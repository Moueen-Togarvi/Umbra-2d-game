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
/// 1.3 m tall, with a child's proportions. Everything else follows from that.
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
  static const double levelWidth = 96.0;

  /// Total height of the level. Ground slabs extend all the way down to this,
  /// so there is never a gap of fog visible *under* the floor.
  static const double levelHeight = 12.0;

  /// How much of the world the camera frames, in metres. Flame fits this box
  /// inside the screen, so a wider phone simply sees more of the level to the
  /// sides. The 9.2 m height keeps the boy readable on a phone.
  static const double cameraVisibleWidth = 18.67;
  static const double cameraVisibleHeight = 9.2;

  /// How far above the player's centre the camera aims. Positive is *up*.
  /// Looking up shows more sky and canopy and less dead black ground.
  static const double cameraLookUp = 2.05;

  /// How far ahead of the player, in the direction of travel, the camera
  /// leads at full running speed. Puts the running boy at about 40% of the
  /// screen, with the space he is running into in front of him.
  static const double cameraLookAhead = 1.8;

  /// Time for the horizontal follow to close most of the gap, in seconds. A
  /// critically damped spring: it eases in and out instead of snapping.
  static const double cameraHorizontalSmoothSeconds = 0.38;

  /// How quickly the camera catches up vertically, per second.
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
  /// Real Earth gravity is 9.81. Platformers run heavier than that, because
  /// real gravity makes a jump arc feel slow and floaty at the scale of a
  /// screen. 18, with a slightly heavier fall, gives the light, long LIMBO
  /// hop: about 0.64 s in the air and a 2 m running jump.
  ///
  /// Note the sign: Flame's y-axis points **down**, so positive y is downward.
  /// (Raw Box2D uses y-up and would write this as -22. flame_forge2d flips the
  /// convention for you, which is why its default gravity is `(0, 10)` and not
  /// `(0, -10)`.)
  static const double gravityMetersPerSecondSquared = 18.0;

  /// Gravity as a vector. A getter rather than a constant because [Vector2] is
  /// mutable and each caller should get its own instance.
  static Vector2 get gravity => Vector2(0, gravityMetersPerSecondSquared);

  // ---------------------------------------------------------------------------
  // Player
  // ---------------------------------------------------------------------------

  /// Player collision width in metres. Narrower than the drawn figure's
  /// reach, so a swinging arm never snags on a wall.
  static const double playerWidth = 0.42;

  /// Player height in metres. The figure is a child, small against the world
  /// — that is most of what makes the world feel vast.
  static const double playerHeight = 1.3;

  /// Player mass in kilograms.
  static const double playerMassKilograms = 40.0;

  /// Running speed in metres per second. Like LIMBO's boy, Umbra's child has
  /// one gait: a light run. There is no walk button.
  static const double moveSpeedMetersPerSecond = 3.2;

  static const double maximumSlopeRadians = math.pi * 0.30;

  /// Crouched, he creeps at this speed, metres a second.
  static const double crouchSpeedMetersPerSecond = 0.85;

  /// Crouched or sitting, the capsule is this much of his full height,
  /// shortened from the top so his feet stay where they are: low enough to
  /// get under a low beam, tall enough to hold the drawn head.
  static const double lowHeightRatio = 0.72;

  /// Held still this long while low, he sits down; before that he stays
  /// bent over, ready to creep on.
  static const double sitAfterSeconds = 0.7;

  /// LIMBO's jump leaves the ground almost at once: a single frame of bent
  /// knees, not a wind-up.
  static const double jumpAnticipationSeconds = 0.017;
  static const double pushForceNewtons = 500;

  /// Crates are moved at a walk, not a run: a light one pushed briskly, a
  /// heavy one slowly, and pulling slower still, metres a second. Between
  /// the light (8 kg) and heavy (35 kg) crate the speed is in proportion.
  static const double pushSpeedLight = 1.9, pushSpeedHeavy = 1.1;
  static const double pullSpeedLight = 1.0, pullSpeedHeavy = 0.75;
  static const double lightCrateKg = 8, heavyCrateKg = 35;

  /// Pushing, the arms brace against the crate: a shape this long grows on
  /// the front of the body, so he holds it at arm's length, not with his
  /// chest. It collides with props only.
  static const double pushBraceMeters = 0.22;

  /// Straining against a heavy crate he leans in further, so the brace
  /// reaches this much further out to keep the arms straight.
  static const double pushBraceStrainMeters = 0.10;
  static const double pushBraceSeconds = 0.2;
  static const double pullForceNewtons = 220;
  static const double swingAcceleration = 4;

  /// Upward speed added when kicking off a rope with jump.
  static const double ropeJumpSpeed = 3.6;

  /// Climbing a rope, hand over hand: up is slower than sliding down. At
  /// the bottom of the rope, holding down this long lets go.
  static const double ropeClimbUpSpeed = 0.9;
  static const double ropeClimbDownSpeed = 1.4;
  static const double ropeLetGoSeconds = 0.3;

  /// A landing faster than this, or a hit from anything this fast, kills: the
  /// body goes limp. About a 4.5 m drop, three and a half times his height.
  static const double deathImpactSpeed = 14;

  /// A landing faster than this (about a 1.5 m drop) folds the knees deep and
  /// holds the boy for a moment before he runs on.
  static const double hardLandingSpeed = 8.2;
  static const double hardLandingSeconds = 0.32;

  /// Ground steeper than this starts a slide down it on his feet; it ends
  /// when the ground is gentler than [slideStopRadians].
  static const double slideStartRadians = 32 * math.pi / 180;
  static const double slideStopRadians = 28 * math.pi / 180;

  /// Sliding: friction along the slope, top speed along it, and how much
  /// steering nudges it.
  static const double slideFriction = 0.15;
  static const double slideMaxSpeed = 7;
  static const double slideSteerAcceleration = 2;

  /// After a slide the speed carries on, braking only gently, this long.
  static const double slideCarrySeconds = 0.6;
  static const double slideCarryDeceleration = 5;

  /// Landings faster than this shake the camera, by up to
  /// [cameraShakeMeters], dying away over [cameraShakeSeconds].
  static const double cameraShakeImpact = 7;
  static const double cameraShakeMeters = 0.12;
  static const double cameraShakeSeconds = 0.5;

  /// Stopped with his centre past an edge, he steps back onto the ground
  /// this fast, metres a second.
  static const double edgeStepBackSpeed = 0.7;

  /// Stopping this close to an edge he faces (metres from his centre), he
  /// balances for [teeterSeconds].
  static const double teeterReach = 0.22;
  static const double teeterSeconds = 1.0;

  /// Climbing up onto a ledge — pull up, knee on top, stand — takes this
  /// long.
  static const double climbSeconds = 1.0;

  /// Turning round: the body passes through a front view in this long.
  static const double turnSeconds = 0.16;

  /// Idle life: the first idle action after standing still this long, then
  /// one every few seconds.
  static const double idleFirstSeconds = 2.5;
  static const double idleMinGapSeconds = 3;
  static const double idleMaxGapSeconds = 6;

  /// Used by the debug knockdown (K), which still gets back up.
  static const double recoveryBlendSeconds = 0.45;

  /// LIMBO's death beat: how long the limp body lies there before the picture
  /// fades, the fade itself, a moment of black, and the fade back in at the
  /// checkpoint.
  static const double deathLingerSeconds = 1.3;
  static const double deathFadeOutSeconds = 0.55;
  static const double deathBlackSeconds = 0.25;
  static const double deathFadeInSeconds = 0.8;

  /// How quickly the player reaches [moveSpeedMetersPerSecond] on the
  /// ground, in m/s². Reaches full speed in about 0.18 seconds, giving the
  /// first step a visible push-off. Braking uses a stronger rate below.
  static const double groundAcceleration = 18.0;

  /// Braking is stronger than acceleration, but still takes a few frames.
  static const double groundDeceleration = 26.0;

  /// Acceleration while airborne. Lower than on the ground: you can steer a
  /// jump, but not reverse it outright.
  static const double airAcceleration = 3.5;

  /// Extra gravity on the way *down*, as a multiple of [gravity]. Rising at
  /// 1x and falling at 1.2x is the classic platformer trick: the jump still
  /// reaches its apex, but the fall is a little quicker and heavier.
  static const double fallGravityMultiplier = 1.2;

  /// How long after walking off an edge a jump is still allowed, in seconds.
  /// Without this, pressing jump on the last pixel of a ledge — which is
  /// exactly where people press it — fails, and the game feels unfair.
  static const double coyoteTimeSeconds = 0.12;

  /// How long before landing a jump press is remembered, in seconds. Pressing
  /// slightly early then lands and jumps in one motion instead of being lost.
  static const double jumpBufferSeconds = 0.12;

  /// How high the player's jump peaks, in metres, measured from the take-off
  /// point. Like LIMBO's, the jump is always this height: holding or
  /// releasing the button early does not change it.
  ///
  /// This is the number to tune when the jump feels wrong. The take-off
  /// velocity is derived from it rather than guessed — see [jumpTakeoffSpeed].
  static const double jumpApexMeters = 1.0;

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
  // Level layout (metres, origin at the level's top-left, y pointing down)
  // ---------------------------------------------------------------------------

  /// The ground, as a few control points per unbroken stretch, x then y in
  /// metres. [Terrain] draws a smooth curve through each stretch; the gap
  /// between two stretches is a pit with spikes at the bottom.
  ///
  /// The first stretch starts flat at [floorSurfaceY] — the physics tests
  /// spawn there and expect level ground — then the land rolls: up to a
  /// crest, down into the mist, up again into the forest.
  ///
  /// Pits are about 1.4 m wide: at [moveSpeedMetersPerSecond] and
  /// [jumpApexMeters] a running jump carries roughly 2 m, so they are
  /// clearable with a little to spare, but only with a jump.
  static const List<List<double>> terrainProfile = [
    // 01 Flooded forest. Keep the spawn and first gap fixed for the physics
    // checks, then let each stretch lead into the next environment.
    [0, floorSurfaceY, 4, floorSurfaceY, 8, 7.3, 11.5, 6.7, gapStartX, 6.6],
    // 02 Broken bridge ravine.
    [gapEndX, 7.0, 19, 7.3, 22.5, 7.1, 26, 6.4, 30, 6.0],
    // 03 Quarry: a steep bank (up to 46°) that he slides down on his feet.
    [31.4, 6.5, 34, 5.65, 35.2, 5.35, 37.2, 6.75, 39.4, 6.6, 43, 5.9, 46, 6.0],
    // 04 Root thicket.
    [47.4, 6.5, 51, 6.3, 55, 6.8, 59, 6.1, 62, 6.2],
    // 05 Marsh and waterwheel.
    [63.4, 6.8, 67, 7.0, 71, 6.7, 75, 7.1, 78, 6.8],
    // 06 Storm coast.
    [79.4, 7.1, 83, 7.0, 87, 6.5, 91, 6.8, levelWidth, 6.6],
  ];

  /// Fallen logs lying on the ground across the path, by their x span; each
  /// sits on the hill under it. Half a metre tall, so they block walking (a
  /// capsule does not step over things) but are cleared by the smallest hop.
  static const List<List<double>> logs = [
    [19, 21],
    [38.6, 40.0],
    [53, 55],
    [68, 69.5],
    [88, 89.5],
  ];

  /// Boulders half sunk in the ground across the path, by their x span;
  /// like the logs, hopped over.
  static const List<List<double>> rocks = [
    [57.6, 58.5],
    [84.0, 84.9],
  ];

  /// How high a boulder stands out of the ground.
  static const double rockHeight = 0.42;

  /// Thickness of a ledge.
  static const double ledgeThickness = 0.5;

  /// How deep below the surrounding ground a pit's stakes stand. Shallow
  /// enough that the camera still sees what happens at the bottom.
  static const double pitDepth = 1.6;

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
  static const double controlButtonDiameterPx = 72.0;

  /// Gap between the screen edge and the nearest button.
  static const double controlEdgeMarginPx = 24.0;

  /// Gap between the two walk buttons.
  static const double controlGapPx = 16.0;

  /// Size of the arrow glyph inside a button, as a fraction of its radius.
  static const double controlGlyphScale = 0.46;
}
