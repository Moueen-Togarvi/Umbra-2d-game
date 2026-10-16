import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart' show FlameGame;

import '../config/palette.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../world/stage.dart';
import 'figures.dart';

/// What a vampire is doing.
enum VampireMode {
  /// Standing still, breathing, the cape stirring.
  stand,

  /// Walking to [Vampire.goalX] and stopping there.
  walk,

  /// Pacing between two points, pausing at each end.
  patrol,

  /// Falling from where it was put, cape spread, then crouching on landing.
  drop,

  /// Rising out of the landing with both arms reaching forward.
  grab,

  /// Sitting up and climbing out of a coffin: rising from below the
  /// ground line until he stands.
  rise,

  /// Moved by someone else ([Vampire.drive]): running after the boy,
  /// leaping, climbing. The gait follows how fast he is moved.
  driven,

  /// Caught in the light with nowhere dark to go: he folds down and
  /// crumbles to ash and embers.
  burn,
}

/// One of the vampires: a gaunt figure over two metres tall, hunched, with
/// a high collar, long arms ending in claws, red eyes, and a cape that is
/// real cloth: strips of points pinned along the shoulders, swinging behind
/// him as he moves and lifting as he falls.
///
/// He can stand in the play plane (to patrol or to seize the boy) or far
/// off in the fog at a [depth], where he is drawn smaller, paler and
/// scrolling slower, like the scenery there. Everything that moves follows
/// a critically damped spring or a smooth cycle, so he moves with a slow,
/// deliberate menace and never jitters.
class Vampire extends Component implements BackdropDrawable {
  Vampire({
    required this.x,
    required this.groundY,
    this.depth = 1,
    this.facing = -1,
    double? fog,
    super.priority = 1,
  }) : fog = fog ?? SceneryProp.defaultFog(depth);

  /// Feet, world metres at depth 1.
  double x, groundY;

  /// Height above the ground (falling).
  double lift = 0;
  @override
  final double depth;
  final double fog;
  double facing;

  VampireMode mode = VampireMode.stand;
  double goalX = 0;
  double patrolA = 0, patrolB = 0;
  double walkSpeed = 1.1;
  double _pause = 0;

  static const double height = 2.2;

  double _speed = 0;
  double _gait = 0;
  double _time = 0;
  double _fallSpeed = 0;
  bool landed = false;
  final Calm _crouch = Calm(0, hertz: 1.4);
  final Calm _reach = Calm(0, hertz: 1.1);
  final Calm _turn = Calm(-1, hertz: 1.2);

  /// Seconds since he landed from a drop.
  double sinceLanding = 0;

  /// How bright the eyes are (they can open slowly out of the dark).
  double eyes = 1;

  /// Not drawn at all (out of the story for now).
  bool gone = false;

  /// How far the claws reach forward when not seizing (0–1): running at
  /// the boy, or reaching for him across the edge of the light.
  double reachGoal = 0;

  /// How far an arm is raised against the light (0–1).
  double shieldGoal = 0;
  final Calm _shield = Calm(0, hertz: 2.2);

  double _drivenSpeed = 0;
  double _burnt = 0;

  /// Whether he has burnt away (an ash heap is left).
  bool get burnt => _burnt >= burnSeconds;
  static const double burnSeconds = 2.2;
  bool _ashes = false;
  final List<_Mote> _motes = [];
  final math.Random _random = math.Random(7);

  late final _Cape _cape = _Cape();
  Stage? _stage;
  CameraComponent? _camera;

  /// Walks to [x], then stands.
  void walkTo(double x) {
    goalX = x;
    mode = VampireMode.walk;
  }

  /// Paces between [a] and [b].
  void patrol(double a, double b) {
    patrolA = a;
    patrolB = b;
    goalX = (x - a).abs() < (x - b).abs() ? b : a;
    mode = VampireMode.patrol;
  }

