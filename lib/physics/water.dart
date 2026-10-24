import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame/game.dart' show FlameGame;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../entities/player.dart';
import '../render/mood.dart';
import '../world/stage.dart';
import 'collision_layers.dart';

/// A body of still or flowing water: a pool, a flooded chamber, a river.
///
/// Everything dynamic in it floats or sinks by Archimedes: each step the
/// part of every shape below the surface is found exactly (polygons are
/// clipped against the surface as it is under them, waves and all; circles
/// cut into segments) and the water pushes up on that part's centroid with
/// the weight of the water it displaces, so a crate floats as deep as its
/// density says, rides the waves, tips upright or turns over, and settles
/// under a load. The water also drags on what moves through it, towards the
/// speed of its [current].
///
/// The surface is a wave: ripples run out from wherever it is broken, at
/// the speed of shallow water, fade as they go and come back off the ends.
/// What moves in it pushes the water about — a bow wave ahead of a raft or
/// a wading boy, a hollow behind, a ring where something drops in — and
/// a slow swell from somewhere else keeps it alive when nothing does.
///
/// The boy cannot swim. He wades slowly where he can stand, and if his
/// head stays under he drowns, the last of his breath going up in bubbles.
///
/// The water is drawn over whatever is in it, darker with depth, so what
/// is under the surface fades away; its surface catches the light.
class WaterBody extends Component {
  WaterBody({
    required this.left,
    required this.right,
    required double surface,
    required this.bottom,
    this.density = 60,
    this.current = 0,
    this.drag = 3.2,
    this.player,
  }) : level = surface,
       _target = surface,
       super(priority: 45);

  final double left, right, bottom;

  /// The surface's height now (y down), before waves; it can rise and fall.
  double level;
  double _target;
  double _rate = 0.4;

  /// Mass of a square metre of water, in the game's units (a crate of 12 kg
  /// over 1.1 m² is about a fifth of this, and floats high).
  final double density;

  /// The water's flow, m/s along x (a river, or the push of water pouring
  /// in), and how strongly it drags.
  double current;
  final double drag;

  final Player? player;

  /// How long his head has been under.
  double _under = 0;

  /// Whether the boy is in the water at all, and how deep his feet are.
  double playerDepth = 0;

  // The surface: heights (down is positive) and their speeds, one column
  // every [_spacing] metres.
  static const double _spacing = 0.15;

  /// How fast a ripple runs along the surface, m/s, and how quickly it
  /// dies away (per second) and is pulled back flat.
  static const double _waveSpeed = 1.5, _damping = 0.9, _restore = 3.0;
  late final int _columns = math.max(2, ((right - left) / _spacing).ceil() + 1);
  late final List<double> _h = List.filled(_columns, 0);
  late final List<double> _v = List.filled(_columns, 0);
  late final List<double> _scratch = List.filled(_columns, 0);
  final Map<Body, double> _wet = {};
  final Map<Shape, ShapeGeometry> _geometry = {};

  /// Where things break the surface this step: their left and right, for
  /// the foam drawn round them.
  final List<(double, double)> _breaks = [];

  /// The x extent of the last part found under water.
  double _lastLeft = 0, _lastRight = 0;
  final List<_Drop> _drops = [];
  final List<_Ring> _rings = [];
  final List<_Bubble> _bubbles = [];
  final math.Random _random = math.Random(4);
  double _time = 0;
  double _rain = 0, _flowFroth = 0;
  bool _raining = false;
  CameraComponent? _camera;
  Stage? _stage;

  /// Raises or lowers the surface to [y] at [speed] m/s.
  void floodTo(double y, {double speed = 0.4}) {
    _target = y;
    _rate = speed;
  }

  bool get isSettled => (level - _target).abs() < 0.005;

  @override
  void onRemove() {
    player?.reportWaterDepth(this, 0);
    super.onRemove();
  }

  /// Sets the surface at once (water poured in or let out elsewhere).
  void setLevel(double y) {
    level = y.clamp(-1000.0, bottom);
    _target = level;
  }

  /// The slow swell that comes from elsewhere: a few long low waves
  /// crossing, steeper in the rain and running with a current.
  double _swell(double x) {
    final double big = _raining ? 2.6 : 1.0;
    final double t = _time;
    final double drift = current * 0.6;
    return big *
        (0.0055 * math.sin(x * 1.7 - t * (1.1 + drift)) +
            0.0035 * math.sin(x * 3.1 + t * 1.6 - drift * t) +
            0.002 * math.sin(x * 5.3 - t * 2.4));
  }

