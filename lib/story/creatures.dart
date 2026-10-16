import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart' show FlameGame;

import '../entities/player.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../world/stage.dart';

/// A flock of bats: each one a boid that keeps its distance from the
/// others, flies with them and towards them, and is steered by where the
/// flock is going. Until disturbed they hang unseen in their roost; the
/// boy coming near, or a scene, sends them out.
class BatFlock extends Component {
  BatFlock({
    required this.roost,
    this.count = 14,
    this.player,
    this.wakeDistance = 4,
    int seed = 3,
  }) : _random = math.Random(seed),
       super(priority: 30);

  /// Where they hang, world metres.
  final Vector2 roost;
  final int count;

  /// They burst out when he passes within [wakeDistance] of the roost.
  final Player? player;
  final double wakeDistance;

  final math.Random _random;
  final List<Bat> bats = [];
  bool awake = false;

  /// Where the flock is heading, and for how long more.
  Vector2 _goal = Vector2.zero();
  double _goalTime = 0;
  final List<Vector2> _route = [];
  CameraComponent? _camera;
  double _time = 0;

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
    for (var i = 0; i < count; i++) {
      bats.add(
        Bat(
          roost +
              Vector2(_random.nextDouble() - 0.5, _random.nextDouble() * 0.4),
          _random.nextDouble() * math.pi * 2,
          0.75 + _random.nextDouble() * 0.5,
        ),
      );
    }
  }

  /// Out of the roost, away up and over towards [to] and off screen.
  void scatter({Vector2? to}) {
    if (awake) return;
    awake = true;
    for (final bat in bats) {
      bat.velocity.setValues(
        (_random.nextDouble() - 0.5) * 4,
        -2 - _random.nextDouble() * 3,
      );
    }
    _route
      ..clear()
      ..add(roost + Vector2(0, -3))
      ..add(to ?? roost + Vector2(14, -6));
    _next();
  }

  /// A swarm streaming along [path] (world points), then away.
  void swarm(List<Vector2> path) {
    awake = true;
    for (final bat in bats) {
      bat.position.setFrom(
        path.first +
            Vector2(_random.nextDouble() * 2 - 1, _random.nextDouble() * 1.5),
      );
      bat.velocity.setValues(3, 0);
    }
    _route
      ..clear()
      ..addAll(path.skip(1));
    _next();
  }

  void _next() {
    if (_route.isEmpty) {
      _goal = Vector2.zero();
      return;
    }
    _goal = _route.removeAt(0);
    _goalTime = 4;
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    final Player? boy = player;
    if (!awake &&
        boy != null &&
        boy.isMounted &&
        (boy.body.position - roost).length < wakeDistance) {
      scatter();
    }
    if (!awake) return;
    Vector2 centre = Vector2.zero();
    for (final bat in bats) {
      centre += bat.position;
    }
    centre /= bats.length.toDouble();
    if (_goal != Vector2.zero()) {
      _goalTime -= dt;
      if ((centre - _goal).length < 1.5 || _goalTime <= 0) _next();
    }
    for (final bat in bats) {
      final Vector2 steer = Vector2.zero();
      Vector2 align = Vector2.zero();
      var near = 0;
      for (final other in bats) {
        if (identical(other, bat)) continue;
        final Vector2 d = bat.position - other.position;
        final double l = d.length;
        if (l < 0.35 && l > 1e-4) steer.add(d / (l * l) * 0.08);
        if (l < 1.5) {
          align += other.velocity;
          near++;
        }
      }
      if (near > 0) steer.add((align / near.toDouble() - bat.velocity) * 0.8);
      steer.add((centre - bat.position) * 0.5);
      if (_goal != Vector2.zero()) {
        final Vector2 to = _goal - bat.position;
        steer.add(to.normalized() * 6);
      } else {
        // Done: away up and out of the picture.
        steer.add(Vector2(bat.velocity.x.sign * 3, -4));
      }
      // Each one jinks a little on its own.
      steer.add(
        Vector2(
              math.sin(_time * 5.1 * bat.temper + bat.phase),
              math.cos(_time * 4.3 * bat.temper + bat.phase * 1.7),
            ) *
            4,
      );
      bat.velocity.add(steer * dt);
      final double speed = bat.velocity.length;
      const double top = 7.5, least = 3;
      if (speed > top) bat.velocity.scale(top / speed);
      if (speed < least && speed > 1e-4) bat.velocity.scale(least / speed);
      bat.position.add(bat.velocity * dt);
      bat.flap += dt * (13 + bat.temper * 4);
    }
  }

  final Paint _paint = Paint()..color = const Color(0xFF040404);

  @override
  void render(Canvas canvas) {
    if (!awake) return;
    final Rect? view = _camera?.visibleWorldRect;
    for (final bat in bats) {
      if (view != null && !view.inflate(1).contains(bat.position.toOffset())) {
        continue;
      }
      _drawBat(canvas, bat);
    }
  }

  void _drawBat(Canvas canvas, Bat bat) {
    final double s = 0.16 * bat.temper;
    final double beat = math.sin(bat.flap);
    final double dir = bat.velocity.x >= 0 ? 1 : -1;
    final Offset c = bat.position.toOffset();
    // Wings: two jointed membranes, up and down with the beat; seen from
    // the side the far one is mostly hidden behind the body.
    final double up = beat * 0.9;
    for (final side in [1.0, -0.55]) {
      final Offset elbow = c + Offset(-dir * s * 0.3, -s * up * side - s * 0.1);
      final Offset tip =
          elbow + Offset(-dir * s * 0.55, -s * up * side * 0.6 + s * 0.2);
      canvas.drawPath(
        Path()
          ..moveTo(c.dx + dir * s * 0.12, c.dy - s * 0.05)
          ..lineTo(elbow.dx, elbow.dy)
          ..lineTo(tip.dx, tip.dy)
          ..quadraticBezierTo(
            (tip.dx + c.dx) / 2,
            (tip.dy + c.dy) / 2 + s * 0.25,
            c.dx - dir * s * 0.1,
            c.dy + s * 0.05,
          )
          ..close(),
        _paint,
      );
    }
    canvas.drawOval(
      Rect.fromCenter(center: c, width: s * 0.5, height: s * 0.28),
      _paint,
    );
    // Ears.
    canvas.drawPath(
      Path()
        ..moveTo(c.dx + dir * s * 0.18, c.dy - s * 0.08)
        ..lineTo(c.dx + dir * s * 0.24, c.dy - s * 0.24)
        ..lineTo(c.dx + dir * s * 0.28, c.dy - s * 0.06)
        ..close(),
      _paint,
    );
  }
}

