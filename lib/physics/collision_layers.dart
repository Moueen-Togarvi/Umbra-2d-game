import 'package:flame_forge2d/flame_forge2d.dart' show Filter;

/// Native Box2D categories. Background art never creates shapes.
abstract final class CollisionLayers {
  static const terrain = 1;
  static const player = 2;
  static const prop = 4;
  static const sensor = 8;
  static const ragdoll = 16;
  static const solid = terrain | prop;
  static const all = terrain | player | prop | sensor | ragdoll;

  /// A prop: it meets the ground, other props, the boy and his limp body.
  /// Without [withPlayer] the boy passes through it; without [collides]
  /// it meets nothing at all.
  static Filter propFilter({bool withPlayer = true, bool collides = true}) =>
      Filter(
        categoryBits: prop,
        maskBits: !collides
            ? 0
            : terrain | prop | ragdoll | (withPlayer ? player : 0),
      );
}