  /// Falls from [lift] metres above [groundY].
  void dropFrom(double height) {
    lift = height;
    _fallSpeed = 0;
    landed = false;
    sinceLanding = 0;
    mode = VampireMode.drop;
  }

  /// Rises reaching for whatever is in front.
  void seize() => mode = VampireMode.grab;

  /// Climbs up out of a coffin he lies [depth] metres down in.
  void riseFrom(double depth) {
    lift = -depth;
    mode = VampireMode.rise;
  }

  /// Whether he has finished climbing out.
  bool get risen => mode != VampireMode.rise;

  /// Puts him at [x] with his feet on [groundY], [lift] above it, as
  /// someone else moves him; [dt] since the last time, for his gait.
  void drive({
    required double x,
    required double groundY,
    double lift = 0,
    required double dt,
  }) {
    if (mode == VampireMode.burn) return;
    final double dx = x - this.x;
    _drivenSpeed = dt > 0 ? dx / dt : 0;
    if (dx.abs() > 1e-4) facing = dx.sign;
    this.x = x;
    this.groundY = groundY;
    this.lift = lift;
    mode = VampireMode.driven;
  }

  /// Caught in the light: he burns away where he stands.
  void burn() {
    if (mode == VampireMode.burn || gone) return;
    mode = VampireMode.burn;
    _burnt = 0;
    _drivenSpeed = 0;
  }

  /// Whole again and standing (a death of the boy's undid what killed him).
  void revive() {
    gone = false;
    _ashes = false;
    _burnt = 0;
    _motes.clear();
    shieldGoal = 0;
    reachGoal = 0;
    lift = 0;
    mode = VampireMode.stand;
  }