/// One bat of a [BatFlock].
class Bat {
  Bat(this.position, this.phase, this.temper);
  final Vector2 position;
  final Vector2 velocity = Vector2.zero();
  final double phase, temper;
  double flap = 0;
}

/// A pair of eyes in the dark undergrowth, watching: pale, blinking now
/// and then. When the boy comes near they go out, as whatever it is
/// shrinks back. Drawn among the fog layers at its [depth].
class WatchingEyes extends Component implements BackdropDrawable {
  WatchingEyes({
    required this.x,
    required this.y,
    this.depth = 0.9,
    this.player,
    this.shyDistance = 4.5,
    this.color = const Color(0xFFE9E4D2),
    int seed = 1,
  }) : _random = math.Random(seed);

  final double x, y;
  @override
  final double depth;
  final Player? player;
  final double shyDistance;
  final Color color;
  final math.Random _random;
  Stage? _stage;
  double _open = 0;
  double _blink = 0;
  double _nextBlink = 2;
  bool gone = false;
  final Paint _paint = Paint();

  @override
  Future<void> onLoad() async {
    _stage = ancestors().whereType<Stage>().firstOrNull;
    if (depth < 0.85) _stage?.backdropProps.add(this);
  }

  @override
  void onRemove() {
    _stage?.backdropProps.remove(this);
    super.onRemove();
  }

  @override
  void update(double dt) {
    final Player? boy = player;
    if (boy != null &&
        boy.isMounted &&
        (boy.body.position.x - x).abs() < shyDistance) {
      gone = true;
    }
    final double target = gone ? 0 : 1;
    _open += (target - _open) * math.min(1, dt * (gone ? 6 : 0.8));
    _nextBlink -= dt;
    if (_nextBlink <= 0) {
      _blink = 0.16;
      _nextBlink = 1.5 + _random.nextDouble() * 4;
    }
    if (_blink > 0) _blink -= dt;
  }

  @override
  void render(Canvas canvas) {
    if (depth < 0.85 && _stage != null) return;
    paint(canvas, Vector2(x, y), Mood.night);
  }

  @override
  void paint(Canvas canvas, Vector2 cam, Mood mood) {
    final double shut = _blink > 0 ? 0.15 : 1;
    final double a = _open;
    if (a < 0.01) return;
    final double k = depth;
    final Offset at = Offset(cam.x + (x - cam.x) * k, cam.y + (y - cam.y) * k);
    final double r = 0.035 * k;
    for (final dx in [-0.09 * k, 0.09 * k]) {
      final Offset e = at + Offset(dx, 0);
      // Opaque: a shader paints at the paint colour's opacity.
      _paint.color = const Color(0xFFFFFFFF);
      _paint.shader = Gradient.radial(e, r * 4, [
        color.withValues(alpha: 0.25 * a),
        color.withValues(alpha: 0),
      ]);
      canvas.drawCircle(e, r * 4, _paint);
      _paint
        ..shader = null
        ..color = color.withValues(alpha: a);
      canvas.drawOval(
        Rect.fromCenter(center: e, width: r * 2.4, height: r * 1.6 * shut),
        _paint,
      );
    }
  }
}
