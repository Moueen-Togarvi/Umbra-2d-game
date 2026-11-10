import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../combat/weapon_art.dart';
import '../combat/weapons.dart';
import '../combat/combat_target.dart';
import '../world/stage.dart';

class WeaponPickup extends PositionComponent {
  WeaponPickup({
    required this.weapon,
    required this.stage,
    required this.enabled,
    required this.onCollected,
    required this.approachDirection,
    required Vector2 position,
  }) : super(position: position, anchor: Anchor.center, priority: 4);

  final WeaponDefinition weapon;
  final Stage stage;
  final bool Function() enabled;
  final void Function(WeaponDefinition) onCollected;
  final double approachDirection;
  double _time = 0;
  bool _collected = false;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (_collected || !enabled() || !stage.player.isMounted) return;
    final playerPosition = stage.player.body.position;
    if ((playerPosition - position).length < 1.05 ||
        (playerPosition.x - position.x) * approachDirection > .8) {
      _collected = true;
      onCollected(weapon);
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final pulse = .78 + math.sin(_time * 2.5) * .12;
    final glow = Paint()
      ..color = const Color(0x55FFFFFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(Offset.zero, .36 * pulse, glow);
    canvas.save();
    canvas.scale(.017);
    WeaponArt.draw(canvas, Offset.zero, 34, weapon.family);
    canvas.restore();
  }
}

/// A harmless Chapter 1 target: it raises its arm on a steady rhythm so the
/// first katana can teach strike recovery and the white telegraph/parry beat.
class TrainingEffigy extends PositionComponent
    implements CombatTarget, CombatTelegraph {
  TrainingEffigy({required Vector2 position})
    : super(position: position, anchor: Anchor.bottomCenter, priority: 3);

  double _clock = 0;
  double _stun = 0;
  double _tilt = 0;

  @override
  Vector2 get combatPosition => position - Vector2(0, 1.05);

  @override
  bool get canReceiveCombatHit => isMounted;

  @override
  bool get isCombatStunned => _stun > 0;

  @override
  bool get isTelegraphing => !isCombatStunned && _clock > 1.5;

  @override
  void receiveCombatHit(CombatHit hit) {
    _stun = hit.stunSeconds.clamp(.45, 1.8);
    _tilt = hit.direction * .28;
    _clock = 0;
    cue('wood', weight: .55, at: combatPosition, shake: .05);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (_stun > 0) {
      _stun = math.max(0, _stun - dt);
    } else {
      _clock = (_clock + dt) % 2.25;
      _tilt *= math.pow(.03, dt).toDouble();
    }
  }

  @override
  void render(Canvas canvas) {
    final ink = Paint()
      ..color = const Color(0xFF08090A)
      ..strokeWidth = .11
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final light = Paint()
      ..color = const Color(0xFFF6F6F2)
      ..strokeWidth = .045
      ..style = PaintingStyle.stroke;
    canvas.save();
    canvas.rotate(_tilt);
    canvas.drawLine(const Offset(0, 0), const Offset(0, -1.65), ink);
    canvas.drawLine(const Offset(-.55, -1.15), const Offset(.55, -1.15), ink);
    canvas.drawCircle(const Offset(0, -1.72), .22, ink);
    canvas.drawLine(const Offset(-.32, 0), const Offset(0, -.55), ink);
    canvas.drawLine(const Offset(.32, 0), const Offset(0, -.55), ink);
    if (isTelegraphing) {
      canvas.drawArc(
        const Rect.fromLTWH(-.78, -2.25, 1.56, 1.15),
        -math.pi * .9,
        math.pi * .8,
        false,
        light,
      );
    }
    canvas.restore();
  }
}
