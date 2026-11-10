import 'dart:math' as math;
import 'dart:ui';

import 'weapons.dart';

abstract final class WeaponArt {
  static void draw(
    Canvas canvas,
    Offset center,
    double size,
    WeaponFamily family, {
    Color color = const Color(0xFFF8F8F5),
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.5, size * .065)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final r = size / 2;
    switch (family) {
      case WeaponFamily.katana:
        canvas.drawLine(
          center + Offset(-r * .75, r * .55),
          center + Offset(r * .75, -r * .55),
          paint,
        );
        canvas.drawLine(
          center + Offset(-r * .55, r * .68),
          center + Offset(-r * .78, r * .35),
          paint,
        );
      case WeaponFamily.shuriken:
        final path = Path();
        for (var i = 0; i < 8; i++) {
          final a = -math.pi / 2 + i * math.pi / 4;
          final d = i.isEven ? r * .82 : r * .25;
          final p = center + Offset(math.cos(a) * d, math.sin(a) * d);
          i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
        }
        canvas.drawPath(path..close(), paint);
      case WeaponFamily.kunai:
        canvas.drawPath(
          Path()
            ..moveTo(center.dx + r * .8, center.dy - r * .55)
            ..lineTo(center.dx + r * .25, center.dy + r * .2)
            ..lineTo(center.dx - r * .25, center.dy - r * .2)
            ..close(),
          paint,
        );
        canvas.drawLine(
          center + Offset(-r * .05, r * .05),
          center + Offset(-r * .65, r * .65),
          paint,
        );
      case WeaponFamily.bow:
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: r * .78),
          -math.pi * .55,
          math.pi * 1.1,
          false,
          paint,
        );
        canvas.drawLine(
          center + Offset(-r * .12, -r * .75),
          center + Offset(-r * .12, r * .75),
          paint,
        );
      case WeaponFamily.smokeBomb || WeaponFamily.bombs:
        canvas.drawCircle(center + Offset(0, r * .1), r * .52, paint);
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - r * .45)
            ..quadraticBezierTo(
              center.dx + r * .2,
              center.dy - r * .85,
              center.dx + r * .55,
              center.dy - r * .7,
            ),
          paint,
        );
      case WeaponFamily.kusarigama:
        canvas.drawArc(
          Rect.fromCircle(
            center: center + Offset(r * .35, -r * .1),
            radius: r * .45,
          ),
          -math.pi,
          math.pi * 1.4,
          false,
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy + r * .2)
            ..quadraticBezierTo(
              center.dx - r * .3,
              center.dy + r * .85,
              center.dx - r * .75,
              center.dy + r * .45,
            ),
          paint,
        );
      case WeaponFamily.spear:
        canvas.drawLine(
          center + Offset(-r * .82, r * .65),
          center + Offset(r * .65, -r * .55),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(center.dx + r * .82, center.dy - r * .72)
            ..lineTo(center.dx + r * .5, center.dy - r * .5)
            ..lineTo(center.dx + r * .67, center.dy - r * .3)
            ..close(),
          paint,
        );
      case WeaponFamily.twinDaggers:
        for (final y in [-.28, .28]) {
          canvas.drawLine(
            center + Offset(-r * .7, r * y),
            center + Offset(r * .65, r * y),
            paint,
          );
        }
      case WeaponFamily.claws:
        for (var i = -1; i <= 1; i++) {
          canvas.drawArc(
            Rect.fromCenter(
              center: center + Offset(0, i * r * .28),
              width: r * 1.45,
              height: r * .65,
            ),
            -.75,
            1.5,
            false,
            paint,
          );
        }
    }
  }
}
