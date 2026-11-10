import 'package:flutter/material.dart';

import '../config/palette.dart';

/// A menu choice with brush or framed selection treatments.
class MainMenuChoice extends StatelessWidget {
  const MainMenuChoice({
    super.key,
    required this.label,
    required this.unit,
    required this.selected,
    required this.autofocus,
    required this.onHighlight,
    required this.onTap,
    this.centered = false,
    this.minimumWidth = 180,
    this.wordSpacing = 0,
    this.amberSelected = false,
    this.ornamental = false,
  });

  final String label;
  final double unit;
  final bool selected, autofocus;
  final bool centered;
  final double minimumWidth;
  final double wordSpacing;
  final bool amberSelected;
  final bool ornamental;
  final VoidCallback onHighlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double fontSize = ornamental
        ? (unit * 2.8).clamp(14, 20)
        : (unit * 3.15).clamp(17, 27);
    final double height = ornamental ? (unit * 8).clamp(42, 58) : 46;
    final text = Text(
      label.toUpperCase(),
      textAlign: centered ? TextAlign.center : TextAlign.left,
      style: TextStyle(
        fontFamily: 'Cinzel',
        fontSize: fontSize,
        fontWeight: ornamental ? FontWeight.w700 : FontWeight.w400,
        letterSpacing: ornamental ? 1.4 : (unit * .72).clamp(3.5, 6),
        wordSpacing: wordSpacing,
        color: ornamental
            ? const Color(0xFF25302F)
            : selected
            ? const Color(0xFF171719)
            : Palette.brandInk.withValues(alpha: .92),
        shadows: ornamental || selected
            ? null
            : const [Shadow(color: Color(0x99000000), blurRadius: 8)],
      ),
    );
    final button = TextButton(
      autofocus: autofocus,
      onPressed: onTap,
      onHover: (hot) {
        if (hot) onHighlight();
      },
      onFocusChange: (focused) {
        if (focused) onHighlight();
      },
      style: ButtonStyle(
        minimumSize: WidgetStatePropertyAll(Size(minimumWidth, height)),
        side: ornamental
            ? WidgetStatePropertyAll(
                BorderSide(
                  color: selected
                      ? const Color(0xFFE8E9E4)
                      : const Color(0xFFD2D4D0),
                ),
              )
            : null,
        backgroundColor: ornamental
            ? WidgetStatePropertyAll(
                selected ? const Color(0xFFF5F5F1) : const Color(0xFFECECE7),
              )
            : null,
        shape: ornamental
            ? const WidgetStatePropertyAll(
                RoundedRectangleBorder(borderRadius: BorderRadius.zero),
              )
            : null,
        alignment: centered ? Alignment.center : Alignment.centerLeft,
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(
            horizontal: (unit * 2.1).clamp(10, 19),
            vertical: (unit * 1.05).clamp(6, 10),
          ),
        ),
        overlayColor: WidgetStatePropertyAll(
          ornamental ? const Color(0x18000000) : Colors.transparent,
        ),
      ),
      child: ornamental
          ? text
          : CustomPaint(
              painter: selected ? _BrushMark(amber: amberSelected) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                child: text,
              ),
            ),
    );

    return Padding(
      padding: EdgeInsets.only(
        bottom: ornamental ? 6 : (unit * .8).clamp(3, 8),
      ),
      child: ornamental
          ? SizedBox(
              height: height,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 42,
                    height: height,
                    child: CustomPaint(
                      painter: const _DiamondOrnamentPainter(),
                    ),
                  ),
                  button,
                  SizedBox(
                    width: 42,
                    height: height,
                    child: CustomPaint(
                      painter: const _DiamondOrnamentPainter(mirrored: true),
                    ),
                  ),
                ],
              ),
            )
          : button,
    );
  }
}

class _DiamondOrnamentPainter extends CustomPainter {
  const _DiamondOrnamentPainter({this.mirrored = false});
  final bool mirrored;

  @override
  void paint(Canvas canvas, Size size) {
    if (mirrored) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    final center = Offset(size.width * .42, size.height / 2);
    final outer = Paint()
      ..color = const Color(0xFFECECE7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final inner = Paint()
      ..color = const Color(0xFFECECE7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7;
    final shaft = Path()
      ..moveTo(center.dx + size.height * .27, center.dy)
      ..lineTo(size.width, center.dy);
    canvas.drawPath(shaft, outer);
    final outerDiamond = Path()
      ..moveTo(center.dx, center.dy - size.height * .39)
      ..lineTo(center.dx + size.height * .39, center.dy)
      ..lineTo(center.dx, center.dy + size.height * .39)
      ..lineTo(center.dx - size.height * .39, center.dy)
      ..close();
    canvas.drawPath(outerDiamond, outer);
    final innerDiamond = Path()
      ..moveTo(center.dx, center.dy - size.height * .22)
      ..lineTo(center.dx + size.height * .22, center.dy)
      ..lineTo(center.dx, center.dy + size.height * .22)
      ..lineTo(center.dx - size.height * .22, center.dy)
      ..close();
    canvas.drawPath(innerDiamond, inner);
    final arrow = Path()
      ..moveTo(center.dx - size.height * .08, center.dy)
      ..lineTo(center.dx - size.height * .26, center.dy)
      ..moveTo(center.dx - size.height * .26, center.dy)
      ..lineTo(center.dx - size.height * .15, center.dy - size.height * .1)
      ..moveTo(center.dx - size.height * .26, center.dy)
      ..lineTo(center.dx - size.height * .15, center.dy + size.height * .1);
    canvas.drawPath(arrow, inner);
  }

  @override
  bool shouldRepaint(covariant _DiamondOrnamentPainter oldDelegate) =>
      oldDelegate.mirrored != mirrored;
}

class _BrushMark extends CustomPainter {
  const _BrushMark({this.amber = false});
  final bool amber;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = amber
          ? Palette.lampAmber.withValues(alpha: .92)
          : const Color(0xE9E7E5E1);
    final Path stroke = Path()
      ..moveTo(-9, size.height * .22)
      ..quadraticBezierTo(size.width * .18, -2, size.width * .43, 1)
      ..quadraticBezierTo(
        size.width * .76,
        3,
        size.width + 12,
        size.height * .16,
      )
      ..lineTo(size.width + 7, size.height * .78)
      ..quadraticBezierTo(
        size.width * .72,
        size.height + 2,
        size.width * .48,
        size.height - 1,
      )
      ..quadraticBezierTo(
        size.width * .17,
        size.height - 3,
        -7,
        size.height * .84,
      )
      ..close();
    canvas.drawPath(stroke, paint);
    canvas.drawRect(
      Rect.fromLTWH(-14, size.height * .42, 10, 1.5),
      paint
        ..color = amber
            ? Palette.lampAmber.withValues(alpha: .55)
            : const Color(0x99E7E5E1),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width + 2, size.height * .58, 13, 1),
      paint
        ..color = amber
            ? Palette.lampAmber.withValues(alpha: .48)
            : const Color(0x88E7E5E1),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
