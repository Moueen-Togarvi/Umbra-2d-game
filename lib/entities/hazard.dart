import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/palette.dart';
import '../world/checkpoint_service.dart';
import 'player.dart';

/// A deadly zone. Touching it respawns the player at the last checkpoint.
///
/// Implemented as a **sensor**: a shape that takes part in collision *detection*
/// but not in collision *response*. The player walks straight through it and
/// the engine reports the overlap, which is exactly what a trigger volume
/// needs. The same mechanism will carry the water zone in Step 4.
///
/// The hazard is invisible in the world — it is drawn as black like everything
/// else, so in the test room it reads as the dark floor of the pit.
class Hazard extends BodyComponent with ContactCallbacks {
  Hazard({
    required Vector2 center,
    required Vector2 size,
    required this._checkpoints,
  }) : super(
         // BodyComponent paints white by default, which would be invisible
         // against the light-grey background.
         paint: Paint()..color = Palette.silhouette,
         bodyDef: BodyDef(type: BodyType.static, position: center.clone()),
         shapeSpecs: [
           ShapeSpec(
             Polygon.box(size.x / 2, size.y / 2),
             ShapeDef(isSensor: true),
           ),
         ],
       ) {
    // Because this userData is a ContactCallbacks, BodyComponent automatically
    // switches on the contact and sensor event flags for the shapes above —
    // that convenience only applies when the callbacks are attached before the
    // body is built, which is why this happens here.
    bodyDef!.userData = this;
  }

  final CheckpointService _checkpoints;

  /// Builds a hazard from its edges, matching the way ground slabs are
  /// described in the test room.
  factory Hazard.zone({
    required double left,
    required double right,
    required double top,
    required double bottom,
    required CheckpointService checkpoints,
  }) {
    return Hazard(
      center: Vector2((left + right) / 2, (top + bottom) / 2),
      size: Vector2(right - left, bottom - top),
      checkpoints: checkpoints,
    );
  }

  @override
  void beginContact(Object other, Contact contact) {
    // `other` is the userData of whatever touched us. Only the player dies.
    if (other is! Player) {
      return;
    }

    // Moving a body from inside a contact callback is safe here, which is not
    // true of every physics engine. flame_forge2d steps the world first and
    // dispatches the events it collected afterwards, so by the time we are
    // called the solver has finished and the world is safe to mutate.
    _checkpoints.respawn(other);
  }
}
