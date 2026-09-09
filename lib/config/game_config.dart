import 'dart:math' as math;

import 'package:flame/game.dart' show Vector2;

/// Every tunable number in the game lives here.
///
/// The rule for this file: if you would ever want to change a value to make the
/// game *feel* different, it belongs in here and nowhere else. Entities read
/// from this file; they never hard-code a number of their own.
///
/// ## Units
///
/// The physics world is measured in **metres, kilograms and seconds**, because
/// that is what Box2D is tuned for. It is not measured in pixels. Pixels only
/// appear at the very last moment, when the camera draws the world, and the
/// conversion factor is [metersToPixels].
///
/// Box2D has a handful of internal tolerances that are absolute lengths rather
/// than fractions of the objects they apply to (for example it starts reporting
/// a contact once two shapes are within 2 cm of each other). Those numbers are
/// only "too small to notice" if your objects are roughly the size of real
/// objects. Lay a world out in pixels — a 40x80 "player" — and those tolerances
/// become invisible compared to the shapes, so bodies collide with things they
/// are not touching, never bounce, and fall asleep while still moving.
///
/// The guidance is to keep moving bodies between 0.1 m and 10 m. Our player is
/// 1.6 m tall, like a person. Everything else follows from that.
abstract final class GameConfig {
  // ---------------------------------------------------------------------------
  // Rendering scale
  // ---------------------------------------------------------------------------

  /// How many screen pixels one metre of physics world is drawn as.
  ///
  /// This is *only* a rendering concern — changing it makes the game look
  /// bigger or smaller and does not change the simulation at all. It is
  /// deliberately separate from the camera's `zoom`, which stays free for
  /// actual camera work later.
  static const double metersToPixels = 100.0;

  // ---------------------------------------------------------------------------
  // Room dimensions (metres)
  // ---------------------------------------------------------------------------

  /// Width of the whole test room. The camera is fitted to this.
  static const double roomWidth = 12.0;

  /// Height of the whole test room.
  static const double roomHeight = 7.0;

  /// Thickness of the invisible walls that keep the player inside the room.
  static const double wallThickness = 0.5;

  // ---------------------------------------------------------------------------
  // Gravity
  // ---------------------------------------------------------------------------

  /// Downward acceleration, in metres per second squared.
  ///
  /// Real Earth gravity is 9.81. Almost every platformer runs at 2-3x that,
  /// because real gravity makes a jump arc feel slow and floaty at the scale of
  /// a screen. 28 gives Umbra a heavy, weighted fall that suits the mood.
  ///
  /// Note the sign: Flame's y-axis points **down**, so positive y is downward.
  /// (Raw Box2D uses y-up and would write this as -28. flame_forge2d flips the
  /// convention for you, which is why its default gravity is `(0, 10)` and not
  /// `(0, -10)`.)
  static const double gravityMetersPerSecondSquared = 28.0;

  /// Gravity as a vector. A getter rather than a constant because [Vector2] is
  /// mutable and each caller should get its own instance.
  static Vector2 get gravity => Vector2(0, gravityMetersPerSecondSquared);

  // ---------------------------------------------------------------------------
  // Player
  // ---------------------------------------------------------------------------

  /// Player silhouette width in metres.
  static const double playerWidth = 0.8;

  /// Player silhouette height in metres — roughly a small adult.
  static const double playerHeight = 1.6;

  /// Player mass in kilograms.
  static const double playerMassKilograms = 70.0;

  /// Box2D derives a body's mass from the *density* of its shapes rather than
  /// letting you set the mass directly, so we work backwards from the mass we
  /// actually want. Density is in kilograms per square metre because the
  /// simulation is two-dimensional.
  static const double playerDensity =
      playerMassKilograms / (playerWidth * playerHeight);

  /// Horizontal walking speed in metres per second.
  ///
  /// About 4 m/s is a brisk jog for a person. Lower it towards 2.0 for a more
  /// deliberate, Limbo-like trudge.
  static const double moveSpeedMetersPerSecond = 4.0;

  /// How high the player's jump peaks, in metres, measured from the take-off
  /// point.
  ///
  /// This is the number to tune when the jump feels wrong. The take-off
  /// velocity is derived from it rather than guessed — see [jumpTakeoffSpeed].
  static const double jumpApexMeters = 1.9;

  /// The upward speed needed at take-off to reach [jumpApexMeters].
  ///
  /// Straight from kinematics: a body launched at speed `v` against gravity `g`
  /// rises `h = v^2 / (2g)` before stopping. Solving for `v` gives
  /// `v = sqrt(2 * g * h)`.
  ///
  /// Deriving it means the apex stays correct when you change gravity, and it
  /// means there is no unexplained "jump force = 600" constant in the codebase.
  static double get jumpTakeoffSpeed =>
      math.sqrt(2 * gravityMetersPerSecondSquared * jumpApexMeters);

  // ---------------------------------------------------------------------------
  // Ground detection
  // ---------------------------------------------------------------------------

  /// Half-width of the foot sensor, as a fraction of the player's half-width.
  ///
  /// Slightly narrower than the body so that brushing a wall never counts as
  /// standing on something.
  static const double footSensorWidthFactor = 0.9;

  /// Half-height of the foot sensor in metres.
  ///
  /// It straddles the sole of the feet, so it reaches this far below the
  /// player. Keep it small: the larger it is, the further off the ground the
  /// player can still jump.
  static const double footSensorHalfHeight = 0.06;

  // ---------------------------------------------------------------------------
  // Test room layout (metres, origin at the room's top-left, y pointing down)
  // ---------------------------------------------------------------------------

  /// Height of the floor surface the player walks on.
  static const double floorSurfaceY = 6.0;

  /// Thickness of the floor slabs.
  static const double floorThickness = 1.0;

  /// The left floor slab spans x = 0 to here.
  static const double gapStartX = 5.0;

  /// The right floor slab starts here and runs to the right wall.
  static const double gapEndX = 7.0;

  /// Top surface of the raised platform, for a jump that has to clear something.
  static const double platformSurfaceY = 4.6;

  /// Thickness of the raised platform.
  static const double platformThickness = 0.3;

  /// Horizontal span of the raised platform.
  static const double platformStartX = 8.5;
  static const double platformEndX = 10.5;

  /// Where the player starts, and the first checkpoint. This is the *centre* of
  /// the player body, so it sits half the player's height above the floor.
  static Vector2 get playerSpawn =>
      Vector2(1.5, floorSurfaceY - playerHeight / 2);
}
