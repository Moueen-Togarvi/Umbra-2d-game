import 'package:flutter/material.dart';

import '../config/palette.dart';

/// The Umbra wordmark: UMBRA in widely spaced Cinzel capitals, with two
/// small glowing eyes looking out of the bowl of the U — the boy's in the
/// warm amber of home, and in red where the story turns dark.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, required this.height, this.eyes});

  /// Cap height, roughly, in logical pixels.
  final double height;

  /// The eyes' colour; none drawn when null.
  final Color? eyes;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: WordmarkPainter.widthFor(height),
    height: height * 1.25,
    child: CustomPaint(
      painter: WordmarkPainter(height: height, eyes: eyes),
    ),
  );
}

/// Paints the wordmark; also used to bake the app icon and splash.
class WordmarkPainter extends CustomPainter {
  WordmarkPainter({required this.height, this.eyes, this.ink});

  final double height;
  final Color? eyes;
  final Color? ink;

  static double widthFor(double height) => height * 5.6;

  TextPainter _layout() {
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      text: TextSpan(
        text: 'UMBRA',
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: height * 1.18,
          letterSpacing: height * 0.32,
          fontWeight: FontWeight.w500,
          color: ink ?? Palette.brandInk,
          height: 1,
        ),
      ),
    );
    painter.layout();
    return painter;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final TextPainter text = _layout();
    // Letter spacing trails the last letter too; centre what is visible.
    final double visible = text.width - height * 0.32;
    final Offset origin = Offset(
      (size.width - visible) / 2,
      (size.height - text.height) / 2,
    );
    text.paint(canvas, origin);
    final Color? glow = eyes;
    if (glow == null) return;
    // The U's bowl: the first glyph's box.
    final List<TextBox> boxes = text.getBoxesForSelection(
      const TextSelection(baseOffset: 0, extentOffset: 1),
    );
    if (boxes.isEmpty) return;
    final Rect u = boxes.first.toRect().shift(origin);
    final double glyphWidth = u.width - height * 0.32;
    final double cx = u.left + glyphWidth * 0.5;
    final double cy = u.top + u.height * 0.55;
    final double gap = glyphWidth * 0.15;
    final double r = height * 0.045;
    for (final dx in [-gap, gap]) {
      final Offset at = Offset(cx + dx, cy);
      canvas.drawCircle(
        at,
        r * 4,
        Paint()
          ..shader = RadialGradient(
            colors: [glow.withValues(alpha: 0.45), glow.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: at, radius: r * 4)),
      );
      canvas.drawOval(
        Rect.fromCenter(center: at, width: r * 2.2, height: r * 1.6),
        Paint()..color = Color.lerp(glow, const Color(0xFFFFFFFF), 0.35)!,
      );
    }
  }

  @override
  bool shouldRepaint(WordmarkPainter old) =>
      old.height != height || old.eyes != eyes || old.ink != ink;
}
