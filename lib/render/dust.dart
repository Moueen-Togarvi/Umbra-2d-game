import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/player.dart';

/// Dirt and grass kicked up by the boy: a burst from his feet when he lands
/// hard, and a spray behind him while he slides down a bank, as in LIMBO.
///
/// Specks of dark earth and bits of grass are thrown up and out, fall back
/// under gravity and fade; a hard landing also leaves a faint pale puff. All
/// plain circles and lines: blurred shapes do not draw on the web renderer
/// at world scale, and Impeller blurs them differently.
class DustField extends Component {
  DustField({required this.player}) : super(priority: 40);

  final Player player;
  final List<_Mote> _motes = [];
  final math.Random _random = math.Random(5);
  int _seenLandings = 0;
  double _slideDebt = 0;

  /// More than this and new motes replace nothing: a cap on the draw cost.
  static const int maxMotes = 160;

  /// Landings slower than this throw up no dust.
  static const double minimumImpact = 4;

  /// Motes alive right now.
  int get liveMotes => _motes.length;

  static final Paint _earth = Paint()
    ..color = const Color(0xFF0B0B0B)
    ..isAntiAlias = true;
  static final Paint _blade = Paint()
    ..color = const Color(0xFF0B0B0B)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 0.009;
  static final Paint _puff = Paint();

  @override
  void update(double dt) {
    super.update(dt);
    if (player.landings != _seenLandings) {
      _seenLandings = player.landings;
      if (player.lastLandingImpact >= minimumImpact) {
        burst(player.lastLandingAt, player.lastLandingImpact);
      }
    }
    if (player.isSliding && player.isOnGround) {
      // About 45 specks a second, from under the front foot.
      _slideDebt += dt * 45;
      final feet = player.rigFootTargets;
      while (_slideDebt >= 1) {
        _slideDebt -= 1;
        _slideSpray(feet[_random.nextBool() ? 0 : 1], player.velocity);
      }
    } else {
      _slideDebt = 0;
    }

    const double g = GameConfig.gravityMetersPerSecondSquared;
    for (final mote in _motes) {
      mote.age += dt;
      if (mote.kind == _Kind.puff) {
        mote.velocity.scale(math.exp(-3 * dt));
        mote.velocity.y -= 0.15 * dt;
      } else {
        mote.velocity.y += g * dt;
        mote.velocity.scale(math.exp(-1.2 * dt));
        mote.spin += mote.spinSpeed * dt;
      }
      mote.position.addScaled(mote.velocity, dt);
    }
    _motes.removeWhere((mote) => mote.age >= mote.life);
  }

  /// Throws up dust from [at] (where the feet hit) for a landing at
  /// [impact] metres a second.
  void burst(Vector2 at, double impact) {
    final double strength = ((impact - minimumImpact) / 8).clamp(0.0, 1.0);
    final int count = (6 + 18 * strength).round();
    for (var i = 0; i < count; i++) {
      final double side = _random.nextBool() ? 1 : -1;
      final double speed = 0.6 + _random.nextDouble() * (1.0 + 2.2 * strength);
      final double rise = 0.8 + _random.nextDouble() * (1.2 + 2.0 * strength);
      _add(
        _Mote(
          kind: _random.nextDouble() < 0.3 ? _Kind.blade : _Kind.speck,
          position: at + Vector2(side * _random.nextDouble() * 0.12, -0.02),
          velocity: Vector2(side * speed, -rise),
          size: 0.010 + _random.nextDouble() * 0.016,
          life: 0.45 + _random.nextDouble() * 0.35,
          spinSpeed: (_random.nextDouble() - 0.5) * 30,
        ),
      );
    }
    final int puffs = strength > 0.15 ? 3 : 1;
    for (var i = 0; i < puffs; i++) {
      final double side = i == 0 ? 0 : (i == 1 ? -1 : 1);
      _add(
        _Mote(
          kind: _Kind.puff,
          position: at + Vector2(side * 0.12, -0.06),
          velocity: Vector2(side * (0.5 + strength), -0.1),
          size: 0.12 + 0.08 * strength,
          life: 0.5 + 0.25 * strength,
        ),
      );
    }
  }

  void _slideSpray(Vector2 foot, Vector2 velocity) {
    final double back = -velocity.x.sign;
    _add(
      _Mote(
        kind: _random.nextDouble() < 0.2 ? _Kind.blade : _Kind.speck,
        position: foot + Vector2(back * 0.04, -0.02),
        velocity: Vector2(
          velocity.x * 0.35 + back * (0.3 + _random.nextDouble() * 0.9),
          -(0.6 + _random.nextDouble() * 1.4),
        ),
        size: 0.008 + _random.nextDouble() * 0.012,
        life: 0.35 + _random.nextDouble() * 0.3,
        spinSpeed: (_random.nextDouble() - 0.5) * 30,
      ),
    );
  }

  void _add(_Mote mote) {
    if (_motes.length >= maxMotes) _motes.removeAt(0);
    _motes.add(mote);
  }

  @override
  void render(Canvas canvas) {
    for (final mote in _motes) {
      final double t = mote.age / mote.life;
      final Offset at = Offset(mote.position.x, mote.position.y);
      switch (mote.kind) {
        case _Kind.speck:
          // Shrinks away rather than fading: dark earth on fog stays dark.
          canvas.drawCircle(at, mote.size * (1 - t * t), _earth);
        case _Kind.blade:
          final double length = mote.size * 4 * (1 - t * t);
          final Offset d = Offset(
            math.cos(mote.spin) * length,
            math.sin(mote.spin) * length,
          );
          canvas.drawLine(at - d / 2, at + d / 2, _blade);
        case _Kind.puff:
          // A soft-edged haze: a radial gradient fading to nothing, so it
          // reads as dust in the air, not a ring.
          final double radius = mote.size * (1 + 2.2 * t);
          final int alpha = (30 * (1 - t) * (1 - t)).round();
          _puff.shader = Gradient.radial(
            at,
            radius,
            [
              Color.fromARGB(alpha, 205, 205, 205),
              Color.fromARGB(alpha ~/ 3, 205, 205, 205),
              const Color(0x00CDCDCD),
            ],
            const [0, 0.55, 1],
          );
          canvas.drawCircle(at, radius, _puff);
      }
    }
  }
}

enum _Kind { speck, blade, puff }

class _Mote {
  _Mote({
    required this.kind,
    required this.position,
    required this.velocity,
    required this.size,
    required this.life,
    this.spinSpeed = 0,
  }) : spin = spinSpeed;

  final _Kind kind;
  final Vector2 position, velocity;
  final double size, life, spinSpeed;
  double spin;
  double age = 0;
}