  /// Something heavy came down on him: gone, in a burst of dust.
  void crush() {
    if (gone) return;
    for (var i = 0; i < 26; i++) {
      final double a = _random.nextDouble() * math.pi;
      final double v = 0.6 + _random.nextDouble() * 1.6;
      _motes.add(
        _Mote(
          Vector2(x + (_random.nextDouble() - 0.5) * 1.2, groundY - 0.2),
          Vector2(math.cos(a) * v, -math.sin(a) * v * 0.6),
          0.8 + _random.nextDouble() * 0.9,
          ember: false,
        ),
      );
    }
    gone = true;
  }

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
    _stage = ancestors().whereType<Stage>().firstOrNull;
    if (depth < 0.85) _stage?.backdropProps.add(this);
    _cape.reset(_shoulder);
  }

  @override
  void onRemove() {
    _stage?.backdropProps.remove(this);
    super.onRemove();
  }

  /// The shoulders' world position (depth 1 metres).
  Vector2 get _shoulder => Vector2(
    x + facing * 0.12,
    groundY - lift - height * 0.78 + _crouch.value * 0.35,
  );

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    double target = 0;
    switch (mode) {
      case VampireMode.stand:
        break;
      case VampireMode.walk:
      case VampireMode.patrol:
        final double d = goalX - x;
        if (_pause > 0) {
          _pause -= dt;
        } else if (d.abs() < 0.05) {
          if (mode == VampireMode.patrol) {
            goalX = goalX == patrolA ? patrolB : patrolA;
            _pause = 1.6;
          } else {
            mode = VampireMode.stand;
          }
        } else {
          facing = d.sign;
          // Slowing to a stop over the last metre.
          target = d.sign * walkSpeed * (d.abs() / 1.0).clamp(0.25, 1.0);
        }
      case VampireMode.drop:
        if (!landed) {
          _fallSpeed += 12 * dt;
          lift -= _fallSpeed * dt;
          if (lift <= 0) {
            lift = 0;
            landed = true;
          }
        } else {
          sinceLanding += dt;
        }
      case VampireMode.grab:
        sinceLanding += dt;
      case VampireMode.rise:
        // Slow at first, then unfolding to his full height.
        lift = math.min(0, lift + dt * (0.5 + (lift + 2) * 0.35));
        if (lift >= 0) mode = VampireMode.stand;
      case VampireMode.driven:
        target = _drivenSpeed;
      case VampireMode.burn:
        _burnt += dt;
        _smoulder(dt);
        if (_burnt >= burnSeconds) {
          gone = true;
          _ashes = true;
        }
    }
    // Speed eases in and out; the gait advances with distance walked.
    final bool driven = mode == VampireMode.driven;
    _speed += (target - _speed) * math.min(1, dt * (driven ? 10 : 3));
    if (!driven && mode != VampireMode.burn) x += _speed * dt;
    _updateMotes(dt);
    _gait += _speed.abs() * dt / 0.95 * math.pi;
    _turn.step(facing, dt);
    final bool crouching =
        (mode == VampireMode.drop && landed && sinceLanding < 0.7) ||
        mode == VampireMode.burn;
    _crouch.step(crouching ? 1 : 0, dt);
    _reach.step(mode == VampireMode.grab ? 1 : reachGoal, dt);
    _shield.step(mode == VampireMode.burn ? 1 : shieldGoal, dt);
    _cape.step(
      dt,
      _shoulder,
      facing,
      _time,
      falling: mode == VampireMode.drop && !landed,
    );
  }

  @override
  void render(Canvas canvas) {
    if (depth < 0.85 && _stage != null) return;
    final Vector2 cam = _camera?.viewfinder.position ?? Vector2(x, groundY);
    paint(canvas, cam, _stage?.moods.at(cam.x) ?? Mood.night);
  }

  final Paint _body = Paint();
  final Paint _limb = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _glow = Paint();

  @override
  void paint(Canvas canvas, Vector2 cam, Mood mood) {
    if (depth >= 1) _paintMotes(canvas);
    if (gone) {
      if (_ashes) _paintAshes(canvas);
      return;
    }
    final double k = depth;
    canvas.save();
    // About the camera, like everything at this depth.
    canvas.translate(cam.x + (x - cam.x) * k, cam.y + (groundY - cam.y) * k);
    canvas.scale(k);
    // Burning, he greys towards ash.
    final double ash = (_burnt / burnSeconds).clamp(0.0, 1.0);
    final Color tone = Color.lerp(
      Color.lerp(const Color(0xFF020202), mood.sky[2], fog)!,
      const Color(0xFF3A3632),
      ash * ash,
    )!;
    _body.color = tone;
    _limb.color = tone;
    final Rect? view = _camera?.visibleWorldRect;
    if (view != null &&
        !view
            .inflate(2)
            .contains(
              Offset(cam.x + (x - cam.x) * k, cam.y + (groundY - cam.y) * k),
            )) {
      canvas.restore();
      return;
    }
    canvas.translate(0, -lift);
    if (ash > 0) {
      // Folding down into a heap as he crumbles.
      canvas.scale(1 + ash * 0.15, 1 - ash * 0.75);
    }
    final double f = _turn.value.clamp(-1.0, 1.0);
    final double dir = f.abs() < 0.1 ? facing : f.sign;
    final double crouch = _crouch.value;
    final double reach = _reach.value;
    final double moving = (_speed.abs() / walkSpeed).clamp(0.0, 1.0);
    final double shield = _shield.value.clamp(0.0, 1.0);
    final double bob = -math.sin(_gait * 2).abs() * 0.03 * moving;
    final double breathe = math.sin(_time * 1.3) * 0.008;
    final double hipY = -1.0 + crouch * 0.42 + bob;
    final Offset hip = Offset(-dir * 0.04, hipY);
    // Hunched: the back bows forward, more in the crouch, less reaching.
    final double hunch =
        0.42 +
        crouch * 0.45 -
        reach * 0.25 +
        shield * 0.25 +
        (mode == VampireMode.driven ? moving * 0.18 : 0);
    final Offset neck =
        hip +
        Offset(dir * math.sin(hunch) * 0.72, -math.cos(hunch) * 0.72 + breathe);
    final Offset head = neck + Offset(dir * 0.13, -0.08);

    // The cape behind everything else, in world metres.
    canvas.save();
    canvas.translate(-x, -(groundY - lift));
    canvas.drawPath(_cape.outline(), _body);
    canvas.restore();

    // Legs: long and thin, stepping in a slow, high-kneed gait.
    _limb.strokeWidth = 0.075;
    for (var i = 0; i < 2; i++) {
      final double phase = _gait + i * math.pi;
      final double fx =
          dir * (math.cos(phase) * 0.36 * moving) + (i - 0.5) * 0.08;
      final double fy = -math.max(0, math.sin(phase)) * 0.16 * moving;
      final Offset foot = Offset(
        fx + dir * crouch * (i == 0 ? 0.3 : -0.25),
        fy,
      );
      final Offset knee = solveLimb(hip, foot, 0.53, 0.52, -dir);
      canvas.drawPath(
        Path()
          ..moveTo(hip.dx, hip.dy)
          ..lineTo(knee.dx, knee.dy)
          ..lineTo(foot.dx, foot.dy),
        _limb,
      );
      // Long pointed shoes.
      canvas.drawPath(
        Path()
          ..moveTo(foot.dx - dir * 0.06, foot.dy - 0.05)
          ..quadraticBezierTo(
            foot.dx + dir * 0.12,
            foot.dy - 0.05,
            foot.dx + dir * 0.24,
            foot.dy - 0.01,
          )
          ..lineTo(foot.dx - dir * 0.07, foot.dy)
          ..close(),
        _body,
      );
    }

    // The coat: narrow at the shoulders, falling in a long curve to a
    // flared, ragged hem below the knees.
    final Offset back = neck + Offset(-dir * 0.15, 0.06);
    final Offset chest = neck + Offset(dir * 0.09, 0.12);
    final double hem = hip.dy + 0.55 - crouch * 0.1;
    final double sway = math.sin(_gait) * 0.04 * moving;
    canvas.drawPath(
      Path()
        ..moveTo(back.dx, back.dy)
        ..cubicTo(
          hip.dx - dir * 0.34,
          hip.dy - 0.35,
          hip.dx - dir * 0.36,
          hip.dy + 0.1,
          hip.dx - dir * 0.34 + sway,
          hem,
        )
        // Ragged points along the hem.
        ..lineTo(hip.dx - dir * 0.24 + sway, hem - 0.08)
        ..lineTo(hip.dx - dir * 0.16 + sway, hem + 0.03)
        ..lineTo(hip.dx - dir * 0.05 + sway, hem - 0.07)
        ..lineTo(hip.dx + dir * 0.06 + sway, hem + 0.02)
        ..lineTo(hip.dx + dir * 0.16 + sway, hem - 0.09)
        ..lineTo(hip.dx + dir * 0.24 + sway, hem - 0.02)
        ..cubicTo(
          hip.dx + dir * 0.2,
          hip.dy - 0.1,
          hip.dx + dir * 0.18,
          hip.dy - 0.3,
          chest.dx,
          chest.dy,
        )
        ..close(),
      _body,
    );

    // The high collar, two spikes rising behind the head.
    canvas.drawPath(
      Path()
        ..moveTo(neck.dx - dir * 0.2, neck.dy + 0.06)
        ..lineTo(neck.dx - dir * 0.24, neck.dy - 0.3)
        ..lineTo(neck.dx - dir * 0.08, neck.dy - 0.08)
        ..lineTo(neck.dx + dir * 0.02, neck.dy - 0.26)
        ..lineTo(neck.dx + dir * 0.08, neck.dy + 0.04)
        ..close(),
      _body,
    );

    // The head: bald and narrow, a hooked nose, pointed ears.
    canvas.drawPath(
      Path()
        ..moveTo(head.dx - dir * 0.08, head.dy + 0.09)
        ..quadraticBezierTo(
          head.dx - dir * 0.11,
          head.dy - 0.14,
          head.dx + dir * 0.02,
          head.dy - 0.13,
        )
        ..quadraticBezierTo(
          head.dx + dir * 0.1,
          head.dy - 0.1,
          head.dx + dir * 0.1,
          head.dy - 0.02,
        )
        ..lineTo(head.dx + dir * 0.17, head.dy + 0.03)
        ..lineTo(head.dx + dir * 0.09, head.dy + 0.05)
        ..quadraticBezierTo(
          head.dx + dir * 0.08,
          head.dy + 0.12,
          head.dx + dir * 0.03,
          head.dy + 0.14,
        )
        ..close(),
      _body,
    );
    canvas.drawPath(
      Path()
        ..moveTo(head.dx - dir * 0.05, head.dy - 0.03)
        ..lineTo(head.dx - dir * 0.13, head.dy - 0.16)
        ..lineTo(head.dx - dir * 0.02, head.dy - 0.06)
        ..close(),
      _body,
    );

    // Arms: hanging and swinging a little as he walks, or reaching out with
    // the claws open.
    _limb.strokeWidth = 0.06;
    for (var i = 0; i < 2; i++) {
      final Offset shoulder =
          neck + Offset(dir * (i == 0 ? 0.04 : -0.06), 0.12);
      final double swing = math.sin(_gait + i * math.pi) * 0.22 * moving;
      final Offset hang =
          shoulder + Offset(dir * (0.12 + swing), 0.78 - crouch * 0.1);
      final Offset out =
          shoulder + Offset(dir * (0.78 - i * 0.08), -0.05 - i * 0.12);
      Offset hand = Offset.lerp(hang, out, reach)!;
      if (i == 0 && shield > 0) {
        // The near arm up across his face against the light.
        hand = Offset.lerp(hand, head + Offset(dir * 0.16, 0.02), shield)!;
      }
      final Offset elbow = solveLimb(shoulder, hand, 0.43, 0.42, dir);
      canvas.drawPath(
        Path()
          ..moveTo(shoulder.dx, shoulder.dy)
          ..lineTo(elbow.dx, elbow.dy)
          ..lineTo(hand.dx, hand.dy),
        _limb,
      );
      // Four long curved claws.
      final Offset along = hand - elbow;
      final double a0 = math.atan2(along.dy, along.dx);
      final double open = 0.15 + reach * 0.35;
      for (var c = 0; c < 4; c++) {
        final double a = a0 + (c - 1.5) * open * 0.5;
        final Offset tip = hand + Offset(math.cos(a), math.sin(a)) * 0.15;
        final Offset bend = hand + Offset(math.cos(a), math.sin(a)) * 0.08;
        canvas.drawPath(
          Path()
            ..moveTo(hand.dx, hand.dy)
            ..quadraticBezierTo(
              bend.dx + dir * 0.0,
              bend.dy - 0.01,
              tip.dx,
              tip.dy + 0.03,
            ),
          _limb..strokeWidth = 0.018,
        );
      }
      _limb.strokeWidth = 0.06;
    }

    // The eyes: red, the only colour on him.
    if (eyes > 0.01 && ash < 0.8) {
      final Offset eye = head + Offset(dir * 0.06, -0.035);
      final double a = eyes * (1 - fog * 0.6) * (1 - ash / 0.8);
      // Opaque: a shader paints at the paint colour's opacity.
      _glow.color = const Color(0xFFFFFFFF);
      _glow.shader = Gradient.radial(eye, 0.06, [
        Palette.vampireRed.withValues(alpha: 0.4 * a),
        Palette.vampireRed.withValues(alpha: 0),
      ]);
      canvas.drawCircle(eye, 0.06, _glow);
      _glow
        ..shader = null
        ..color = Color.lerp(
          Palette.vampireRed,
          const Color(0xFFFFB0A0),
          0.35,
        )!.withValues(alpha: a);
      canvas.drawOval(
        Rect.fromCenter(center: eye, width: 0.032, height: 0.014),
        _glow,
      );
    }
    canvas.restore();
  }
}

