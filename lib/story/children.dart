import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show Body;

import '../character/character_interactions.dart';
import '../config/game_config.dart';
import '../world/stage.dart';
import 'figures.dart';

/// The way the boy has come, kept as points every few centimetres of his
/// travel, so that others can walk it behind him.
class Trail {
  final List<Vector2> _points = [];
  static const double spacing = 0.05;

  void record(Vector2 feet) {
    if (_points.isEmpty || (_points.last - feet).length >= spacing) {
      _points.add(feet.clone());
      // A long walk is not kept for ever.
      if (_points.length > 4000) _points.removeRange(0, 1000);
    }
  }

  void clear() => _points.clear();

  /// The point [back] metres of travel behind the newest one, or null if
  /// the trail is not that long.
  Vector2? behind(double back) {
    if (_points.isEmpty) return null;
    final int steps = (back / spacing).round();
    final int i = _points.length - 1 - steps;
    return i < 0 ? null : _points[i];
  }
}

/// One of the stolen children: small, thin, with the same pale eyes as the
/// boy. Shut in a cell until he opens it; then it follows him, walking the
/// way he went a few steps behind, and stops when he stops. Close behind
/// him while he pushes, it pushes too.
class Child extends Component {
  Child({
    required this.home,
    required this.groundY,
    required this.index,
    this.height = 0.92,
    super.priority = 2,
  }) : _at = Vector2(home, groundY);

  /// Where it waits in its cell, and its place in the line behind him.
  final double home, groundY;
  final int index;
  final double height;

  /// Following him (out of its cell).
  bool following = false;

  /// Gone (out through a hole too small for him).
  bool gone = false;

  final Vector2 _at;
  double _facing = 1;
  double _gait = 0;
  double _time = 0;
  final Calm _speed = Calm(0, hertz: 3);

  /// Where its feet are, world metres.
  Vector2 get feet => _at;

  /// How far behind him it walks.
  double get back => 1.0 + index * 0.85;

  /// Back in its cell (after a death undid the boy's work).
  void reset() {
    following = false;
    gone = false;
    _at.setValues(home, groundY);
  }

  /// Walks along [trail] to its place in the line, at most at running
  /// speed; [goal], if given, overrides the trail (a scripted walk).
  void step(double dt, Trail trail, {Vector2? goal}) {
    if (dt <= 0) return;
    _time += dt;
    final Vector2? target = goal ?? (following ? trail.behind(back) : null);
    double moved = 0;
    if (target != null) {
      final Vector2 d = target - _at;
      final double dist = d.length;
      final double most = GameConfig.moveSpeedMetersPerSecond * 1.2 * dt;
      if (dist > 1e-4) {
        final Vector2 m = d * (math.min(dist, most) / dist);
        _at.add(m);
        moved = m.length;
        if (m.x.abs() > 1e-4) _facing = m.x.sign;
      }
    }
    _speed.step(dt > 0 ? moved / dt : 0, dt);
    _gait += moved / 0.42 * math.pi;
  }

  static final Paint _body = Paint()..color = const Color(0xFF030303);
  static final Paint _limb = Paint()
    ..color = const Color(0xFF030303)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  static final Paint _eye = Paint()..color = const Color(0xE6FFFFFF);

