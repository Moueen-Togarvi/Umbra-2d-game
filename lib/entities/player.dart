import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../input/player_intent.dart';

/// The player character: a black rectangle driven by a Box2D body.
///
/// ## What changed by moving to a physics engine
///
/// A hand-rolled platformer keeps a `velocity` field, adds gravity to it every
/// frame, moves the rectangle, and then runs its own overlap tests to push the
/// rectangle back out of the floor. That works, and it is how most first
/// prototypes start, but everything it does is bespoke: it only knows about the
/// shapes you taught it about, and things like resting stably on a slope,
/// stacking, or being pushed by another object have to be invented from
/// scratch.
///
/// With Box2D we stop *simulating* and start *describing*. We declare that the
/// player is a body with a shape, a mass and a friction coefficient, and the
/// solver works out where everything ends up each step. That is what makes
/// crates, ropes and buoyancy possible later — they are all the same solver
/// doing the same job.
class Player extends BodyComponent {
  /// Note the `this._intent` parameter: Dart lets a private field be filled by
  /// an initialising formal, and callers pass it under its public name, so this
  /// is constructed as `Player(intent: ..., spawnPosition: ...)`.
  Player({required this._intent, required Vector2 spawnPosition})
    : _spawnPosition = spawnPosition.clone(),
      super(paint: Paint()..color = Palette.silhouette);

  final PlayerIntent _intent;
  final Vector2 _spawnPosition;

  /// Tracks whether the player's feet are touching anything solid.
  late final GroundSensor _groundSensor = GroundSensor(owner: this);

  /// Whether the player is currently standing on something.
  bool get isOnGround => _groundSensor.isOnGround;

  @override
  Body createBody() {
    // `world` is assigned by BodyComponent just before this runs.
    final Body playerBody = world.createBody(
      BodyDef(
        // Dynamic: the solver moves it, gravity and collisions apply.
        // (Static bodies never move; kinematic bodies move but ignore forces.)
        type: BodyType.dynamic,
        position: _spawnPosition.clone(),

        // Without this the rectangle topples over the instant it lands on a
        // corner. Real platformer characters do not rotate; they are a
        // capsule-on-rails wearing a physics body as a costume.
        fixedRotation: true,

        // Box2D lets resting bodies "sleep" to save time. A sleeping body
        // ignores direct velocity writes until something wakes it, which would
        // make the player unresponsive after standing still. Cheap to disable
        // for one body.
        enableSleep: false,

        // Identifies this body in contact events. The hazard reads this to
        // find out that it was the player who touched it.
        userData: this,
      ),
    );

    // --- The body shape: the visible silhouette -------------------------------
    // Note the half-extents: Box2D describes boxes from their centre outwards,
    // so a 0.8 x 1.6 m player is `box(0.4, 0.8)`.
    playerBody.createShape(
      Polygon.box(GameConfig.playerWidth / 2, GameConfig.playerHeight / 2),
      ShapeDef(
        density: GameConfig.playerDensity,
        material: SurfaceMaterial(
          // Zero friction on the player's own sides. Because we drive
          // horizontal movement by writing velocity directly, friction here
          // would only ever work against us: it is what makes a character
          // stick to a wall while holding the direction key mid-air.
          // The *floor* still has friction, which is what matters.
          friction: 0,
        ),
        // Sensors only generate events for shapes that have opted in, on both
        // sides. Without this line the hazard's sensor would never see us and
        // respawn would silently stop working.
        enableSensorEvents: true,
      ),
    );

    // --- The foot sensor: "am I standing on something?" -----------------------
    // A thin, slightly narrower box straddling the soles. It is a sensor, so it
    // reports overlaps but never pushes anything.
    //
    // Why not just check "is my vertical velocity zero"? Because that is also
    // true at the apex of a jump, and while scraping along a ceiling. A sensor
    // asks the question we actually mean.
    playerBody.createShape(
      Polygon.offsetBox(
        GameConfig.playerWidth / 2 * GameConfig.footSensorWidthFactor,
        GameConfig.footSensorHalfHeight,
        center: Vector2(0, GameConfig.playerHeight / 2),
      ),
      ShapeDef(
        isSensor: true,
        enableSensorEvents: true,
        // A sensor should not add weight to the player.
        density: 0,
        userData: _groundSensor,
      ),
    );

    return playerBody;
  }

  @override
  void update(double dt) {
    super.update(dt);

    final Vector2 velocity = body.linearVelocity;

    // --- Horizontal movement --------------------------------------------------
    // We overwrite the horizontal velocity outright rather than applying a
    // force. Forces are more physically honest, but they give a character that
    // accelerates slowly and slides on stopping, which reads as unresponsive.
    //
    // The trade-off is real and worth naming: because we *set* this value, the
    // player currently wins every horizontal argument with the physics world.
    // Push a heavy crate in Step 2 and the player would shove it like it were
    // weightless. Step 2 revisits this line.
    final double targetHorizontalSpeed =
        _intent.horizontalAxis * GameConfig.moveSpeedMetersPerSecond;

    // Vertical velocity is left completely alone — that is gravity's business,
    // and handing it back untouched is what keeps falling and jumping physical.
    body.linearVelocity = Vector2(targetHorizontalSpeed, velocity.y);

    // --- Jumping --------------------------------------------------------------
    // The request is consumed whether or not we can act on it, so a press made
    // in mid-air is discarded rather than saved up and spent on landing.
    final bool wantsToJump = _intent.consumeJumpRequest();
    if (wantsToJump && isOnGround) {
      _jump();
    }
  }

