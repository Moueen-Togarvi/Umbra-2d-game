import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../physics/collision_layers.dart';
import '../world/checkpoint_service.dart';
import 'player.dart';

/// A deadly zone. Touching it respawns the player at the last checkpoint.
///
/// Implemented as a **sensor**: a shape that takes part in collision *detection*
/// but not in collision *response*. The player walks straight through it and
/// the engine reports the overlap, which is exactly what a trigger volume
/// needs. The same mechanism will carry the water zone in Step 4.
///
/// Drawn as the floor of a pit bristling with spikes: black like everything
/// else, but with a jagged top edge that reads as "do not land here" from
/// across the screen.
class Hazard extends BodyComponent with ContactCallbacks {
  Hazard({
    required Vector2 center,
    required Vector2 size,
    required this._checkpoints,
  }) : _size = size.clone(),
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
         ],
       ) {
    // Because this userData is a ContactCallbacks, BodyComponent automatically
    // switches on the contact and sensor event flags for the shapes above —
    // that convenience only applies when the callbacks are attached before the
    // body is built, which is why this happens here.
    bodyDef!.userData = this;
  }

  final CheckpointService _checkpoints;
  final Vector2 _size;

  /// The spiked floor, built once in body-local metres.
  late final Path _spikes = _buildSpikes();

  Path _buildSpikes() {
    final double hw = _size.x / 2;
    final double hh = _size.y / 2;
    const double spikeHeight = 0.55;
    const double spikeWidth = 0.28;
    final Path path = Path()..moveTo(-hw, hh);
    path.lineTo(-hw, -hh + spikeHeight);
    double x = -hw;
    var i = 0;
    while (x < hw) {
      // Alternate tall and short spikes, leaning slightly, so the row does
      // not look machine-made.
      final double h = spikeHeight * (i.isEven ? 1.0 : 0.62);
      final double lean = (i % 3 - 1) * 0.04;
      final double tip = math.min(hw, x + spikeWidth / 2 + lean);
      final double base = math.min(hw, x + spikeWidth);
      path.lineTo(tip, -hh + spikeHeight - h);
      path.lineTo(base, -hh + spikeHeight);
      x = base;
      i++;
    }
    path.lineTo(hw, hh);
    path.close();
    return path;
  }

  final Paint _shadowPaint = Paint();

  @override
  void render(Canvas canvas) {
    // The drop above the spikes: fog at the lip, black by the time it
    // reaches them. Without this a pit shows bright fog all the way down to
    // a hard black block at the bottom, which reads as a slab floating in
    // mid-air rather than as a hole in the ground.
    final double hw = _size.x / 2;
    final double hh = _size.y / 2;
    final double lip = -hh - GameConfig.pitDepth;
    _shadowPaint.shader = Gradient.linear(
      Offset(0, lip),
      Offset(0, -hh + 0.2),
      const [Color(0x59000000), Color(0xD9000000), Color(0xFF000000)],
      const [0.0, 0.4, 1.0],
    );
    canvas.drawRect(Rect.fromLTRB(-hw, lip, hw, -hh + 0.3), _shadowPaint);
    canvas.drawPath(_spikes, paint);
  }

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
