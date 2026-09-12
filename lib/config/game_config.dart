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
  // Level dimensions (metres)
  // ---------------------------------------------------------------------------

  /// Total width of the level. The camera scrolls along it.
  static const double levelWidth = 64.0;

  /// Total height of the level. Ground slabs extend all the way down to this,
  /// so there is never a gap of fog visible *under* the floor.
  static const double levelHeight = 12.0;

  /// Kept for the old name's sake: the width used by the physics tests.
  static const double roomWidth = levelWidth;
  static const double roomHeight = levelHeight;

  /// How much of the world the camera frames, in metres. Flame fits this box
  /// inside the screen, so a wider phone simply sees more of the level to the
  /// sides. 9 m tall puts a 1.6 m player at about a sixth of the screen,
  /// which is the small-figure-in-a-vast-world framing the reference art has.
  static const double cameraVisibleWidth = 16.0;
  static const double cameraVisibleHeight = 9.0;

  /// How far above the player's centre the camera aims. Positive is *up*.
  /// Looking up shows more sky and canopy and less dead black ground.
  static const double cameraLookUp = 1.4;

  /// How far ahead of the player, in the direction of travel, the camera
  /// leads. Lets the player see what they are walking into.
  static const double cameraLookAhead = 1.0;

  /// How quickly the camera catches up with its target, per second. Larger
  /// is snappier; around 3 gives a slow cinematic drift.
  static const double cameraFollowSpeed = 3.0;

  /// The lowest the camera's centre may go. Stops a fall into a pit from
  /// dragging the view down and showing the fog *under* the forest.
  static const double cameraMaxY = 6.0;

  /// Thickness of the walls that keep the player inside the level. Thick so
  /// that the player can never tunnel through at speed.
  static const double wallThickness = 3.0;

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

  /// Player collision width in metres. Narrower than the drawn figure's
  /// reach, so a swinging arm never snags on a wall.
  static const double playerWidth = 0.5;

  /// Player height in metres. The figure is a child, small against the world
  /// — that is most of what makes the world feel vast.
  static const double playerHeight = 1.3;

  /// Player mass in kilograms.
  static const double playerMassKilograms = 40.0;

  /// Box2D derives a body's mass from the *density* of its shapes rather than
  /// letting you set the mass directly, so we work backwards from the mass we
  /// actually want. Density is in kilograms per square metre because the
  /// simulation is two-dimensional.
  static const double playerDensity =
      playerMassKilograms / (playerWidth * playerHeight);

  /// Horizontal running speed in metres per second. A child's run.
  static const double moveSpeedMetersPerSecond = 3.2;

  /// How quickly the player reaches [moveSpeedMetersPerSecond] on the
  /// ground, in m/s². 24 gets to full speed in about an eighth of a second:
  /// enough of a ramp that starting to run reads as a push-off rather than a
  /// teleport, not so much that the controls feel laggy. Stopping on the
  /// ground is instant.
  static const double groundAcceleration = 24.0;

  /// Acceleration while airborne. Lower than on the ground: you can steer a
  /// jump, but not reverse it outright.
  static const double airAcceleration = 12.0;

  /// Extra gravity on the way *down*, as a multiple of [gravity]. Rising at
  /// 1x and falling at 1.45x is the classic platformer trick: the jump still
  /// reaches its apex, but the fall is quicker and heavier, so a jump feels
  /// like a hop rather than a float.
  static const double fallGravityMultiplier = 1.45;

  /// How long after walking off an edge a jump is still allowed, in seconds.
  /// Without this, pressing jump on the last pixel of a ledge — which is
  /// exactly where people press it — fails, and the game feels unfair.
  static const double coyoteTimeSeconds = 0.12;

  /// How long before landing a jump press is remembered, in seconds. Pressing
  /// slightly early then lands and jumps in one motion instead of being lost.
  static const double jumpBufferSeconds = 0.12;

  /// How high the player's jump peaks, in metres, measured from the take-off
  /// point.
  ///
  /// This is the number to tune when the jump feels wrong. The take-off
  /// velocity is derived from it rather than guessed — see [jumpTakeoffSpeed].
  static const double jumpApexMeters = 1.8;

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
  // Level layout (metres, origin at the level's top-left, y pointing down)
  // ---------------------------------------------------------------------------

  /// The ground, as a list of slabs described by their left edge, right edge
  /// and top surface. Anything between 0 and [levelWidth] that no slab
  /// covers is a pit, and the level builder puts a hazard at the bottom.
  ///
  /// Pits are 1.4 m wide: at [moveSpeedMetersPerSecond] and [jumpApexMeters]
  /// a running jump carries about 2.4 m, which leaves roughly half a second
  /// in which pressing jump clears the pit — forgiving, but never walkable. Steps up are at most 1.3 m, comfortably
  /// under the jump apex.
  static const List<Slab> terrain = [
    Slab(left: 0, right: gapStartX, top: floorSurfaceY), // the shore
    Slab(left: gapEndX, right: 24, top: 7.2),
    Slab(left: 24, right: 27, top: 6.6), // steps up into the mist
    Slab(left: 27, right: 30, top: 6.0),
    Slab(left: 31.4, right: 42, top: 6.4),
    Slab(left: 42, right: 50, top: 5.2), // the dark forest, high ground
    Slab(left: 51.4, right: levelWidth, top: 5.6),
  ];

  /// Fallen logs lying across the path. Each sits 1.1 m above its floor:
  /// too tall to walk past, since the player is 1.3 m and the log's underside
  /// meets the head, but low enough that a hop lands on it with a generous
  /// timing window. Higher and the hop has to be timed to the frame.
  static const List<Slab> ledges = [
    Slab(left: 19, right: 21, top: 6.1),
    Slab(left: 36, right: 38, top: 5.3),
    Slab(left: 45.5, right: 47.5, top: 4.1),
  ];

  /// Thickness of a ledge.
  static const double ledgeThickness = 0.3;

  /// How deep below the surrounding ground a pit's deadly floor sits.
  static const double pitDepth = 2.4;

  /// The first slab's surface: where the player spawns and where the physics
  /// tests expect the floor to be.
  static const double floorSurfaceY = 7.5;

  /// The first pit, between the shore and the next slab. The tests drop the
  /// player into this one.
  static const double gapStartX = 14.0;
  static const double gapEndX = 15.4;

  /// Where the player starts, and the first checkpoint. This is the *centre*
  /// of the player body, so it sits half the player's height above the floor.
  static Vector2 get playerSpawn =>
      Vector2(2.0, floorSurfaceY - playerHeight / 2);

  // ---------------------------------------------------------------------------
  // Scenery
  // ---------------------------------------------------------------------------

  /// The silhouettes that stand in the fog behind the player, placed one at a
  /// time along the level rather than tiled, so that each screen holds a
  /// single thing to look at — a tree, a gallows, a tower — and the rest is
  /// empty mist. That emptiness is the look; a busy backdrop kills it.
  ///
  /// [SceneryProp.depth] is how far into the fog the thing stands: 0 is right
  /// behind the player, 1 is the horizon. It sets how the prop scrolls, how
  /// faint it is drawn, and whether the soft (blurred) art is used.
  static const List<SceneryProp> scenery = [
    SceneryProp('prop_tree_b', x: 4.5, y: 7.5, height: 7.5, depth: 0.55),
    SceneryProp('prop_fence', x: 9.5, y: 7.5, height: 1.5, depth: 0.12),
    SceneryProp('prop_tree_a', x: 13.0, y: 7.5, height: 8.5, depth: 0.05),
    SceneryProp('prop_gallows', x: 21.0, y: 7.2, height: 5.6, depth: 0.22),
    SceneryProp('prop_tree_a', x: 27.5, y: 6.6, height: 7.0, depth: 0.65),
    SceneryProp('prop_boulder', x: 34.5, y: 6.4, height: 1.3, depth: 0.15),
    SceneryProp(
      'prop_ladder',
      x: 38.5,
      y: -0.6,
      height: 5.0,
      depth: 0.08,
      hangs: true,
    ),
    SceneryProp('prop_tower', x: 44.5, y: 5.2, height: 9.0, depth: 0.72),
    SceneryProp('prop_tree_b', x: 48.5, y: 5.2, height: 7.0, depth: 0.10),
    SceneryProp('prop_watchtower', x: 56.0, y: 5.6, height: 6.5, depth: 0.55),
    SceneryProp('prop_tree_a', x: 61.5, y: 5.6, height: 8.0, depth: 0.50),
  ];

  // ---------------------------------------------------------------------------
  // On-screen controls
  //
  // WARNING: everything below is in LOGICAL PIXELS, not metres.
  //
  // These are the only numbers in this file that are not part of the physics
  // simulation. Touch controls live in the camera's *viewport*, which is screen
  // space, so that a button stays the size of a thumb no matter how far the
  // world is zoomed. Do not feed these into anything that takes a world
  // coordinate, and do not scale them by [metersToPixels].
  // ---------------------------------------------------------------------------

  /// Diameter of a control button.
  ///
  /// Material's minimum touch target is 48dp; a game that is held in both hands
  /// and played with thumbs wants considerably more than the minimum.
  static const double controlButtonDiameterPx = 88.0;

  /// Gap between the screen edge and the nearest button.
  static const double controlEdgeMarginPx = 28.0;

  /// Gap between the two walk buttons.
  static const double controlGapPx = 20.0;

  /// Size of the arrow glyph inside a button, as a fraction of its radius.
  static const double controlGlyphScale = 0.46;
}

/// A horizontal run of solid ground: from [left] to [right], with its walkable
/// surface at [top]. Slabs are described by their edges rather than a centre
/// and size because that is how a level is naturally read: "floor from x=0 to
/// x=14, surface at y=7.5".
class Slab {
  const Slab({required this.left, required this.right, required this.top});

  final double left;
  final double right;
  final double top;

  double get width => right - left;
}

/// One silhouette standing in the fog. See [GameConfig.scenery].
class SceneryProp {
  const SceneryProp(
    this.image, {
    required this.x,
    required this.y,
    required this.height,
    required this.depth,
    this.hangs = false,
  });

  /// Base name of the art in `assets/images/props/`, without extension. Props
  /// drawn deep in the fog use the `_soft` variant automatically.
  final String image;

  /// World x of the prop's centre, in metres.
  final double x;

  /// World y of the prop's base — the ground it stands on — or, when [hangs]
  /// is set, of its top.
  final double y;

  /// Drawn height in metres.
  final double height;

  /// 0 just behind the player, 1 at the horizon.
  final double depth;

  /// Hang from [y] instead of standing on it, for ladders and ropes.
  final bool hangs;
}