  @override
  void render(Canvas canvas) {
    if (gone) return;
    final double h = height;
    final double dir = _facing;
    final double moving = (_speed.value / 2.5).clamp(0.0, 1.0);
    final double bob = -math.sin(_gait).abs() * 0.025 * moving;
    canvas.save();
    canvas.translate(_at.x, _at.y + bob);
    // Legs, a little long for the body, stepping.
    _limb.strokeWidth = h * 0.06;
    final Offset hip = Offset(0, -h * 0.42);
    for (var i = 0; i < 2; i++) {
      final double p = _gait + i * math.pi;
      final Offset foot = Offset(
        dir * math.cos(p) * h * 0.2 * moving,
        -math.max(0, math.sin(p)) * h * 0.08 * moving,
      );
      final Offset knee = solveLimb(hip, foot, h * 0.22, h * 0.22, -dir);
      canvas.drawPath(
        Path()
          ..moveTo(hip.dx, hip.dy)
          ..lineTo(knee.dx, knee.dy)
          ..lineTo(foot.dx, foot.dy),
        _limb,
      );
    }
    // A thin body in a long ragged shirt, leaning into the walk.
    final double lean = dir * moving * h * 0.05;
    canvas.drawPath(
      Path()
        ..moveTo(-h * 0.1, -h * 0.4)
        ..lineTo(-h * 0.08 + lean, -h * 0.76)
        ..lineTo(h * 0.08 + lean, -h * 0.76)
        ..lineTo(h * 0.11, -h * 0.4)
        ..lineTo(h * 0.04, -h * 0.36)
        ..lineTo(-h * 0.03, -h * 0.4)
        ..close(),
      _body,
    );
    // Arms hanging, swinging a little.
    _limb.strokeWidth = h * 0.045;
    for (var i = 0; i < 2; i++) {
      final double swing = math.sin(_gait + i * math.pi) * h * 0.12 * moving;
      final Offset shoulder = Offset(lean, -h * 0.72);
      final Offset hand = shoulder + Offset(dir * swing, h * 0.3);
      canvas.drawLine(shoulder, hand, _limb);
    }
    // A big head with tousled hair, and the eyes.
    final Offset head = Offset(lean * 1.4 + dir * h * 0.02, -h * 0.88);
    canvas.drawCircle(head, h * 0.13, _body);
    for (var k = 0; k < 4; k++) {
      final double a = -math.pi * (0.2 + k * 0.2);
      canvas.drawCircle(
        head + Offset(math.cos(a), math.sin(a)) * h * 0.12,
        h * 0.05,
        _body,
      );
    }
    final double blink = (_time * 0.31 + index * 0.17) % 1 < 0.03 ? 0.2 : 1;
    canvas.drawOval(
      Rect.fromCenter(
        center: head + Offset(dir * h * 0.06, -h * 0.005),
        width: h * 0.035,
        height: h * 0.035 * blink,
      ),
      _eye,
    );
    canvas.restore();
  }
}

/// The freed children, following the boy and lending their weight to
/// what he pushes.
class Following extends Component {
  Following(this.kids, {this.helpNewtons = 280});

  final List<Child> kids;

  /// How hard each pushes alongside him.
  final double helpNewtons;

  final Trail trail = Trail();
  Stage? _stage;

  /// Overrides for a scripted walk: where each should go.
  final Map<Child, Vector2> goals = {};

  @override
  Future<void> onLoad() async {
    _stage = ancestors().whereType<Stage>().firstOrNull;
  }

  /// How many are close behind him now.
  int get helping {
    final boy = _stage?.player;
    if (boy == null || !boy.isMounted) return 0;
    final double x = boy.body.position.x;
    final double f = boy.facing;
    var n = 0;
    for (final c in kids) {
      if (!c.following || c.gone) continue;
      final double behind = (x - c.feet.x) * f;
      if (behind > 0.2 && behind < 3.2) n++;
    }
    return n;
  }

  @override
  void update(double dt) {
    final boy = _stage?.player;
    if (boy == null || !boy.isMounted) return;
    if (!boy.isDead) {
      trail.record(boy.body.position + Vector2(0, GameConfig.playerHeight / 2));
    }
    for (final c in kids) {
      c.step(dt, trail, goal: goals[c]);
    }
    // Their weight behind his: what he pushes, they push.
    final interactions = boy.interactions;
    final Body? load = interactions.pushResistanceBody;
    if (interactions.mode == InteractionMode.pushing && load != null) {
      final int n = helping;
      if (n > 0 && load.isValid) {
        load.applyForce(Vector2(boy.facing * helpNewtons * n, 0));
      }
    }
  }
}