/// A speck of ash, an ember or a puff of dust, in world metres.
class _Mote {
  _Mote(this.p, this.v, this.life, {required this.ember});
  final Vector2 p, v;
  double life;
  final bool ember;
  late final double full = life;
}

extension on Vampire {
  /// Embers and ash lifting off him as he burns.
  void _smoulder(double dt) {
    final double t = (_burnt / Vampire.burnSeconds).clamp(0.0, 1.0);
    final int count = (dt * (60 + 140 * (1 - t))).round();
    final double top = Vampire.height * (1 - t * 0.75);
    for (var i = 0; i < count; i++) {
      final bool ember = _random.nextDouble() < 0.35;
      _motes.add(
        _Mote(
          Vector2(
            x + (_random.nextDouble() - 0.5) * 0.7,
            groundY - _random.nextDouble() * top,
          ),
          Vector2(
            (_random.nextDouble() - 0.5) * 0.5,
            -0.4 - _random.nextDouble() * (ember ? 1.4 : 0.7),
          ),
          0.6 + _random.nextDouble() * (ember ? 1.0 : 1.8),
          ember: ember,
        ),
      );
    }
  }

  void _updateMotes(double dt) {
    for (var i = _motes.length - 1; i >= 0; i--) {
      final m = _motes[i];
      m.life -= dt;
      if (m.life <= 0) {
        _motes.removeAt(i);
        continue;
      }
      // Ash drifts and settles; embers rise and fade; dust falls back.
      if (m.ember) {
        m.v.y -= 0.3 * dt;
      } else {
        m.v.y += 0.35 * dt;
      }
      m.v.x += math.sin(m.life * 5 + i) * 0.4 * dt;
      m.v.scale(math.exp(-1.2 * dt));
      m.p.addScaled(m.v, dt);
    }
  }
}

