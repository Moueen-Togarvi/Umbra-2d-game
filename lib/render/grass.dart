import 'dart:math' as math;
import 'dart:ui';

/// The wind and whatever is pushing through the grass, shared by every
/// patch of grass in the level so they all sway together.
class GrassWind {
  double time = 0;

  /// World x of the boy's feet, and how fast he is moving through the
  /// grass. Blades near him lean away from his legs.
  double pusherX = double.nan;
  double pusherSpeed = 0;

  void update(double dt) => time += dt;
}

/// Parameters of one layer of grass. The layer behind the boy is dense and
/// tall; the layer in front of him is sparse and short enough that it only
/// hides his feet.
class GrassStyle {
  const GrassStyle({
    required this.spacing,
    required this.seed,
    required this.minHeight,
    required this.maxHeight,
    required this.clumpHeight,
    required this.coverage,
    this.stalkChance = 0,
    this.bladeWidth = 0.011,
  });

  final double spacing, seed, minHeight, maxHeight, clumpHeight, coverage;

  /// Chance of a tall stalk with a seed head instead of a plain blade.
  final double stalkChance;
  final double bladeWidth;

  // Blade counts are budgeted: every blade is rebuilt each frame, and on
  // the web the path work is a large share of the frame time.
  static const back = GrassStyle(
    spacing: 0.034,
    seed: 3.1,
    minHeight: 0.04,
    maxHeight: 0.18,
    clumpHeight: 0.42,
    coverage: 0.74,
    stalkChance: 0.03,
    bladeWidth: 0.013,
  );

  /// Short enough that the boots stay visible, standing in it rather
  /// than buried.
  static const front = GrassStyle(
    spacing: 0.08,
    seed: 11.7,
    minHeight: 0.02,
    maxHeight: 0.075,
    clumpHeight: 0.11,
    coverage: 0.45,
    bladeWidth: 0.009,
  );
}

/// Builds wispy LIMBO-style grass blades into a single path, so a whole
/// screen of grass is one draw call.
///
/// Every blade is deterministic in its root position, so the grass does not
/// shimmer as the camera moves; only the wind and the boy's passing move the
/// tips.
abstract final class GrassPainter {
  static double _hash(double x) {
    final double value = math.sin(x * 127.1 + 311.7) * 43758.5453;
    return value - value.floorToDouble();
  }

  /// Slowly varying 0..1 noise: where the clumps and the bald patches are.
  static double _clumps(double x, double seed) =>
      0.5 +
      0.32 * math.sin(x * 0.83 + seed) * math.sin(x * 0.37 + seed * 2.1) +
      0.18 * math.sin(x * 2.9 + seed * 0.7);

  /// Adds the blades rooted between [left] and [right] to [path].
  /// [surface] gives the ground's y at a world x, or null where there is
  /// no ground to grow from.
  static void addBlades(
    Path path, {
    required double left,
    required double right,
    required double? Function(double x) surface,
    required GrassStyle style,
    required GrassWind wind,
  }) {
    final double spacing = style.spacing;
    final double t = wind.time;
    final bool pushed = wind.pusherX.isFinite;
    for (
      double x = (left / spacing).floorToDouble() * spacing;
      x < right;
      x += spacing
    ) {
      final double id = x * 1.37 + style.seed;
      final double clump = _clumps(x, style.seed);
      if (_hash(id) > style.coverage * (0.35 + clump)) continue;
      final double rootX = x + (_hash(id + 1.3) - 0.5) * spacing;
      final double? groundY = surface(rootX);
      if (groundY == null) continue;
      final double rootY = groundY + 0.02;

      final double tall = math.pow(_hash(id + 2.9), 2.2).toDouble();
      double height =
          style.minHeight +
          (style.maxHeight - style.minHeight) * _hash(id + 4.1) +
          style.clumpHeight * tall * clump * clump;
      final bool stalk = _hash(id + 7.7) < style.stalkChance;
      if (stalk) height = style.clumpHeight * (0.9 + _hash(id + 8.1) * 0.6);

      // Lean: a prevailing breeze, gusts travelling along the field, and the
      // boy's legs parting the grass as he passes.
      double lean =
          (_hash(id + 5.3) - 0.42) * 0.55 +
          0.12 +
          math.sin(t * 1.25 - rootX * 0.55) * 0.10 +
          math.sin(t * 2.7 - rootX * 1.9 + 1.0) * 0.05;
      if (pushed) {
        final double d = rootX - wind.pusherX;
        if (d.abs() < 0.8) {
          final double influence = math.exp(-(d * d) / 0.07);
          lean +=
              d.sign *
              influence *
              (0.55 + 0.5 * (wind.pusherSpeed.abs() / 3.2).clamp(0.0, 1.0));
          height *= 1 - influence * 0.25;
        }
      }
      final double width = style.bladeWidth * (0.6 + _hash(id + 6.2) * 0.8);
      final double tipX = rootX + lean * height;
      final double tipY = rootY - height * (1 - 0.18 * lean.abs());
      final double midX = rootX + lean * height * 0.25;
      final double midY = rootY - height * 0.62;
      path
        ..moveTo(rootX - width, rootY)
        ..quadraticBezierTo(midX - width * 0.4, midY, tipX, tipY)
        ..quadraticBezierTo(midX + width * 0.6, midY, rootX + width, rootY)
        ..close();
      if (stalk) {
        // A seed head: a small elongated oval at the tip.
        final double angle = math.atan2(tipY - midY, tipX - midX);
        final double c = math.cos(angle), s = math.sin(angle);
        const double headLength = 0.05, headWidth = 0.011;
        path
          ..moveTo(tipX - c * 0.004, tipY - s * 0.004)
          ..quadraticBezierTo(
            tipX + c * headLength * 0.5 - s * headWidth,
            tipY + s * headLength * 0.5 + c * headWidth,
            tipX + c * headLength,
            tipY + s * headLength,
          )
          ..quadraticBezierTo(
            tipX + c * headLength * 0.5 + s * headWidth,
            tipY + s * headLength * 0.5 - c * headWidth,
            tipX - c * 0.004,
            tipY - s * 0.004,
          )
          ..close();
      }
    }
  }
}
