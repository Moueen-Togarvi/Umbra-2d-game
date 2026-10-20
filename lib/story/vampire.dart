import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart' show FlameGame;

import '../config/palette.dart';
import '../render/mood.dart';
import '../render/npc_atlas.dart';
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

  /// Caught by deep water: he goes under, clawing at it.
  sink,
}

/// A hovering vampire with an articulated upper body and a coat dissolving
/// into smoke. Ground-relative AI coordinates remain the gameplay authority;
/// the visual body drifts above them and leaves a small local pool of mist.
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

  /// Ground reference, world metres at depth 1.
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
  static const double hoverClearance = .35;

  double _speed = 0;
  double? _soundX;
  double _soundDistance = 0;
  double _time = 0;
  late final double _driftPhase = x * .37;
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
  NpcAtlas? _art;
  bool get hasArtwork => _art != null;
  final Paint _sprite = Paint()..filterQuality = FilterQuality.medium;
  final Paint _joint = Paint()..color = const Color(0xFF0B0C0E);
  final Paint _mist = Paint()
    ..shader = Gradient.radial(
      Offset.zero,
      1,
      const [Color(0x45979B98), Color(0x22898F8B), Color(0x00898F8B)],
      const [0, .4, 1],
    );
  final Paint _trail = Paint()..style = PaintingStyle.stroke;
  final Path _smokePath = Path();
  ImageShader? _coatTexture;
  final Paint _coatPaint = Paint()..filterQuality = FilterQuality.medium;
  static final Float64List _textureMatrix = Float64List.fromList([
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
    0,
    0,
    0,
    0,
    1,
  ]);
  // Remove the atlas's painted eye colour; the live eye below obeys eyes,
  // distance fog and burning, rather than remaining red after extinguishing.
  final Paint _headSprite = Paint()
    ..filterQuality = FilterQuality.medium
    ..colorFilter = const ColorFilter.matrix([
      .1807,
      .6079,
      .0614,
      0,
      0,
      .1807,
      .6079,
      .0614,
      0,
      0,
      .1807,
      .6079,
      .0614,
      0,
      0,
      0,
      0,
      0,
      1,
      0,
    ]);
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

  Vector2 get _chest => Vector2(x, groundY - lift - 1.4);

  /// Rises reaching for whatever is in front.
  void seize() {
    if (mode != VampireMode.grab) cue('shriek', weight: 0.8, at: _chest);
    mode = VampireMode.grab;
  }

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

  /// The water over his head: he goes under, and does not come up.
  void drown() {
    if (mode == VampireMode.sink || mode == VampireMode.burn || gone) return;
    mode = VampireMode.sink;
    _drivenSpeed = 0;
    _sunk = 0;
    cue('splash', weight: 0.8, at: _chest);
    cue('shriek', weight: 0.5, at: _chest);
  }

  double _sunk = 0;

  /// Caught in the light: he burns away where he stands.
  void burn() {
    if (mode == VampireMode.burn || gone) return;
    mode = VampireMode.burn;
    _burnt = 0;
    _drivenSpeed = 0;
    cue('shriek', at: _chest, shake: 0.2);
    cue('burn', weight: 0.9, at: _chest);
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
    cue('shriek', weight: 0.7, at: _chest, shake: 0.5);
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
    _art = await NpcAtlas.load('vampire');
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
    _stage = ancestors().whereType<Stage>().firstOrNull;
    if (depth < 0.85) _stage?.backdropProps.add(this);
    _cape.reset(_shoulder);
  }

  @override
  void onRemove() {
    _coatTexture?.dispose();
    _coatTexture = null;
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
    final previousX = _soundX;
    _soundX = x;
    if (!gone &&
        depth >= .99 &&
        lift < .1 &&
        mode != VampireMode.burn &&
        mode != VampireMode.sink &&
        mode != VampireMode.drop &&
        mode != VampireMode.rise) {
      final stage = _stage;
      if (stage != null &&
          stage.player.isMounted &&
          !stage.player.isDead &&
          (stage.player.body.position.x - x).abs() < 12 &&
          (stage.player.body.position.y - (groundY - .65)).abs() < 2) {
        stage.reportThreat(ThreatLevel.tension);
      }
      final moved = previousX == null ? 0.0 : (x - previousX).abs();
      if (moved < 1) _soundDistance += moved;
      if (_soundDistance >= .9) {
        _soundDistance %= .9;
        cue('vampire_step', weight: .7, at: Vector2(x, groundY));
        cue('vampire_cloth', weight: .3, at: Vector2(x, groundY - 1));
      }
    } else {
      _soundDistance = 0;
    }
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
            cue('rumble', weight: .18, at: _chest, shake: .1);
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
      case VampireMode.sink:
        _sunk += dt;
        lift -= dt * (0.6 + _sunk * 0.6);
        if (_sunk > 2.6) gone = true;
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
    if (!driven && mode != VampireMode.burn && mode != VampireMode.sink) {
      x += _speed * dt;
    }
    _updateMotes(dt);
    _turn.step(facing, dt);
    final bool crouching =
        (mode == VampireMode.drop && landed && sinceLanding < 0.7) ||
        mode == VampireMode.burn;
    _crouch.step(crouching ? 1 : 0, dt);
    _reach.step(
      mode == VampireMode.grab || mode == VampireMode.sink ? 1 : reachGoal,
      dt,
    );
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
      Color.lerp(const Color(0xFF101012), mood.sky[2], fog)!,
      const Color(0xFF3A3632),
      ash * ash,
    )!;
    _body.color = tone;
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
    _paintGroundMist(canvas, ash);
    final hover = math.sin(_time * 1.65 + _driftPhase) * .035;
    canvas.translate(0, -lift + hover);
    if (ash > 0) {
      // Folding down into a heap as he crumbles.
      canvas.scale(1 + ash * 0.15, 1 - ash * 0.75);
    }
    final art = _art;
    if (art == null) {
      canvas.restore();
      return;
    }
    final f = _turn.value.clamp(-1.0, 1.0);
    final facingSign = f.abs() < .1 ? facing : f.sign;
    canvas.scale(facingSign * math.max(.35, f.abs()), 1);
    const dir = 1.0;
    final crouch = _crouch.value;
    final reach = _reach.value;
    final moving = (_speed.abs() / walkSpeed).clamp(0.0, 1.0);
    final shield = _shield.value.clamp(0.0, 1.0);
    final breathe = math.sin(_time * 1.3) * .006;
    final hip = Offset(-.04, -1.02 + crouch * .12);
    final hunch = .17 + crouch * .4 + moving * .15 + shield * .2 - reach * .07;
    final neck =
        hip + Offset(math.sin(hunch) * .77, -math.cos(hunch) * .77 + breathe);
    final head = neck + const Offset(.045, -.16);
    final tintAmount = math.max(fog, ash * .85).clamp(0.0, .9);
    _sprite.colorFilter = tintAmount > .01
        ? ColorFilter.mode(
            tone.withValues(alpha: tintAmount),
            BlendMode.srcATop,
          )
        : null;
    _joint.colorFilter = _sprite.colorFilter;

    const torso = Rect.fromLTWH(-.24, -.19, .46, .99);
    Offset torsoPoint(Offset uv) {
      final local = Offset(
        torso.left + uv.dx * torso.width,
        torso.top + uv.dy * torso.height,
      );
      return neck +
          Offset(
            local.dx * math.cos(hunch) - local.dy * math.sin(hunch),
            local.dx * math.sin(hunch) + local.dy * math.cos(hunch),
          );
    }

    void arm(int side) {
      final bool rear = side == 0;
      // The visible armhole is at UV (.20, .34) in the torso artwork.
      // Derive its world position from the exact same torso transform.
      final shoulder = torsoPoint(
        rear ? const Offset(.31, .34) : const Offset(.20, .34),
      );
      final phase = _time * 1.65 + _driftPhase + side * math.pi;
      final swing = math.sin(phase) * .025 * moving * (1 - reach);
      final hang =
          hip +
          Offset((rear ? .19 : .36) + swing, -.10 - math.cos(phase) * .008);
      final out = neck + Offset(rear ? .58 : .55, rear ? .14 : .10);
      var wrist = Offset.lerp(hang, out, reach)!;
      if (!rear && shield > 0) {
        wrist = Offset.lerp(wrist, head + const Offset(.19, .04), shield)!;
      }
      final delta = wrist - shoulder;
      wrist =
          shoulder + delta * math.min(1, .709 / math.max(.001, delta.distance));
      // Mirroring the whole figure already changes its handedness. Both
      // elbows must bend anatomically the same way in this local side view.
      final elbow = solveLimb(shoulder, wrist, .36, .35, 1);
      // Underlays live beneath the textured sleeves. They cover transparent
      // fringes without replacing the existing clothing artwork.
      canvas.drawCircle(shoulder, .072, _joint);
      canvas.drawCircle(elbow, .045, _joint);
      canvas.drawCircle(wrist, .028, _joint);
      art.bone(
        canvas,
        3,
        shoulder,
        elbow,
        .16,
        _sprite,
        startAnchor: const Offset(.57, .12),
        endAnchor: const Offset(.44, .94),
      );
      art.bone(
        canvas,
        4,
        elbow,
        wrist,
        .115,
        _sprite,
        startAnchor: const Offset(.27, .08),
        endAnchor: const Offset(.52, .86),
      );
      final forearm = wrist - elbow;
      final angle = math.atan2(forearm.dy, forearm.dx);
      final restingAngle = rear ? .30 : .18;
      final reachingAngle = rear ? .14 : .08;
      final handAngle = restingAngle + (reachingAngle - restingAngle) * reach;
      final curl = (handAngle - angle) * (1 - shield);
      art.hand(
        canvas,
        5,
        wrist,
        elbow,
        .14,
        .18,
        _sprite,
        curl: curl,
        wristAnchor: const Offset(.31, .065),
        fingerAnchor: const Offset(.68, .80),
      );
    }

    arm(0);
    _paintSmokeVeil(canvas, hip, moving, ash);
    _paintFloatingCoat(canvas, art, hip, moving, facingSign);
    canvas.save();
    canvas.translate(neck.dx, neck.dy);
    canvas.rotate(hunch);
    art.draw(canvas, 1, torso, _sprite);
    canvas.restore();
    art.draw(
      canvas,
      0,
      Rect.fromCenter(center: head, width: .46, height: .43),
      _headSprite,
    );
    arm(1);

    // Keep the eye saturated and readable at gameplay scale, including fog.
    if (eyes > 0.01 && ash < 0.8) {
      final Offset eye = head + Offset(dir * 0.15, -0.015);
      final double a = eyes * (1 - fog * 0.6) * (1 - ash / 0.8);
      const red = Color(0xFFFF2028);
      // Opaque: a shader paints at the paint colour's opacity.
      _glow.color = const Color(0xFFFFFFFF);
      _glow.shader = Gradient.radial(
        eye,
        .095,
        [
          red.withValues(alpha: .65 * a),
          red.withValues(alpha: .22 * a),
          red.withValues(alpha: 0),
        ],
        [0, .35, 1],
      );
      canvas.drawCircle(eye, .095, _glow);
      _glow
        ..shader = null
        ..color = red.withValues(alpha: a);
      canvas.drawOval(
        Rect.fromCenter(center: eye, width: .050, height: .024),
        _glow,
      );
    }
    canvas.restore();
  }

  void _paintGroundMist(Canvas canvas, double ash) {
    final opacity =
        (1 - lift.abs() / .9).clamp(0.0, 1.0) * (1 - ash) * (1 - fog * .65);
    if (opacity < .01) return;
    canvas.save();
    canvas.clipRect(const Rect.fromLTRB(-1.5, -.48, 1.5, .015));
    for (var i = 0; i < 7; i++) {
      final phase = _time * .55 + i * 1.7 + _driftPhase;
      final px = (i - 3) * .20 + math.sin(phase) * .12 - _speed * .045;
      final py = -.045 - (i % 3) * .035 + math.cos(phase * .7) * .018;
      _mist.color = Color.fromRGBO(255, 255, 255, opacity * .48);
      canvas.save();
      canvas.translate(px, py);
      canvas.scale(.40 + (i % 2) * .10, .10 + (i % 3) * .018);
      canvas.drawCircle(Offset.zero, 1, _mist);
      canvas.restore();
    }
    canvas.restore();
  }

  void _paintSmokeVeil(Canvas canvas, Offset hip, double moving, double ash) {
    final opacity = (1 - fog * .65) * (1 - ash);
    for (var i = 0; i < 5; i++) {
      final t = _time * .8 + _driftPhase + i * 1.8;
      final sx = hip.dx - .25 + i * .09;
      final sy = hip.dy + .35 + i * .035;
      final drift = -.10 - moving * .12 + math.sin(t) * .055;
      _trail
        ..strokeWidth = .035 - (i % 3) * .006
        ..shader = Gradient.linear(
          Offset(sx, sy),
          Offset(sx + drift, -.06),
          [
            const Color(0xFF111416).withValues(alpha: opacity * .55),
            const Color(0xFF707774).withValues(alpha: opacity * .12),
            const Color(0x00707774),
          ],
          const [0, .65, 1],
        );
      _smokePath
        ..reset()
        ..moveTo(sx, sy)
        ..cubicTo(
          sx + .10 * math.cos(t),
          sy + .16,
          sx + drift - .08,
          -.25,
          sx + drift,
          -.06,
        );
      canvas.drawPath(_smokePath, _trail);
    }
  }

  void _paintFloatingCoat(
    Canvas canvas,
    NpcAtlas art,
    Offset hip,
    double moving,
    double facingSign,
  ) {
    const strips = 12;
    const top = -.17;
    final hem = -hoverClearance - hip.dy;
    final length = hem - top;
    final lag = -.08 - moving * .16 - facingSign * _cape.sway * .08;
    final positions = <Offset>[];
    final texture = <Offset>[];
    final colors = <Color>[];
    final source = art.parts[2];
    for (var i = 0; i <= strips; i++) {
      final v = i / strips;
      final fade = ((v - .45) / .55).clamp(0.0, 1.0);
      final alpha = 1 - fade * fade * (3 - 2 * fade);
      final offset = lag * v * v + math.sin(_time * 1.6 - v * 5) * .025 * v;
      positions.addAll([
        Offset(hip.dx - .44 + offset, hip.dy + top + v * length),
        Offset(hip.dx + .22 + offset, hip.dy + top + v * length),
      ]);
      texture.addAll([
        Offset(source.left, source.top + v * source.height),
        Offset(source.right, source.top + v * source.height),
      ]);
      final color = Color.fromRGBO(255, 255, 255, alpha);
      colors.addAll([color, color]);
    }
    _coatTexture ??= ImageShader(
      art.image,
      TileMode.clamp,
      TileMode.clamp,
      _textureMatrix,
      filterQuality: FilterQuality.medium,
    );
    _coatPaint
      ..shader = _coatTexture
      ..colorFilter = _sprite.colorFilter;
    final mesh = Vertices(
      VertexMode.triangleStrip,
      positions,
      textureCoordinates: texture,
      colors: colors,
    );
    canvas.drawVertices(mesh, BlendMode.modulate, _coatPaint);
    mesh.dispose();
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

  double get sway => _p.isEmpty
      ? 0
      : ((_at(rows - 1, cols ~/ 2).x - _at(0, cols ~/ 2).x) / length).clamp(
          -1.0,
          1.0,
        );
}
