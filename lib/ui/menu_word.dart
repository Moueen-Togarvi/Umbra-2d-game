import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/palette.dart';

/// One of the menu's words: a Cinzel numeral in amber, the word in italic
/// Cormorant, and the lantern's light behind it when it is the first, or
/// under the pointer, or focused. Used on the main menu, under the
/// settings, and on the pause screen; [scale] makes it smaller there.
class MenuWord extends StatefulWidget {
  const MenuWord({
    super.key,
    required this.numeral,
    required this.label,
    required this.unit,
    required this.onTap,
    this.primary = false,
    this.scale = 1,
    this.alignNumerals = false,
  });
  final String numeral, label;
  final double unit, scale;
  final VoidCallback? onTap;
  final bool primary;

  /// Room for the widest numeral, so the words of a left-aligned list
  /// start in one line.
  final bool alignNumerals;

  @override
  State<MenuWord> createState() => _MenuWordState();
}

class _MenuWordState extends State<MenuWord> {
  bool _hot = false;

  void _set(bool hot) {
    if (hot != _hot) setState(() => _hot = hot);
  }

  @override
  Widget build(BuildContext context) {
    final double u = widget.unit * widget.scale;
    final bool lit = widget.primary || _hot;
    return TextButton(
      onPressed: widget.onTap,
      onHover: _set,
      onFocusChange: _set,
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: u * 1.9),
        ),
      ),
      child: CustomPaint(
        painter: lit ? _Glow(u) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            SizedBox(
              width: widget.alignNumerals ? u * 4.2 : null,
              child: Text(
                widget.numeral,
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: (u * 2.1).clamp(9, double.infinity),
                  letterSpacing: u * .42,
                  color: Palette.lampAmber.withValues(alpha: lit ? 1 : .55),
                ),
              ),
            ),
            SizedBox(width: widget.alignNumerals ? u * 1.4 : u * 3),
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: 'Cormorant',
                fontStyle: FontStyle.italic,
                fontSize: u * 6.1,
                height: 1.1,
                color: Palette.brandInk.withValues(alpha: lit ? .96 : .5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lantern's warm light behind a menu word, fading out to the left.
class _Glow extends CustomPainter {
  const _Glow(this.unit);
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in the design's 720-high frame, scaled to this screen.
    final double s = unit / 7.2;
    final centre = Offset(size.width - 62 * s, size.height / 2);
    final double rx = 236 * s, ry = 59 * s;
    final m = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(rx / ry, 1, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    canvas.drawRect(
      Rect.fromCenter(center: centre, width: rx * 2, height: ry * 2),
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          ry,
          [
            Palette.lampAmber.withValues(alpha: .30),
            Palette.lampAmber.withValues(alpha: 0),
          ],
          const [0, 1],
          TileMode.clamp,
          m.storage,
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _Glow oldDelegate) => oldDelegate.unit != unit;
}
