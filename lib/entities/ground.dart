import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/palette.dart';

/// A solid, immovable slab: floors, walls and platforms.
///
/// This is a **static** body. Static bodies have infinite mass, are never moved
/// by the solver, and do not collide with each other — which makes them
/// essentially free to simulate. Level geometry should almost always be static.
///
/// Unlike [Player], this entity is built with the declarative `bodyDef` +
/// `shapeSpecs` form instead of overriding `createBody`. For a body with one
/// shape and no custom logic, that is the shorter and clearer of the two.
class Ground extends BodyComponent {
  Ground({required Vector2 center, required Vector2 size})
    : super(
        paint: Paint()..color = Palette.silhouette,
        bodyDef: BodyDef(type: BodyType.static, position: center.clone()),
        shapeSpecs: [
          ShapeSpec(
            // Half-extents, as always in Box2D.
            Polygon.box(size.x / 2, size.y / 2),
            ShapeDef(
              // The player's foot sensor can only detect shapes that have
              // opted in to sensor events. Leaving this out is the single most
              // common reason a ground check "just doesn't work": everything
              // looks right, the player lands correctly, and jumping never
              // fires again.
              enableSensorEvents: true,
            ),
          ),
        ],
      ) {
    // `this` is not available in an initialiser list, so the userData is
    // attached here, in the constructor body, before the body is ever created.
    //
    // This is required, not cosmetic: the foot sensor identifies what it has
    // landed on by looking at userData, and a slab with none is invisible to
    // it.
    bodyDef!.userData = this;
  }

  /// Builds a slab from its edges rather than its centre, which is how level
  /// geometry is naturally described: "floor from x=0 to x=5, top surface at
  /// y=6".
  factory Ground.slab({
    required double left,
    required double right,
    required double top,
    required double thickness,
  }) {
    return Ground(
      center: Vector2((left + right) / 2, top + thickness / 2),
      size: Vector2(right - left, thickness),
    );
  }
}