  /// The surface at [x], waves and swell included.
  double surfaceAt(double x) {
    final double u = ((x - left) / _spacing).clamp(0, _columns - 1.0);
    final int i = u.floor().clamp(0, _columns - 2);
    final double t = u - i;
    // Shallow water has no room to swell.
    final double deep = ((bottom - level) / 0.4).clamp(0.0, 1.0);
    return level + _h[i] * (1 - t) + _h[i + 1] * t + _swell(x) * deep;
  }

  /// Whether [point] is under the surface.
  bool holds(Vector2 point) =>
      point.x >= left &&
      point.x <= right &&
      point.y >= level &&
      point.y <= bottom;

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
    _stage = ancestors().whereType<Stage>().firstOrNull;
    _raining = _stage?.ambience == 'rain';
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    final double step = (_target - level).clamp(-_rate * dt, _rate * dt);
    level += step;
    _breaks.clear();
    _pouring(step, dt);
    _waves(dt);
    _float(dt);
    _drown(dt);
    _raindrops(dt);
    _particles(dt);
  }

  // ---------------------------------------------------------------------------
  // Floating
  // ---------------------------------------------------------------------------

  World? get _world => switch (findGame()) {
    final Forge2DGame g => g.world.physicsWorld,
    _ => null,
  };

  void _float(double dt) {
    final World? world = _world;
    if (world == null) return;
    final shapes = world.overlapAabb(
      Aabb(Vector2(left, level - 0.4), Vector2(right, bottom)),
      filter: QueryFilter(
        categoryBits: CollisionLayers.all,
        maskBits:
            CollisionLayers.prop |
            CollisionLayers.ragdoll |
            CollisionLayers.player,
      ),
    );
    // Per body: wet area, its first moments, and its second moment about
    // the origin (for how hard the water resists it turning).
    final Map<Body, (double, double, double, double)> wet = {};
    final Map<Body, (double, double, double)> span = {};
    for (final shape in shapes) {
      if (!shape.isValid || shape.isSensor) continue;
      final Body body = shape.body;
      if (body.type != BodyType.dynamic) continue;
      final (double a, double cx, double cy, double j) = _submerged(
        shape,
        body,
      );
      if (a <= 1e-5) continue;
      final (double lo, double hi, double top) =
          span[body] ?? (double.infinity, -double.infinity, double.infinity);
      span[body] = (
        math.min(lo, _lastLeft),
        math.max(hi, _lastRight),
        math.min(top, shape.aabb.lowerBound.y),
      );
      final (double pa, double px, double py, double pj) =
          wet[body] ?? (0, 0, 0, 0);
      wet[body] = (
        pa + a,
        px + cx * a,
        py + cy * a,
        pj + j + a * (cx * cx + cy * cy),
      );
    }
    final double g = GameConfig.gravityMetersPerSecondSquared;
    for (final entry in wet.entries) {
      final Body body = entry.key;
      final (double area, double sx, double sy, double so) = entry.value;
      final Vector2 centroid = Vector2(sx / area, sy / area);
      // Second moment of the wet part about its own centroid.
      final double spin = math.max(0, so - area * centroid.length2);
      // Archimedes: the weight of the water pushed aside, pushing up.
      body.applyForce(Vector2(0, -density * area * g), point: centroid);
      final (double lo, double hi, double top) = span[body]!;
      // On a slope of the surface the water runs downhill (towards the
      // side lower down, the larger y), and carries what floats in it a
      // little way with it: the heap a crate pushes up ahead of it holds
      // it back.
      final double slope =
          (surfaceAt(hi) - surfaceAt(lo)) / math.max(0.05, hi - lo);
      body.applyForce(
        Vector2(slope * density * area * g * 0.35, 0),
        point: body.worldCenterOfMass,
      );
      // Drag towards the water's own motion, through the wet part.
      final Vector2 r = centroid - body.worldCenterOfMass;
      final double w = body.angularVelocity;
      final Vector2 v =
          body.linearVelocity +
          Vector2(-w * r.y, w * r.x) -
          Vector2(current, 0);
      final double k = drag * density * area;
      final Vector2 f = v * -k;
      // Never more than stops it this step, so it cannot flip back.
      final double most = body.mass / dt;
      if (f.length > most * v.length) f.scale(most * v.length / f.length);
      body.applyForce(f, point: centroid);
      // Pushed down or lifted, a wide thing has to move a lot of water out
      // of its way first (the water's added mass): a raft dips under a
      // landing, it does not plunge.
      final double wide = math.max(0, hi - lo);
      final double heave = 7 * density * wide * wide;
      final double most3 = body.mass / dt;
      body.applyForce(
        Vector2(0, -v.y * math.min(heave, most3)),
        point: centroid,
      );
      // Water resists turning too, the more the further the wet part
      // reaches from its middle (the water it has to push aside): a raft
      // that he lands on near one end dips there, but does not flip.
      final double resist = 18 * density * spin + body.rotationalInertia * 2;
      final double most2 = body.rotationalInertia / dt;
      body.applyTorque(-w * math.min(resist, most2));
      // And what floats comes to rest square to the water (a crate or a
      // raft weighted low, as they are): drawn to the nearest quarter turn,
      // gently, so a wave rocks it but does not leave it on its corner.
      body.applyTorque(
        -math.sin(4 * body.angle) / 4 * density * g * area * 0.35,
      );
      // What breaks the surface moves the water: it is pushed down and
      // out under something going down, heaped up ahead of something going
      // along and left hollow behind it.
      final bool atSurface = top < surfaceAt((lo + hi) / 2) + 0.05;
      if (atSurface) {
        _breaks.add((lo, hi));
        _stir(lo, hi, body.linearVelocity, dt);
      }
      // Breaking the surface starts a ripple and throws up spray: once,
      // as it first goes in.
      final double before = _wet[body] ?? 0;
      if (before <= 1e-4 && body.linearVelocity.y > 1.2) {
        _splash(centroid.x, body.linearVelocity.y, area - before);
      }
    }
    _wet
      ..clear()
      ..addAll({for (final e in wet.entries) e.key: e.value.$1});
  }

  int _column(double x) =>
      ((x - left) / _spacing).round().clamp(0, _columns - 1);

  /// A push to the surface's speed at [x], spread smoothly over the
  /// columns round it rather than all on one.
  void _push(double x, double amount, {int reach = 3}) {
    final int c = _column(x);
    for (var k = -reach; k <= reach; k++) {
      final int j = c + k;
      if (j < 0 || j >= _columns) continue;
      final double w = math.cos(k / (reach + 1) * math.pi / 2);
      _v[j] += amount * w * w;
    }
  }

  /// The water pushed about by something between [lo] and [hi] moving at
  /// [velocity].
  void _stir(double lo, double hi, Vector2 velocity, double dt) {
    final int a = _column(lo), b = _column(hi);
    // Going down it presses the surface under it down, which the waves
    // carry out to either side; coming up, the other way.
    final double press = velocity.y.clamp(-3.0, 3.0) * 0.3 * dt * 60;
    for (var j = a; j <= b; j++) {
      _v[j] += press * 0.02;
    }
    // Along: a heap ahead, a hollow behind, as deep as it goes fast
    // through the water (what drifts with a current leaves no wake).
    final double along = (velocity.x - current).clamp(-4.0, 4.0);
    if (along.abs() > 0.15) {
      final double push = along.abs() * 0.022 * dt * 60;
      final double ahead = along > 0 ? hi + 0.15 : lo - 0.15;
      final double behind = along > 0 ? lo - 0.15 : hi + 0.15;
      _push(ahead, -push * 0.45, reach: 2);
      _push(behind, push * 0.3, reach: 2);
    }
  }

  /// The area of [shape] under the surface, its centroid, and its second
  /// moment of area about that centroid.
  (double, double, double, double) _submerged(Shape shape, Body body) {
    // A shape's geometry never changes: read it from the simulation once.
    final geometry = _geometry[shape] ??= shape.geometry;
    // The surface round it, as a straight line between its two sides: a
    // raft on a wave rides it, tilting. Read just outside it, where the
    // water is free: the hollow it presses into the surface under itself
    // is not water it floats on (the water pushed aside is what lifts it).
    final box = shape.aabb;
    final double x0 = box.lowerBound.x, x1 = box.upperBound.x;
    final double y0 = surfaceAt(x0 - 0.15), y1 = surfaceAt(x1 + 0.15);
    final double mid = (y0 + y1) / 2;
    // It rides up and down with the waves in full, but takes only a little
    // of their slope: a crate tilts with a wave, it is not tipped over by
    // one.
    double surface(double x) => x1 - x0 < 1e-6
        ? mid
        : mid + (y1 - y0) * 0.3 * ((x - (x0 + x1) / 2) / (x1 - x0));
    switch (geometry) {
      case Circle(:final center, :final radius):
        final c = body.worldPoint(center);
        return _circle(c, radius, surface(c.x));
      case Capsule(:final center1, :final center2, :final radius):
        // As a polygon round its outline.
        final a = body.worldPoint(center1), b = body.worldPoint(center2);
        final Vector2 axis = (b - a)..normalize();
        final Vector2 n = Vector2(-axis.y, axis.x);
        final points = <Vector2>[];
        for (var i = 0; i <= 6; i++) {
          final double t = math.pi * i / 6;
          points.add(b + (axis * math.sin(t) + n * math.cos(t)) * radius);
        }
        for (var i = 0; i <= 6; i++) {
          final double t = math.pi * i / 6;
          points.add(a + (axis * -math.sin(t) - n * math.cos(t)) * radius);
        }
        return _polygon(points, surface);
      case Polygon(:final points?):
        return _polygon([for (final p in points) body.worldPoint(p)], surface);
      default:
        return (0, 0, 0, 0);
    }
  }

  (double, double, double, double) _circle(Vector2 c, double r, double at) {
    final double top = c.y - r, low = c.y + r;
    if (low <= at) return (0, 0, 0, 0);
    final double full = math.pi * r * r;
    _lastLeft = c.x - r;
    _lastRight = c.x + r;
    if (top >= at) return (full, c.x, c.y, full * r * r / 2);
    final double h = low - at;
    final double theta = 2 * math.acos(((r - h) / r).clamp(-1.0, 1.0));
    final double area = r * r / 2 * (theta - math.sin(theta));
    final double sinHalf = math.sin(theta / 2);
    final double d = area <= 1e-9
        ? r
        : 4 * r * sinHalf * sinHalf * sinHalf / (3 * (theta - math.sin(theta)));
    return (area, c.x, c.y + d, area * r * r / 4);
  }

  /// Clips a convex polygon to the water (below the [surface] line, within
  /// the pool) and returns its area, centroid and second moment about the
  /// centroid.
  (double, double, double, double) _polygon(
    List<Vector2> points,
    double Function(double x) surface,
  ) {
    List<Vector2> clip(
      List<Vector2> p,
      bool Function(Vector2) inside,
      Vector2 Function(Vector2, Vector2) cut,
    ) {
      final out = <Vector2>[];
      for (var i = 0; i < p.length; i++) {
        final a = p[i], b = p[(i + 1) % p.length];
        final bool ia = inside(a), ib = inside(b);
        if (ia) out.add(a);
        if (ia != ib) out.add(cut(a, b));
      }
      return out;
    }

    // Where the edge from a to b crosses the (straight) surface line.
    Vector2 atSurface(Vector2 a, Vector2 b) {
      final double da = a.y - surface(a.x), db = b.y - surface(b.x);
      final double t = da / (da - db);
      return a + (b - a) * t;
    }

    Vector2 atX(Vector2 a, Vector2 b, double x) {
      final double t = (x - a.x) / (b.x - a.x);
      return Vector2(x, a.y + (b.y - a.y) * t);
    }

    var p = clip(points, (v) => v.y >= surface(v.x), atSurface);
    if (p.length < 3) return (0, 0, 0, 0);
    p = clip(p, (v) => v.x >= left, (a, b) => atX(a, b, left));
    if (p.length < 3) return (0, 0, 0, 0);
    p = clip(p, (v) => v.x <= right, (a, b) => atX(a, b, right));
    if (p.length < 3) return (0, 0, 0, 0);
    _lastLeft = p.map((v) => v.x).reduce(math.min);
    _lastRight = p.map((v) => v.x).reduce(math.max);
    double area = 0, cx = 0, cy = 0, j = 0;
    // Measured from the first vertex, to keep the numbers small.
    final Vector2 o = p.first;
    for (var i = 0; i < p.length; i++) {
      final a = p[i] - o, b = p[(i + 1) % p.length] - o;
      final double cross = a.x * b.y - b.x * a.y;
      area += cross;
      cx += (a.x + b.x) * cross;
      cy += (a.y + b.y) * cross;
      j +=
          cross *
          (a.x * a.x +
              a.x * b.x +
              b.x * b.x +
              a.y * a.y +
              a.y * b.y +
              b.y * b.y);
    }
    area /= 2;
    if (area.abs() < 1e-9) return (0, 0, 0, 0);
    final double gx = cx / (6 * area), gy = cy / (6 * area);
    // Polar moment about the first vertex, moved to the centroid.
    final double polar = (j / 12).abs() - area.abs() * (gx * gx + gy * gy);
    return (area.abs(), o.x + gx, o.y + gy, math.max(0, polar));
  }

  // ---------------------------------------------------------------------------
  // The boy
  // ---------------------------------------------------------------------------

  void _drown(double dt) {
    final Player? boy = player;
    if (boy == null || !boy.isMounted || boy.isDead) {
      _under = 0;
      playerDepth = 0;
      return;
    }
    final Vector2 at = boy.cameraPosition;
    final double feet = at.y + GameConfig.playerHeight / 2;
    final bool over = at.x > left && at.x < right;
    playerDepth = over ? math.max(0, feet - surfaceAt(at.x)) : 0;
    boy.reportWaterDepth(this, playerDepth);
    // His head: a little below the top of him.
    final double head = at.y - GameConfig.playerHeight * 0.3;
    if (over && head > surfaceAt(at.x) + 0.02) {
      _under += dt;
      // His breath going, a bubble at a time, then all at once.
      final double rate = _under < 0.45 ? 5 : 22;
      if (_random.nextDouble() < rate * dt) {
        _bubble(at.x + (_random.nextDouble() - 0.5) * 0.15, head - 0.05);
      }
      if (_under > 0.7) {
        _splash(at.x, 1.5, 0.05);
        for (var i = 0; i < 8; i++) {
          _bubble(at.x + (_random.nextDouble() - 0.5) * 0.3, head);
        }
        boy.die();
      }
    } else {
      _under = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Ripples, spray, bubbles, rain
  // ---------------------------------------------------------------------------

  void _bubble(double x, double y) {
    if (_bubbles.length > 60 || x < left || x > right) return;
    _bubbles.add(
      _Bubble(
        Vector2(x, y),
        0.012 + _random.nextDouble() * 0.025,
        _random.nextDouble() * 6,
      ),
    );
  }

  void _splash(double x, double speed, double amount) {
    final int i = _column(x);
    final double push = (speed * 0.035 + amount * 0.4).clamp(0, 0.18);
    for (var k = -3; k <= 3; k++) {
      final int j = i + k;
      if (j < 0 || j >= _columns) continue;
      _v[j] += push * (1 - k.abs() / 4) * 3;
    }
    final double y = surfaceAt(x);
    _rings.add(_Ring(x, 0.05, 0.6 + push * 2));
    final int count = (speed * 4).clamp(3, 18).round();
    for (var n = 0; n < count && _drops.length < 90; n++) {
      final double side = _random.nextDouble() - 0.5;
      _drops.add(
        _Drop(
          Vector2(x + side * 0.35, y - 0.02),
          Vector2(
            side * 3.2 + (_random.nextDouble() - 0.5) * 0.6,
            -(0.9 + _random.nextDouble() * speed * 0.65),
          ),
          0.5 + _random.nextDouble() * 0.5,
          0.012 + _random.nextDouble() * 0.022,
        ),
      );
    }
    for (var n = 0; n < (count / 3).round(); n++) {
      _bubble(x + (_random.nextDouble() - 0.5) * 0.4, y + 0.1 + n * 0.05);
    }
  }

  /// While the water rises or falls the surface churns where it pours in
  /// or drains away, and froths.
  void _pouring(double step, double dt) {
    final double flow = step.abs() / math.max(dt, 1e-6);
    _flowFroth +=
        ((flow > 0.02 ? 1.0 : 0.0) - _flowFroth) * math.min(1, dt * 3);
    if (flow <= 0.02) return;
    // In at the left end, out at the right (where the rooms' drains are).
    final double x = step < 0 ? left + 0.4 : right - 0.4;
    _push(x, (_random.nextDouble() - 0.5) * flow * 0.9);
    if (_random.nextDouble() < flow * 30 * dt) {
      _bubble(x + (_random.nextDouble() - 0.5) * 0.6, level + 0.25);
    }
  }

  void _raindrops(double dt) {
    if (!_raining) return;
    _rain += dt * (right - left) * 3;
    while (_rain > 1) {
      _rain -= 1;
      final double x = left + _random.nextDouble() * (right - left);
      _push(x, 0.03, reach: 1);
      if (_rings.length < 40) _rings.add(_Ring(x, 0.01, 0.35));
    }
  }

  void _particles(double dt) {
    for (var i = 0; i < _drops.length; i++) {
      final d = _drops[i];
      d.v.y += GameConfig.gravityMetersPerSecondSquared * dt;
      d.p.add(d.v * dt);
      d.life -= dt;
      if (d.life <= 0 || (d.v.y > 0 && d.p.y > surfaceAt(d.p.x))) {
        // A drop falling back makes its own little ring.
        if (d.life > 0 && _rings.length < 40) {
          _rings.add(_Ring(d.p.x, 0.005, 0.25));
        }
        _drops.removeAt(i--);
      }
    }
    for (var i = 0; i < _rings.length; i++) {
      final r = _rings[i];
      r.age += dt;
      if (r.age > r.life) _rings.removeAt(i--);
    }
    for (var i = 0; i < _bubbles.length; i++) {
      final b = _bubbles[i];
      b.p.y -= (0.55 + b.r * 12) * dt;
      b.p.x += math.sin(_time * 7 + b.phase) * 0.12 * dt;
      if (b.p.y < surfaceAt(b.p.x) + b.r) {
        if (_rings.length < 40) _rings.add(_Ring(b.p.x, 0.003, 0.3));
        _bubbles.removeAt(i--);
      }
    }
  }

  /// The surface as a wave: each column is pulled by its neighbours (the
  /// wave equation, so ripples travel at [_waveSpeed]), loses a little to
  /// friction, and is drawn slowly back to flat; the ends reflect. With a
  /// current, what is on the surface is carried downstream.
  void _waves(double dt) {
    const int substeps = 2;
    final double h = dt / substeps;
    const double c2 = _waveSpeed * _waveSpeed / (_spacing * _spacing);
    for (var s = 0; s < substeps; s++) {
      for (var i = 0; i < _columns; i++) {
        final double l = i > 0 ? _h[i - 1] : _h[i];
        final double r = i < _columns - 1 ? _h[i + 1] : _h[i];
        _v[i] +=
            (c2 * (l + r - 2 * _h[i]) - _restore * _h[i] - _damping * _v[i]) *
            h;
      }
      for (var i = 0; i < _columns; i++) {
        _h[i] = (_h[i] + _v[i] * h).clamp(-0.12, 0.12);
      }
      // A little viscosity: the shortest ripples (a column or two long)
      // die first, so the surface stays smooth.
      for (var i = 0; i < _columns; i++) {
        final double l = i > 0 ? _v[i - 1] : _v[i];
        final double r = i < _columns - 1 ? _v[i + 1] : _v[i];
        _scratch[i] = _v[i] + 0.18 * (l + r - 2 * _v[i]);
      }
      for (var i = 0; i < _columns; i++) {
        _v[i] = _scratch[i];
      }
    }
    if (current.abs() > 0.01) {
      // Carried along (upwind), so a river's ripples run downstream.
      final double k = (current * dt / _spacing).clamp(-0.9, 0.9);
      for (var i = 0; i < _columns; i++) {
        final int up = k > 0
            ? math.max(0, i - 1)
            : math.min(_columns - 1, i + 1);
        _scratch[i] = _h[i] - k.abs() * (_h[i] - _h[up]);
      }
      for (var i = 0; i < _columns; i++) {
        _h[i] = _scratch[i];
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Drawing
  // ---------------------------------------------------------------------------

  final Paint _body = Paint();
  final Paint _glow = Paint();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _fill = Paint();
  final Path _surfacePath = Path(), _bodyPath = Path(), _scratchPath = Path();

  /// The solid things standing in the water (steps, walls), so the water
  /// is not drawn over them; found once they are all there.
  Path? _solids;
  bool _anySolid = false;
  double _solidsAt = -1;

  Path _findSolids() {
    final path = Path();
    final World? world = _world;
    if (world == null) return path;
    for (final shape in world.overlapAabb(
      Aabb(Vector2(left, level - 6), Vector2(right, bottom - 0.02)),
      filter: QueryFilter(
        categoryBits: CollisionLayers.all,
        maskBits: CollisionLayers.terrain,
      ),
    )) {
      if (!shape.isValid ||
          shape.isSensor ||
          shape.body.type != BodyType.static) {
        continue;
      }
      final geometry = shape.geometry;
      if (geometry is! Polygon) continue;
      final points = geometry.points;
      if (points == null || points.length < 3) continue;
      // Only what stands up out of the pool's floor, not the floor itself.
      final box = shape.aabb;
      if (box.lowerBound.y > bottom - 0.05) continue;
      path.addPolygon([
        for (final p in points) shape.body.worldPoint(p).toOffset(),
      ], true);
    }
    return path;
  }

  @override
  void render(Canvas canvas) {
    final Rect? view = _camera?.visibleWorldRect;
    final Rect area = Rect.fromLTRB(left, level - 0.4, right, bottom);
    if (view != null && !view.inflate(0.5).overlaps(area)) return;
    final double depth = bottom - level;
    if (depth < 0.015) return;
    final double from = math.max(left, (view?.left ?? left) - 0.3);
    final double to = math.min(right, (view?.right ?? right) + 0.3);
    if (_solidsAt < 0 || (_time - _solidsAt > 2 && _time < 6)) {
      _solids = _findSolids();
      _anySolid = _solids!.computeMetrics().isNotEmpty;
      _solidsAt = _time;
    }
    final Path? solids = _solids;
    canvas.save();
    if (solids != null && _anySolid) {
      canvas.clipPath(
        Path.combine(
          PathOperation.difference,
          Path()..addRect(area.inflate(1)),
          solids,
        ),
      );
    }
    final Mood mood =
        _stage?.moods.at(_camera?.viewfinder.position.x ?? left) ?? Mood.fog;
    final Color fog = mood.sky[2];
    const Color black = Color(0xFF000000);
    final Color white = Color.lerp(fog, const Color(0xFFFFFFFF), 0.55)!;

    // The surface, sampled once and used for everything below.
    final List<Offset> top = [];
    for (double x = from; x < to; x += _spacing / 2) {
      top.add(Offset(x, surfaceAt(x)));
    }
    top.add(Offset(to, surfaceAt(to)));
    void smooth(Path path, List<Offset> points) {
      path.moveTo(points.first.dx, points.first.dy);
      for (var i = 1; i < points.length - 1; i++) {
        final Offset m = (points[i] + points[i + 1]) / 2;
        path.quadraticBezierTo(points[i].dx, points[i].dy, m.dx, m.dy);
      }
      path.lineTo(points.last.dx, points.last.dy);
    }

    _surfacePath.reset();
    smooth(_surfacePath, top);
    _bodyPath.reset();
    smooth(_bodyPath, top);
    _bodyPath
      ..lineTo(to, bottom)
      ..lineTo(from, bottom)
      ..close();

    // The water: the fog's light held in its top, going murky and then
    // black within a metre and a half; shallow water is clearer.
    final double clear = (1 - depth / 0.6).clamp(0.0, 1.0);
    final Color upper = Color.lerp(fog, black, 0.42)!;
    final Color murk = Color.lerp(fog, black, 0.78)!;
    _body.shader = Gradient.linear(
      Offset(0, level - 0.05),
      Offset(0, level + 1.6),
      [
        upper.withValues(alpha: 0.62 - clear * 0.3),
        murk.withValues(alpha: 0.86 - clear * 0.3),
        const Color(0xFF020203).withValues(alpha: 0.97),
      ],
      const [0, 0.35, 1],
    );
    canvas.drawPath(_bodyPath, _body);
    _body.shader = null;

    // Just under the surface, a band of light that moves with the waves.
    _glow.shader = Gradient.linear(
      Offset(0, level - 0.02),
      Offset(0, level + 0.22),
      [white.withValues(alpha: 0.2), white.withValues(alpha: 0)],
    );
    _scratchPath
      ..reset()
      ..addPolygon([
        ...top,
        for (final p in top.reversed) p + const Offset(0, 0.22),
      ], true);
    canvas.drawPath(_scratchPath, _glow);
    _glow.shader = null;

    // Caustics: the light the surface bends, a net of faint lines wavering
    // a little way down, fading with depth.
    if (depth > 0.25) {
      for (final (down, phase, alpha) in const [
        (0.12, 0.0, 0.16),
        (0.28, 1.7, 0.11),
        (0.5, 3.3, 0.07),
      ]) {
        if (down > depth - 0.05) break;
        _line
          ..strokeWidth = 0.014
          ..color = white.withValues(alpha: alpha);
        _scratchPath.reset();
        var drawing = false;
        for (double x = from; x <= to; x += 0.12) {
          final double y =
              surfaceAt(x) +
              down +
              math.sin(x * 4.1 + _time * 1.3 + phase) * 0.025 +
              math.sin(x * 9.7 - _time * 2.2) * 0.008;
          final bool on =
              math.sin(x * 2.3 + phase * 2 + _time * (0.7 + current)) +
                  math.sin(x * 5.9 - _time * 1.1) * 0.5 >
              0.25;
          if (on && !drawing) {
            _scratchPath.moveTo(x, y);
            drawing = true;
          } else if (on) {
            _scratchPath.lineTo(x, y);
          } else {
            drawing = false;
          }
        }
        canvas.drawPath(_scratchPath, _line);
      }
    }

    // The surface itself: a fine bright line, brighter on the crests,
    // with glints that come and go where the light catches it.
    _line
      ..strokeWidth = 0.02
      ..color = white.withValues(alpha: 0.55);
    canvas.drawPath(_surfacePath, _line);
    _line.strokeWidth = 0.028;
    for (var i = 1; i < top.length; i++) {
      final double x = top[i].dx;
      final double glint =
          math.sin(x * 7.3 + _time * 2.1) * math.sin(x * 3.1 - _time * 1.3);
      // Crests (the surface higher than the level) catch more light.
      final double crest = ((level - top[i].dy) * 30).clamp(0.0, 1.0);
      final double a = (glint - 0.55).clamp(0.0, 1.0) * 1.6 + crest * 0.35;
      if (a <= 0.03) continue;
      _line.color = white.withValues(alpha: math.min(0.85, a));
      canvas.drawLine(top[i - 1], top[i], _line);
    }

    // Foam: along the ends, where the water meets the walls, round
    // whatever breaks the surface, and more while it pours in or out.
    _fill.color = white.withValues(alpha: 0.32);
    void foam(double x0, double x1, double thick) {
      for (double x = math.max(from, x0); x <= math.min(to, x1); x += 0.07) {
        final double n = math.sin(x * 31 + _time * 3) * 0.5 + 0.5;
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(x, surfaceAt(x) + 0.005),
            width: 0.06 + n * 0.05,
            height: thick * (0.5 + n * 0.5),
          ),
          _fill,
        );
      }
    }

    foam(left, left + 0.18, 0.025);
    foam(right - 0.18, right, 0.025);
    for (final (lo, hi) in _breaks) {
      foam(lo - 0.12, lo + 0.05, 0.03);
      foam(hi - 0.05, hi + 0.12, 0.03);
    }
    if (_flowFroth > 0.05) {
      _fill.color = white.withValues(alpha: 0.35 * _flowFroth);
      foam(left, left + 1.2, 0.04);
      foam(right - 1.2, right, 0.04);
    }

    // Rings spreading where something broke the surface.
    for (final r in _rings) {
      if (r.x < from - 1 || r.x > to + 1) continue;
      final double t = r.age / r.life;
      final double w = r.size + t * (0.5 + r.size * 4);
      _line
        ..strokeWidth = 0.012
        ..color = white.withValues(alpha: 0.45 * (1 - t));
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset(r.x, surfaceAt(r.x)),
          width: w * 2,
          height: w * 0.22,
        ),
        _line,
      );
    }

    // Bubbles going up, and spray: drops drawn along their path.
    _line
      ..strokeWidth = 0.008
      ..color = white.withValues(alpha: 0.5);
    for (final b in _bubbles) {
      canvas.drawCircle(b.p.toOffset(), b.r, _line);
    }
    _fill.color = Color.lerp(black, fog, 0.55)!;
    _line.color = Color.lerp(black, fog, 0.55)!;
    for (final d in _drops) {
      final Offset p = d.p.toOffset();
      _line.strokeWidth = d.size;
      canvas.drawLine(p, p - (d.v * 0.025).toOffset(), _line);
      canvas.drawCircle(p, d.size * 0.6, _fill);
    }
    canvas.restore();
  }
}

class _Drop {
  _Drop(this.p, this.v, this.life, this.size);
  final Vector2 p, v;
  double life;
  final double size;
}

class _Ring {
  _Ring(this.x, this.size, this.life);
  final double x, size, life;
  double age = 0;
}

class _Bubble {
  _Bubble(this.p, this.r, this.phase);
  final Vector2 p;
  final double r, phase;
}