final Paint _motePaint = Paint();

extension on Vampire {
  void _paintMotes(Canvas canvas) {
    for (final m in _motes) {
      final double a = (m.life / m.full).clamp(0.0, 1.0);
      if (m.ember) {
        _motePaint.color = Color.lerp(
          Palette.vampireRed,
          const Color(0xFFFFA060),
          a,
        )!.withValues(alpha: a);
        canvas.drawCircle(m.p.toOffset(), 0.012 + 0.012 * a, _motePaint);
      } else {
        _motePaint.color = const Color(0xFF5A5650).withValues(alpha: a * 0.8);
        canvas.drawCircle(m.p.toOffset(), 0.018 + 0.02 * (1 - a), _motePaint);
      }
    }
  }

  /// What is left: a low heap of ash, the collar's two spikes in it.
  void _paintAshes(Canvas canvas) {
    _motePaint.color = const Color(0xFF151413);
    canvas.drawPath(
      Path()
        ..moveTo(x - 0.5, groundY + 0.02)
        ..quadraticBezierTo(x - 0.3, groundY - 0.16, x, groundY - 0.18)
        ..quadraticBezierTo(x + 0.35, groundY - 0.14, x + 0.55, groundY + 0.02)
        ..close(),
      _motePaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x - 0.1, groundY - 0.12)
        ..lineTo(x - 0.16, groundY - 0.36)
        ..lineTo(x, groundY - 0.15)
        ..lineTo(x + 0.06, groundY - 0.3)
        ..lineTo(x + 0.1, groundY - 0.12)
        ..close(),
      _motePaint,
    );
  }
}

