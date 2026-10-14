import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../physics/collision_layers.dart';
import '../render/culling.dart';

/// A boulder half sunk in the ground, low enough to hop over.
///
/// Its collision is a convex, slightly rounded polygon, and what is drawn is
/// that same outline, so a foot lands on the stone that is there. It rests
/// on the highest drawn ground under it, settled a few centimetres in, and
/// its base reaches down below the lowest, so no light shows under it and
/// nothing gets beneath it; a little heaped soil sits at its foot.
class Rock extends BodyComponent with OffScreenCulling {
  Rock({
    required this.left,
    required this.right,
    required this.height,
    required this.groundBelow,
  }) : super(
         paint: Paint()..color = const Color(0xFF070707),
         renderBody: false,
       );

  final double left, right, height;

  /// The drawn ground, world y at world x.
  final double Function(double x) groundBelow;

  /// The polygon's corner rounding, metres.
  static const double rounding = 0.03;

  late final List<Vector2> _corners;
  late final Path _outline;

  /// The silhouette as drawn, body-local, for tests.
  @visibleForTesting
  Path get outline => _outline;

  /// The highest drawn ground under the rock, world y: where it rests.
  late final double restY;

  @override
  Body createBody() {
    var highest = double.infinity, lowest = double.negativeInfinity;
    for (double x = left; x <= right + 1e-9; x += 0.04) {
      final double y = groundBelow(x);
      highest = math.min(highest, y);
      lowest = math.max(lowest, y);
    }
    restY = highest;
    final double w = right - left;
    final center = Vector2((left + right) / 2, highest);
    // Settled 6 cm into the soil, its base well under the lowest ground.
    final double sunk = 0.06;
    final double base = lowest - highest + 0.06;
    final double h = height + sunk;
    final random = math.Random((left * 413).round());
    double jitter() => (random.nextDouble() - 0.5) * 0.04;
    _corners = [
      Vector2(-w / 2, base),
      Vector2(-w / 2 * 0.97, sunk - h * (0.35 + jitter())),
      Vector2(-w * 0.34, sunk - h * (0.86 + jitter())),
      Vector2(-w * 0.06, sunk - h),
      Vector2(w * 0.22, sunk - h * (0.96 + jitter())),
      Vector2(w * 0.43, sunk - h * (0.68 + jitter())),
      Vector2(w / 2, sunk - h * (0.22 + jitter())),
      Vector2(w / 2 * 0.96, base),
    ];
    final result = world.createBody(
      BodyDef(type: BodyType.static, position: center, userData: this),
    );
    result.createShape(
      Polygon(_corners, radius: rounding),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.8),
        enableSensorEvents: true,
      ),
    );
    _outline = _buildOutline(center, random);
    return result;
  }

  /// The polygon grown by its rounding, as the collision shape is, plus a
  /// chip or two out of its lower flanks and a little heaped soil at its
  /// foot. Body-local metres.
  Path _buildOutline(Vector2 center, math.Random random) {
    final n = _corners.length;
    final path = Path();
    final grown = <Vector2>[];
    for (var i = 0; i < n; i++) {
      final prev = _corners[(i - 1 + n) % n];
      final point = _corners[i];
      final next = _corners[(i + 1) % n];
      // Outward normals of the two edges meeting here: the corners run
      // up the left side, over the top and down the right, clockwise on
      // screen (y down).
      Vector2 normal(Vector2 a, Vector2 b) {
        final d = (b - a)..normalize();
        return Vector2(d.y, -d.x);
      }

      final bisector = normal(prev, point) + normal(point, next);
      final Vector2 offset = bisector.length2 < 1e-9
          ? Vector2.zero()
          : (bisector..normalize()) * rounding;
      grown.add(point + offset);
    }
    // A rounded, weathered outline through the grown polygon: curves
    // through each edge's middle, bulging to the corners, with a little
    // grain — within a couple of centimetres of what the feet stand on.
    final mids = [
      for (var i = 0; i < n; i++) (grown[i] + grown[(i + 1) % n]) * 0.5,
    ];
    path.moveTo(mids.last.x, mids.last.y);
    for (var i = 0; i < n; i++) {
      final corner = grown[i];
      final mid = mids[i];
      final double grain = (random.nextDouble() - 0.5) * 0.012;
      path.quadraticBezierTo(corner.x, corner.y + grain, mid.x, mid.y);
    }
    path.close();
    // Soil heaped against its foot on both sides.
    for (final side in const [-1.0, 1.0]) {
      final double x = side * (right - left) / 2;
      final double ground = groundBelow(center.x + x) - center.y;
      path.addOval(
        Rect.fromCenter(
          center: Offset(x, ground + 0.01),
          width: 0.12 + random.nextDouble() * 0.06,
          height: 0.06,
        ),
      );
    }
    return path;
  }

  @override
  void render(Canvas canvas) {
    final Rect bounds = _outline.getBounds().shift(
      Offset(body.position.x, body.position.y),
    );
    if (isOnScreen(bounds)) canvas.drawPath(_outline, paint);
  }
}
