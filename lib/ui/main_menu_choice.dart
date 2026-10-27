import 'package:flutter/material.dart';

import '../config/palette.dart';

/// The brush-highlighted choice shared by the title and pause menus.
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
  });

  final String label;
  final double unit;
  final bool selected, autofocus;
  final bool centered;
  final VoidCallback onHighlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double fontSize = (unit * 3.15).clamp(17, 27);
    return Padding(
      padding: EdgeInsets.only(bottom: (unit * .8).clamp(3, 8)),
      child: TextButton(
        autofocus: autofocus,
        onPressed: onTap,
        onHover: (hot) {
          if (hot) onHighlight();
        },
        onFocusChange: (focused) {
          if (focused) onHighlight();
        },
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(180, 46)),
          alignment: centered ? Alignment.center : Alignment.centerLeft,
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: (unit * 2.1).clamp(10, 19),
              vertical: (unit * 1.05).clamp(6, 10),
            ),
          ),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        ),
        child: CustomPaint(
          painter: selected ? const _BrushMark() : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: fontSize,
                fontWeight: FontWeight.w400,
                letterSpacing: (unit * .72).clamp(3.5, 6),
                color: selected
                    ? const Color(0xFF171719)
                    : Palette.brandInk.withValues(alpha: .92),
                shadows: selected
                    ? null
                    : const [Shadow(color: Color(0x99000000), blurRadius: 8)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrushMark extends CustomPainter {
  const _BrushMark();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = const Color(0xE9E7E5E1);
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
      paint..color = const Color(0x99E7E5E1),
    );
    canvas.drawRect(
      Rect.fromLTWH(size.width + 2, size.height * .58, 13, 1),
      paint..color = const Color(0x88E7E5E1),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
