import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// Something that lights a part of the world: a moonlit window, a lantern,
/// the candles of a chandelier.
///
/// It matters for more than the picture. The vampires will not step into
/// light; caught in it, they run for the dark, and with nowhere to run they
/// burn. A stage keeps its lights in [Stage.lights], and anything that
/// needs to know asks the stage whether a point is lit.
abstract interface class LightSource {
  /// Whether [point] (world metres) is in this light now.
  bool lights(Vector2 point);
}

/// Shared drawing for warm points of light: a lantern flame, a candle.
abstract final class Glow {
  static final Paint _paint = Paint();

  /// A soft round glow of [color] at [centre], [radius] metres, at
  /// [strength] (0–1) in the middle.
  static void round(
    Canvas canvas,
    Offset centre,
    double radius,
    Color color,
    double strength,
  ) {
    if (strength <= 0.004 || radius <= 0) return;
    // Opaque: a paint with a shader draws at its colour's opacity.
    _paint
      ..color = const Color(0xFFFFFFFF)
      ..shader = Gradient.radial(
        centre,
        radius,
        [
          color.withValues(alpha: strength),
          color.withValues(alpha: strength * 0.32),
          color.withValues(alpha: strength * 0.08),
          color.withValues(alpha: 0),
        ],
        const [0, 0.22, 0.6, 1],
      );
    canvas.drawCircle(centre, radius, _paint);
    _paint.shader = null;
  }

  /// A candle or lantern flame: a small teardrop, bright at its heart.
  static void flame(
    Canvas canvas,
    Offset base,
    double height,
    Color color,
    double flicker,
  ) {
    final double h = height * (0.85 + 0.15 * flicker);
    final double w = height * 0.32;
    _paint
      ..shader = null
      ..color = Color.lerp(color, const Color(0xFFFFF4DC), 0.45)!;
    canvas.drawPath(
      Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(
          base.dx - w,
          base.dy - h * 0.35,
          base.dx,
          base.dy - h,
        )
        ..quadraticBezierTo(base.dx + w, base.dy - h * 0.35, base.dx, base.dy)
        ..close(),
      _paint,
    );
  }

  /// A steady flicker for a flame, 0–1, different for each [seed].
  static double flicker(double time, int seed) =>
      0.5 +
      0.3 * math.sin(time * 7.3 + seed * 1.7) * math.sin(time * 2.1 + seed) +
      0.2 * math.sin(time * 13.1 + seed * 0.9);
}
