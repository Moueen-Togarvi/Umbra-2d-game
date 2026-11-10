import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart'
    show TextPainter, TextSpan, TextStyle, TextDirection, FontWeight;

import '../combat/combat_controller.dart';
import '../combat/weapon_art.dart';
import '../combat/weapons.dart';
import '../entities/player.dart';

class WeaponHud extends PositionComponent {
  WeaponHud({
    required this.inventory,
    required this.combat,
    required this.player,
    required this.hidden,
  }) : super(priority: 50);

  final WeaponInventory inventory;
  final CombatController combat;
  final Player? Function() player;
  final bool Function() hidden;
  final Paint _panel = Paint()..color = const Color(0xB00A0B0C);
  final Paint _line = Paint()
    ..color = const Color(0xE6FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1;
  String _cachedName = '';
  TextPainter? _name;

  @override
  void onGameResize(Vector2 size) {
    this.size = size;
    super.onGameResize(size);
  }

  @override
  void render(Canvas canvas) {
    final weapon = inventory.active;
    final boy = player();
    if (hidden() || weapon == null || boy == null) return;
    const top = 14.0;
    final compact = size.x < 650;
    final left = Rect.fromLTWH(68, top, compact ? 174 : 216, 48);
    final rightWidth = compact ? 126.0 : 162.0;
    final right = Rect.fromLTWH(size.x - rightWidth - 14, top, rightWidth, 48);
    for (final rect in [left, right]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        _panel,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(3)),
        _line,
      );
    }
    WeaponArt.draw(
      canvas,
      Offset(left.left + 25, left.center.dy),
      30,
      weapon.family,
    );
    if (_cachedName != weapon.name) {
      _cachedName = weapon.name;
      _name = TextPainter(
        text: TextSpan(
          text: weapon.name.toUpperCase(),
          style: TextStyle(
            color: const Color(0xFFF8F8F5),
            fontFamily: 'Cinzel',
            fontWeight: FontWeight.w500,
            fontSize: compact ? 11 : 13,
            letterSpacing: 1.2,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: left.width - 60);
    }
    _name!.paint(
      canvas,
      Offset(left.left + 48, left.center.dy - _name!.height / 2),
    );

    final ammo = weapon.usesAmmo
        ? '${inventory.ammoFor(weapon.family)} / ${weapon.maxAmmo}'
        : 'READY';
    final painter = TextPainter(
      text: TextSpan(
        text: ammo,
        style: const TextStyle(
          color: Color(0xFFF8F8F5),
          fontFamily: 'Roboto',
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(right.left + 12, right.center.dy - painter.height / 2),
    );
    for (var i = 0; i < 2; i++) {
      final alive = i < boy.dangerMarks;
      final center = Offset(right.right - 18 - i * 22, right.center.dy);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(.785);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 11, height: 11),
        alive
            ? (_line..style = PaintingStyle.fill)
            : (_line..style = PaintingStyle.stroke),
      );
      canvas.restore();
    }
    _line.style = PaintingStyle.stroke;
  }
}
