/// Native Box2D categories. Background art never creates shapes.
abstract final class CollisionLayers {
  static const terrain = 1;
  static const player = 2;
  static const prop = 4;
  static const sensor = 8;
  static const ragdoll = 16;
  static const solid = terrain | prop;
  static const all = terrain | player | prop | sensor | ragdoll;
}
