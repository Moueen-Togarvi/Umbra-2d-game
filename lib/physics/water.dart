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
/// clipped against the surface line, circles cut into segments) and the
/// water pushes up on that part's centroid with the weight of the water it
/// displaces, so a crate floats as deep as its density says, tips upright
/// or turns over, and settles under a load. The water also drags on what
/// moves through it, towards the speed of its [current].
///
/// The boy cannot swim. He wades slowly where he can stand, and if his
/// head stays under he drowns.
///
/// The surface is a row of springs that ripples where things break it.
/// The water is drawn over whatever is in it, darker with depth, so what
/// is under the surface fades away.
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

  /// The surface's height now (y down); it can rise and fall.
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

  static const double _spacing = 0.15;
  late final int _columns = math.max(2, ((right - left) / _spacing).ceil() + 1);
  late final List<double> _h = List.filled(_columns, 0);
  late final List<double> _v = List.filled(_columns, 0);
  final Map<Body, double> _wet = {};
  final Map<Shape, ShapeGeometry> _geometry = {};

  /// The x extent of the last part found under water.
  double _lastLeft = 0, _lastRight = 0;
  final List<_Drop> _drops = [];
  final math.Random _random = math.Random(4);
  double _time = 0;
  CameraComponent? _camera;
  Stage? _stage;

  /// Raises or lowers the surface to [y] at [speed] m/s.
  void floodTo(double y, {double speed = 0.4}) {
    _target = y;
    _rate = speed;
  }

  bool get isSettled => (level - _target).abs() < 0.005;

  /// Sets the surface at once (water poured in or let out elsewhere).
  void setLevel(double y) {
    level = y.clamp(-1000.0, bottom);
    _target = level;
  }

  /// The surface at [x], ripples included.
  double surfaceAt(double x) {
    final double u = ((x - left) / _spacing).clamp(0, _columns - 1.0);
    final int i = u.floor().clamp(0, _columns - 2);
    final double t = u - i;
    return level + _h[i] * (1 - t) + _h[i + 1] * t;
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
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    final double step = (_target - level).clamp(-_rate * dt, _rate * dt);
    level += step;
    _waves(dt);
    _float(dt);
    _drown(dt);
    for (var i = 0; i < _drops.length; i++) {
      final d = _drops[i];
      d.v.y += GameConfig.gravityMetersPerSecondSquared * dt;
      d.p.add(d.v * dt);
      d.life -= dt;
      if (d.life <= 0 || (d.v.y > 0 && d.p.y > surfaceAt(d.p.x))) {
        _drops.removeAt(i--);
      }
    }
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
      Aabb(Vector2(left, level - 0.3), Vector2(right, bottom)),
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
    final Map<Body, (double, double)> span = {};
    for (final shape in shapes) {
      if (!shape.isValid || shape.isSensor) continue;
      final Body body = shape.body;
      if (body.type != BodyType.dynamic) continue;
      final (double a, double cx, double cy, double j) = _submerged(
        shape,
        body,
      );
      if (a <= 1e-5) continue;
      final (double lo, double hi) =
          span[body] ?? (double.infinity, -double.infinity);
      span[body] = (math.min(lo, _lastLeft), math.max(hi, _lastRight));
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
      final (double lo, double hi) = span[body]!;
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
      // Breaking the surface starts a ripple and throws up spray.
      final double before = _wet[body] ?? 0;
      // (The splash compares wet areas between steps.)
      if (area > before + 1e-3 && body.linearVelocity.y > 1.2) {
        _splash(centroid.x, body.linearVelocity.y, area - before);
      }
    }
    _wet
      ..clear()
      ..addAll({for (final e in wet.entries) e.key: e.value.$1});
  }

  /// The area of [shape] under the surface, its centroid, and its second
  /// moment of area about that centroid.
  (double, double, double, double) _submerged(Shape shape, Body body) {
    // A shape's geometry never changes: read it from the simulation once.
    final geometry = _geometry[shape] ??= shape.geometry;
    switch (geometry) {
      case Circle(:final center, :final radius):
        return _circle(body.worldPoint(center), radius);
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
        return _polygon(points);
      case Polygon(:final points?):
        return _polygon([for (final p in points) body.worldPoint(p)]);
      default:
        return (0, 0, 0, 0);
    }
  }

  (double, double, double, double) _circle(Vector2 c, double r) {
    final double top = c.y - r, low = c.y + r;
    if (low <= level) return (0, 0, 0, 0);
    final double full = math.pi * r * r;
    _lastLeft = c.x - r;
    _lastRight = c.x + r;
    if (top >= level) return (full, c.x, c.y, full * r * r / 2);
    final double h = low - level;
    final double theta = 2 * math.acos(((r - h) / r).clamp(-1.0, 1.0));
    final double area = r * r / 2 * (theta - math.sin(theta));
    final double sinHalf = math.sin(theta / 2);
    final double d = area <= 1e-9
        ? r
        : 4 * r * sinHalf * sinHalf * sinHalf / (3 * (theta - math.sin(theta)));
    return (area, c.x, c.y + d, area * r * r / 4);
  }

  /// Clips a convex polygon to the water (y ≥ level, x within the pool)
  /// and returns its area, centroid and second moment about the centroid.
  (double, double, double, double) _polygon(List<Vector2> points) {
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

    Vector2 atY(Vector2 a, Vector2 b, double y) {
      final double t = (y - a.y) / (b.y - a.y);
      return Vector2(a.x + (b.x - a.x) * t, y);
    }

    Vector2 atX(Vector2 a, Vector2 b, double x) {
      final double t = (x - a.x) / (b.x - a.x);
      return Vector2(x, a.y + (b.y - a.y) * t);
    }

    var p = clip(points, (v) => v.y >= level, (a, b) => atY(a, b, level));
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
    boy.waterDepth = playerDepth;
    // His head: a little below the top of him.
    final double head = at.y - GameConfig.playerHeight * 0.3;
    if (over && head > surfaceAt(at.x) + 0.02) {
      _under += dt;
      if (_under > 0.7) {
        _splash(at.x, 1.5, 0.05);
        boy.die();
      }
    } else {
      _under = 0;
    }
  }

  // ---------------------------------------------------------------------------
  // Ripples and spray
  // ---------------------------------------------------------------------------

  void _splash(double x, double speed, double amount) {
    final int i = ((x - left) / _spacing).round();
    final double push = (speed * 0.035 + amount * 0.4).clamp(0, 0.18);
    for (var k = -3; k <= 3; k++) {
      final int j = i + k;
      if (j < 0 || j >= _columns) continue;
      _v[j] += push * (1 - k.abs() / 4) * 8;
    }
    final int count = (speed * 3).clamp(2, 14).round();
    for (var n = 0; n < count && _drops.length < 80; n++) {
      _drops.add(
        _Drop(
          Vector2(x + (_random.nextDouble() - 0.5) * 0.4, level - 0.02),
          Vector2(
            (_random.nextDouble() - 0.5) * 2.4,
            -(0.8 + _random.nextDouble() * speed * 0.55),
          ),
          0.4 + _random.nextDouble() * 0.5,
          0.012 + _random.nextDouble() * 0.02,
        ),
      );
    }
  }

  void _waves(double dt) {
    // Springs back to flat, a little damping, and spreading sideways; with a
    // faint breathing swell so still water is never quite dead.
    const double stiffness = 70, damping = 5, spread = 0.22;
    for (var i = 0; i < _columns; i++) {
      final double swell = math.sin(_time * 1.3 + i * 0.35) * 0.0015;
      _v[i] += (-stiffness * (_h[i] - swell) - damping * _v[i]) * dt;
    }
    for (var pass = 0; pass < 2; pass++) {
      for (var i = 0; i < _columns; i++) {
        final double l = i > 0 ? _h[i - 1] : _h[i];
        final double r = i < _columns - 1 ? _h[i + 1] : _h[i];
        _v[i] += spread * (l + r - 2 * _h[i]) * 60 * dt;
      }
    }
    for (var i = 0; i < _columns; i++) {
      _h[i] = (_h[i] + _v[i] * dt).clamp(-0.25, 0.25);
    }
  }

  // ---------------------------------------------------------------------------
  // Drawing
  // ---------------------------------------------------------------------------

  final Paint _body = Paint();
  final Paint _line = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _drop = Paint();

  @override
  void render(Canvas canvas) {
    final Rect? view = _camera?.visibleWorldRect;
    final Rect area = Rect.fromLTRB(left, level - 0.3, right, bottom);
    if (view != null && !view.inflate(0.5).overlaps(area)) return;
    final double from = math.max(left, (view?.left ?? left) - 0.3);
    final double to = math.min(right, (view?.right ?? right) + 0.3);
    final Mood mood =
        _stage?.moods.at(_camera?.viewfinder.position.x ?? left) ?? Mood.fog;
    final Color fog = mood.sky[2];
    // The top of the water holds the fog's light, a grey band that darkens
    // to black within a metre and a half: that is what reads as water, and
    // what lets the black of things under it show through faintly.
    final Color top = Color.lerp(fog, const Color(0xFF000000), 0.45)!;
    final Color mid = Color.lerp(fog, const Color(0xFF000000), 0.8)!;
    final path = Path()..moveTo(from, bottom);
    for (double x = from; x <= to; x += _spacing) {
      path.lineTo(x, surfaceAt(x));
    }
    path
      ..lineTo(to, surfaceAt(to))
      ..lineTo(to, bottom)
      ..close();
    _body
      ..color = const Color(0xFFFFFFFF)
      ..shader = Gradient.linear(
        Offset(0, level),
        Offset(0, level + 1.6),
        [
          top.withValues(alpha: 0.78),
          mid.withValues(alpha: 0.9),
          const Color(0xFF020203).withValues(alpha: 0.97),
        ],
        const [0, 0.3, 1],
      );
    canvas.drawPath(path, _body);
    _body.shader = null;
    // The surface catches the light: a subdued rim, and fainter broken
    // ones just under it that drift with the swell.
    final surface = Path()..moveTo(from, surfaceAt(from));
    for (double x = from; x <= to; x += _spacing) {
      surface.lineTo(x, surfaceAt(x));
    }
    final Color shine = Color.lerp(fog, const Color(0xFFFFFFFF), 0.25)!;
    _line
      ..strokeWidth = 0.017
      ..color = shine.withValues(alpha: 0.38);
    canvas.drawPath(surface, _line);
    _line
      ..strokeWidth = 0.016
      ..color = shine.withValues(alpha: 0.28);
    for (final (depth, phase) in const [(0.07, 0.0), (0.16, 2.1), (0.3, 4.0)]) {
      final under = Path();
      var started = false;
      for (double x = from; x <= to; x += 0.25) {
        final double y =
            surfaceAt(x) +
            depth +
            math.sin(x * 2.3 + _time * 0.9 + phase) * 0.012;
        final bool on =
            math.sin(x * 1.9 + phase + _time * (0.4 + current * 0.8)) > 0.1;
        if (on && !started) {
          under.moveTo(x, y);
          started = true;
        } else if (on) {
          under.lineTo(x, y);
        } else {
          started = false;
        }
      }
      canvas.drawPath(under, _line);
    }
    _drop.color = Color.lerp(const Color(0xFF000000), fog, 0.35)!;
    for (final d in _drops) {
      canvas.drawCircle(d.p.toOffset(), d.size, _drop);
    }
  }
}

class _Drop {
  _Drop(this.p, this.v, this.life, this.size);
  final Vector2 p, v;
  double life;
  final double size;
}