  /// Launches the player upwards fast enough to reach [GameConfig.jumpApexMeters].
  void _jump() {
    // Setting the velocity rather than applying an impulse is deliberate: it
    // makes the jump height independent of the player's mass, so tuning the
    // character's weight later does not silently retune the jump.
    //
    // The impulse form would be `applyLinearImpulse(Vector2(0, -mass * speed))`
    // after zeroing the vertical velocity — same result, more moving parts.
    //
    // Negative y is upwards: Flame's y-axis points down the screen.
    body.linearVelocity = Vector2(
      body.linearVelocity.x,
      -GameConfig.jumpTakeoffSpeed,
    );
  }

  /// Instantly moves the player to [position] with no leftover motion.
  ///
  /// Used by the checkpoint system. Zeroing both velocities is the part that is
  /// easy to forget: without it the player arrives at the checkpoint still
  /// carrying the speed it had when it died, and immediately drifts off it.
  void teleportTo(Vector2 position) {
    body.setTransform(position, const Rot.identity());
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0;
    // Deliberately *not* resetting the ground sensor here. See GroundSensor.
  }

  @override
  void renderShape(Canvas canvas, Shape shape) {
    // BodyComponent draws every shape on the body, which would render the foot
    // sensor as a visible black bar under the player's feet. Sensors are
    // invisible machinery, so skip them.
    if (shape.isSensor) {
      return;
    }
    super.renderShape(canvas, shape);
  }
}

/// Counts how many solid things the player's feet are currently touching.
///
/// A counter rather than a boolean, because the feet can touch two things at
/// once — the seam between two floor slabs, or a crate and the floor. If this
/// were a boolean, stepping off one of the two would wrongly report the player
/// as airborne.
class GroundSensor with ContactCallbacks {
  GroundSensor({required this.owner});

  /// The player this sensor belongs to, used to filter out self-contacts.
  final Player owner;

  /// Note there is no `reset()`. An earlier version cleared this on respawn,
  /// which looked defensive and was actually the source of a bug: the
  /// dispatcher delivers *all* begin events before *all* end events, so a stale
  /// end arriving in the same batch as the respawn's fresh begin cancelled it
  /// out and left the player permanently unable to jump. Box2D pairs every
  /// begin with an end, including across a teleport, so the count balances
  /// itself if left alone.
  int _contactCount = 0;

  /// True while the feet are touching at least one solid thing.
  bool get isOnGround => _contactCount > 0;

  @override
  void beginContact(Object other, Contact contact) {
    if (!_isStandableSurface(other, contact)) {
      return;
    }
    _contactCount++;
  }

  @override
  void endContact(Object other, Contact contact) {
    if (!_isStandableSurface(other, contact)) {
      return;
    }
    // Guard against underflow. Box2D pairs every begin with an end, so this
    // should not trigger, but a stuck-airborne player is a miserable bug to
    // chase and the guard is one line.
    if (_contactCount > 0) {
      _contactCount--;
    }
  }

  /// Whether this contact is something the player can actually stand on.
  ///
  /// Two separate filters, both of which were found the hard way:
  ///
  /// 1. **Ignore our own player.** flame_forge2d gathers the userData of both
  ///    bodies *and* both shapes in a contact, then notifies each
  ///    [ContactCallbacks] once per other participant. This sensor lives on the
  ///    player's own body, so every ground contact notifies us twice: once
  ///    about the ground, once about the player who owns us. Without this,
  ///    every increment is doubled.
  ///
  /// 2. **Ignore other sensors.** Sensors in Box2D v3 detect each other, so the
  ///    hazard's trigger volume shows up here looking exactly like a floor.
  ///    A trigger volume is not something you can stand on. This matters more
  ///    with every step: the water zone in Step 4 is a sensor too, and without
  ///    this filter the player would count as standing on solid ground the
  ///    entire time they were swimming.
  ///
  /// For a sensor event the engine names one shape the sensor and the other the
  /// visitor. If *we* are the sensor, the visitor is the thing we landed on and
  /// it must be solid. If we are the visitor, then the other shape is by
  /// definition a sensor, and we want nothing to do with it.
  bool _isStandableSurface(Object other, Contact contact) {
    if (identical(other, owner)) {
      return false;
    }
    if (contact.isSensorEvent) {
      // An end event can arrive after a shape has been destroyed, in which case
      // there is nothing left to inspect.
      if (!contact.isValid) {
        return false;
      }
      if (contact.visitor.isSensor) {
        return false;
      }
    }
    return true;
  }
}
