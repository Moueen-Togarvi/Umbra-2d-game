import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../physics/collision_layers.dart';
import 'player.dart';

/// A pit of sharpened stakes. Touching the stakes kills the boy: the body
/// goes limp and falls onto them, and the death sequence takes it from there.
///
/// The stakes are a **sensor**: a shape that takes part in collision
/// *detection* but not in collision *response*, so the engine reports the
/// touch without the stakes holding him up. Below their points a solid
/// floor catches the limp body, so it comes to rest among the stakes rather
/// than falling out of the world.
class Hazard extends BodyComponent with ContactCallbacks {
  Hazard({required Vector2 center, required Vector2 size})
    : _size = size.clone(),
      super(
        paint: Paint()..color = Palette.silhouette,
        renderBody: false,
        bodyDef: BodyDef(type: BodyType.static, position: center.clone()),
        shapeSpecs: [
          ShapeSpec(
            Polygon.box(size.x / 2, size.y / 2),
            ShapeDef(
              isSensor: true,
              filter: Filter(
                categoryBits: CollisionLayers.sensor,
                maskBits: CollisionLayers.player | CollisionLayers.ragdoll,
              ),
            ),
          ),
          // The floor the stakes stand in, a little below their points.
          ShapeSpec(
            Polygon.offsetBox(
              size.x / 2,
              size.y / 2 - stakeHeight / 2,
              center: Vector2(0, stakeHeight / 2),
            ),
            ShapeDef(
              filter: Filter(categoryBits: CollisionLayers.terrain),
              material: SurfaceMaterial(friction: 0.9),
            ),
          ),
        ],
      ) {
    // Because this userData is a ContactCallbacks, BodyComponent automatically
    // switches on the contact and sensor event flags for the shapes above —
    // that convenience only applies when the callbacks are attached before the
    // body is built, which is why this happens here.
    bodyDef!.userData = this;
  }

  /// How far the stakes stand above the pit floor.
  static const double stakeHeight = 0.55;

  final Vector2 _size;

  /// The stakes, built once in body-local metres.
  late final Path _stakes = _buildStakes();

  Path _buildStakes() {
    final double hw = _size.x / 2;
    final double hh = _size.y / 2;
    final double base = -hh + stakeHeight;
    // The floor runs under the undercut banks on both sides.
    final Path path = Path()
      ..moveTo(-hw - 0.15, hh)
      ..lineTo(-hw - 0.15, base)
      ..lineTo(hw + 0.15, base)
      ..lineTo(hw + 0.15, hh)
      ..close();
    // Sharpened poles at uneven heights and angles, the way they would be
    // driven into the bottom of a pit by hand.
    final random = math.Random((_size.x * 1000).round());
    for (
      double x = -hw + 0.08;
      x < hw - 0.04;
      x += 0.13 + random.nextDouble() * 0.09
    ) {
      final double height = stakeHeight * (0.65 + random.nextDouble() * 0.45);
      final double lean = (random.nextDouble() - 0.5) * 0.35;
      final double width = 0.035 + random.nextDouble() * 0.02;
      final double tipX = x + lean * height;
      final double shoulderY = base - height * 0.78;
      path
        ..moveTo(x - width / 2, base + 0.02)
        ..lineTo(x - width / 2 + lean * height * 0.78, shoulderY)
        ..lineTo(tipX, base - height)
        ..lineTo(x + width / 2 + lean * height * 0.78, shoulderY)
        ..lineTo(x + width / 2, base + 0.02)
        ..close();
    }
    return path;
  }

  final Paint _shadowPaint = Paint();

  @override
  void render(Canvas canvas) {
    // The drop above the stakes: fog at the lip, black by the time it
    // reaches them. Without this a pit shows bright fog all the way down to
    // a hard black block at the bottom, which reads as a slab floating in
    // mid-air rather than as a hole in the ground.
    // It reaches under the undercut banks on both sides, so no fog shows
    // between a crumbling cliff face and the shaft.
    final double hw = _size.x / 2;
    final double hh = _size.y / 2;
    final double lip = -hh - GameConfig.pitDepth;
    _shadowPaint.shader = Gradient.linear(
      Offset(0, lip),
      Offset(0, -hh + stakeHeight),
      const [Color(0x00000000), Color(0x38000000), Color(0x80000000)],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(-hw - 0.15, lip, hw + 0.15, -hh + stakeHeight + 0.05),
      _shadowPaint,
    );
    canvas.drawPath(_stakes, paint);
  }

  /// Builds a hazard from its edges, matching the way ground slabs are
  /// described in the level.
  factory Hazard.zone({
    required double left,
    required double right,
    required double top,
    required double bottom,
  }) {
    return Hazard(
      center: Vector2((left + right) / 2, (top + bottom) / 2),
      size: Vector2(right - left, bottom - top),
    );
  }

  @override
  void beginContact(Object other, Contact contact) {
    // `other` is the userData of whatever touched us: the capsule, or a
    // limb of the ragdoll, both of which carry the Player.
    if (other is Player) other.die();
  }
}
