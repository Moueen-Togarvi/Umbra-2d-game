import 'package:flame_forge2d/flame_forge2d.dart';

import '../entities/hill_ground.dart';
import '../physics/collision_layers.dart';

/// Where a foot meets the ground, in world metres.
class GroundContact {
  GroundContact(this.point, this.normal, this.body);

  /// The visible surface point.
  final Vector2 point;

  /// Unit surface normal, pointing up (negative y).
  final Vector2 normal;

  /// What the foot stands on, so a planted foot can ride a moving platform.
  final Body body;
}

/// Finds the ground under world x, searching [depth] metres down from
/// [fromY]. Returns null where there is nothing to stand on.
typedef GroundQuery =
    GroundContact? Function(double x, double fromY, double depth);

/// Casts straight down through solid shapes (skipping [ignore], sensors and
/// walls) and reports the *visible* surface.
///
/// On an earth bank that is its drawn, roughened edge rather than the smooth
/// collision chain under it, so a foot lands on the crumb or stone the
/// player can see instead of hovering a centimetre above or inside it. The
/// normal stays the collision normal: smooth, so soles don't jitter on
/// every crumb.
GroundContact? probeGround(
  Forge2DWorld world,
  double x,
  double fromY,
  double depth, {
  Body? ignore,
}) {
  RayHit? closest;
  world.castRay(Vector2(x, fromY), Vector2(0, depth), (hit) {
    if (hit.shape.body == ignore || hit.shape.isSensor || hit.normal.y > -0.6) {
      return -1;
    }
    closest = hit;
    return hit.fraction;
  }, filter: QueryFilter(maskBits: CollisionLayers.solid));
  final hit = closest;
  if (hit == null) return null;
  final data = hit.shape.body.userData;
  if (data is HillGround && x >= data.segment.left && x <= data.segment.right) {
    return GroundContact(
      Vector2(x, data.drawnHeightAt(x)),
      hit.normal.clone(),
      hit.shape.body,
    );
  }
  return GroundContact(hit.point.clone(), hit.normal.clone(), hit.shape.body);
}