/// The cape: columns of points hanging from the shoulders, joined across
/// and down by sticks, integrated with Verlet steps. It trails the body's
/// movement, stirs in the air and spreads as he falls.
class _Cape {
  static const int cols = 6, rows = 9;
  static const double length = 1.4;
  final List<Vector2> _p = [];
  final List<Vector2> _q = [];

  Vector2 _pin(Vector2 shoulder, double facing, int c) => Vector2(
    shoulder.x - facing * (0.02 + c * 0.035),
    shoulder.y - 0.02 + c * 0.01,
  );

  void reset(Vector2 shoulder) {
    _p.clear();
    _q.clear();
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final Vector2 top = _pin(shoulder, -1, c);
        final v = Vector2(top.x, top.y + length * r / (rows - 1));
        _p.add(v);
        _q.add(v.clone());
      }
    }
  }

  Vector2 _at(int r, int c) => _p[r * cols + c];

  void step(
    double dt,
    Vector2 shoulder,
    double facing,
    double time, {
    required bool falling,
  }) {
    if (dt <= 0 || _p.isEmpty) return;
    const double damping = 0.975;
    for (var i = cols; i < _p.length; i++) {
      final p = _p[i], q = _q[i];
      final int r = i ~/ cols;
      final double down = r / (rows - 1);
      final double stir =
          math.sin(time * 1.7 + i * 0.37) * 0.6 * down +
          math.sin(time * 0.6 + r) * 0.3;
      // Air from below lifts the cape while he falls.
      final double ay = falling ? -6.0 * down : 9.8;
      final double nx = p.x + (p.x - q.x) * damping + stir * dt * dt;
      final double ny = p.y + (p.y - q.y) * damping + ay * dt * dt;
      q.setFrom(p);
      p.setValues(nx, ny);
    }
    for (var c = 0; c < cols; c++) {
      final Vector2 pin = _pin(shoulder, facing, c);
      _at(0, c).setFrom(pin);
    }
    final double dy = length / (rows - 1);
    for (var k = 0; k < 4; k++) {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          if (r + 1 < rows) _stick(_at(r, c), _at(r + 1, c), dy, r == 0);
          if (c + 1 < cols) {
            // The hem may flare wider than the shoulders.
            _stick(_at(r, c), _at(r, c + 1), 0.035 + r * 0.022, r == 0);
          }
        }
      }
      // The cape hangs behind him: it cannot pass forward through his body.
      for (var r = 1; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final p = _at(r, c);
          final double limit = shoulder.x + facing * 0.05;
          if ((p.x - limit) * facing > 0) p.x = limit;
        }
      }
    }
  }

  void _stick(Vector2 a, Vector2 b, double rest, bool pinnedA) {
    final double dx = b.x - a.x, dy = b.y - a.y;
    final double d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-6 || d < rest) return;
    final double f = (d - rest) / d;
    if (pinnedA) {
      b.x -= dx * f;
      b.y -= dy * f;
    } else {
      a.x += dx * f * 0.5;
      a.y += dy * f * 0.5;
      b.x -= dx * f * 0.5;
      b.y -= dy * f * 0.5;
    }
  }

  Path outline() {
    final path = Path();
    if (_p.isEmpty) return path;
    path.moveTo(_at(0, 0).x, _at(0, 0).y);
    for (var r = 1; r < rows; r++) {
      path.lineTo(_at(r, 0).x, _at(r, 0).y);
    }
    // A tattered hem: points cut in between the columns.
    for (var c = 1; c < cols; c++) {
      final a = _at(rows - 1, c - 1), b = _at(rows - 1, c);
      path
        ..lineTo((a.x + b.x) / 2, (a.y + b.y) / 2 - 0.12 - (c % 2) * 0.06)
        ..lineTo(b.x, b.y);
    }
    for (var r = rows - 2; r >= 0; r--) {
      path.lineTo(_at(r, cols - 1).x, _at(r, cols - 1).y);
    }
    return path..close();
  }
}
