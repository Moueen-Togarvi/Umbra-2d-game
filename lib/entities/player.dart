import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../input/player_intent.dart';

/// The player character: a small silhouetted figure driven by a Box2D body.
///
/// The physics body is still a plain box — that is what makes movement
/// predictable — and the figure is drawn *inside* it, in body-local metres,
/// with limbs posed from the body's velocity. There is no sprite sheet: a
/// silhouette is a handful of strokes, and posing them in code means the walk
/// cycle speeds up and slows down with the player instead of sliding.
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
      super(paint: Paint()..color = Palette.silhouette, renderBody: false);

  final PlayerIntent _intent;
  final Vector2 _spawnPosition;

  // --- Animation state --------------------------------------------------------
  // All of this is presentation. Nothing in the physics reads it.

  /// Which way the figure faces: +1 right, -1 left. Remembered across frames
  /// so standing still keeps the last direction.
  double _facing = 1;

  /// Progress through the walk cycle, in radians. Advanced by distance
  /// travelled rather than time, so the feet never slide.
  double _walkPhase = 0;

  /// How much of the walk pose to show, 0..1. Eases in and out so a step that
  /// starts and stops does not snap the limbs.
  double _walkWeight = 0;

  /// How much of the airborne pose to show, 0..1.
  double _airWeight = 0;

  /// Vertical velocity mapped to -1 (rising) .. +1 (falling), smoothed.
  double _fallLean = 0;

  double _time = 0;
  double _nextBlinkAt = 2.5;
  double _blinkRemaining = 0;

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

  // --- Movement state ---------------------------------------------------------

  /// Seconds since the feet last touched ground. Drives coyote time.
  double _timeSinceGrounded = 0;

  /// Seconds since jump was last pressed. Drives the jump buffer.
  double _timeSinceJumpPressed = double.infinity;

  @override
  void update(double dt) {
    super.update(dt);

    final Vector2 velocity = body.linearVelocity;
    final bool grounded = isOnGround;

    _timeSinceGrounded = grounded ? 0 : _timeSinceGrounded + dt;
    if (_intent.consumeJumpRequest()) {
      _timeSinceJumpPressed = 0;
    } else {
      _timeSinceJumpPressed += dt;
    }

    // --- Horizontal movement --------------------------------------------------
    // The horizontal velocity is driven straight at a target rather than by
    // applying a force, because forces give a character that winds up slowly
    // and slides on stopping. But it is not *snapped* to the target either:
    // it ramps up over a few frames so a run starts with a push-off, and it
    // ramps slower in the air so a jump can be steered but not reversed. On
    // the ground, letting go stops instantly — that is what feels planted.
    //
    // The trade-off is worth naming: because this *sets* the value, the
    // player wins every horizontal argument with the physics world. Pushing a
    // heavy crate later will revisit this.
    final double target =
        _intent.horizontalAxis * GameConfig.moveSpeedMetersPerSecond;
    final double newX;
    if (grounded && target == 0) {
      newX = 0;
    } else {
      final double accel = grounded
          ? GameConfig.groundAcceleration
          : GameConfig.airAcceleration;
      newX = _approach(velocity.x, target, accel * dt);
    }

    // --- Heavier fall -----------------------------------------------------------
    // Gravity is a property of the world, so the extra pull on the way down
    // is applied as a force on this body alone. Only while actually falling:
    // at rest on the floor there is no downward velocity to speak of.
    if (!grounded && velocity.y > 0.05) {
      body.applyForce(
        Vector2(
          0,
          body.mass *
              GameConfig.gravityMetersPerSecondSquared *
              (GameConfig.fallGravityMultiplier - 1),
        ),
      );
    }

    // Vertical velocity is otherwise left alone — that is gravity's business,
    // and handing it back untouched is what keeps falling and jumping physical.
    body.linearVelocity = Vector2(newX, velocity.y);

    // --- Jumping ----------------------------------------------------------------
    // A jump happens when a recent press meets recent ground: the press may
    // be up to [jumpBufferSeconds] old, and the ground up to
    // [coyoteTimeSeconds] gone. Both timers are spent on use so neither can
    // pay for a second jump.
    final bool pressedRecently =
        _timeSinceJumpPressed <= GameConfig.jumpBufferSeconds;
    final bool groundedRecently =
        _timeSinceGrounded <= GameConfig.coyoteTimeSeconds;
    if (pressedRecently && groundedRecently && velocity.y >= -0.01) {
      _jump();
      _timeSinceJumpPressed = double.infinity;
      _timeSinceGrounded = double.infinity;
    }

    _animate(dt, newX, velocity.y, grounded);
  }

  /// Moves the presentation state on by one frame. Reads velocity, never
  /// writes it.
  void _animate(
    double dt,
    double horizontalSpeed,
    double verticalSpeed,
    bool grounded,
  ) {
    _time += dt;

    if (_intent.horizontalAxis != 0) {
      _facing = _intent.horizontalAxis.sign;
    }

    final bool walking = grounded && horizontalSpeed.abs() > 0.3;
    if (walking) {
      // One full stride per metre or so — short legs, quick steps.
      _walkPhase += horizontalSpeed.abs() * dt * (2 * math.pi / 1.0);
    }
    _walkWeight = _approach(_walkWeight, walking ? 1 : 0, dt * 12);
    _airWeight = _approach(_airWeight, grounded ? 0 : 1, dt * 10);
    final double leanTarget = (verticalSpeed / 7.0).clamp(-1.0, 1.0);
    _fallLean = _approach(_fallLean, leanTarget, dt * 6);

    // Blink every few seconds, for a tenth of one.
    if (_blinkRemaining > 0) {
      _blinkRemaining -= dt;
    } else if (_time >= _nextBlinkAt) {
      _blinkRemaining = 0.11;
      _nextBlinkAt = _time + 2.2 + (_time * 7.3) % 3.1;
    }
  }

  static double _approach(double value, double target, double step) {
    if ((target - value).abs() <= step) return target;
    return value + step * (target - value).sign;
  }

  /// Launches the player upwards fast enough to reach [GameConfig.jumpApexMeters].
  void _jump() {
    // Setting the velocity rather than applying an impulse is deliberate: it
    // makes the jump height independent of the player's mass, so tuning the
    // character's weight later does not silently retune the jump.
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

  // ---------------------------------------------------------------------------
  // Drawing
  // ---------------------------------------------------------------------------
  //
  // Everything below is in body-local metres: the origin is the centre of the
  // physics box, y points down. The figure is a small child — a big round
  // head on a short body — the proportions that make the world look vast.
  // The body is 1.3 m tall, so the crown of the head is at y = -0.65 and the
  // soles at y = +0.65.

  static const double _headRadius = 0.175;
  static const double _headY = -0.46;
  static const double _shoulderY = -0.24;
  static const double _hipY = 0.06;
  static const double _upperArm = 0.21;
  static const double _foreArm = 0.19;
  static const double _thigh = 0.30;
  static const double _shin = 0.29;

  final Paint _limbPaint = Paint()
    ..color = Palette.silhouette
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _eyePaint = Paint()..color = Palette.eyes;
  final Paint _glowPaint = Paint()..color = Palette.eyeGlow;

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.scale(_facing, 1);

    // A little bob while running, and a breath while standing.
    final double bob =
        _walkWeight * math.sin(_walkPhase * 2).abs() * 0.03 +
        (1 - _walkWeight) * math.sin(_time * 1.6) * 0.006;
    canvas.translate(0, -bob);

    // Lean into a run; tip slightly forward on the way down from a jump.
    final double lean = _walkWeight * 0.10 + _airWeight * 0.10 * _fallLean;
    canvas.rotate(lean);

    _drawLegs(canvas);
    _drawTorso(canvas);
    _drawArms(canvas);
    _drawHead(canvas);

    canvas.restore();
  }

  void _drawTorso(Canvas canvas) {
    // A small, slightly tapered body; wider at the shoulders. Rounded so it
    // reads as a child in a shirt rather than as a block.
    final Path torso = Path()
      ..moveTo(-0.115, _shoulderY)
      ..quadraticBezierTo(0.0, _shoulderY - 0.06, 0.115, _shoulderY)
      ..lineTo(0.095, _hipY + 0.05)
      ..quadraticBezierTo(0.0, _hipY + 0.11, -0.095, _hipY + 0.05)
      ..close();
    canvas.drawPath(torso, paint);
    // Neck: short and thick, so the head sits *on* the body.
    _limbPaint.strokeWidth = 0.09;
    canvas.drawLine(
      Offset(0, _shoulderY + 0.02),
      Offset(0.005, _headY + _headRadius * 0.55),
      _limbPaint,
    );
  }

  void _drawHead(Canvas canvas) {
    final Offset centre = Offset(0.015, _headY);
    canvas.drawCircle(centre, _headRadius, paint);

    // Hair: a soft tousled cap on the crown and back, not spikes. Two ovals
    // do it: one over the top, one hanging over the back of the neck.
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centre.dx - 0.03, centre.dy - _headRadius * 0.55),
        width: _headRadius * 2.15,
        height: _headRadius * 1.35,
      ),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(centre.dx - _headRadius * 0.75, centre.dy + 0.02),
        width: _headRadius * 0.9,
        height: _headRadius * 1.7,
      ),
      paint,
    );

    // The eyes. Small, white, and the brightest thing in the scene, so the
    // player is never lost against a black foreground. They look the way the
    // figure faces, so they sit forward of the head's centre.
    final double open = _blinkRemaining > 0 ? 0.15 : 1.0;
    for (final dx in const [0.035, 0.105]) {
      final Offset eye = Offset(centre.dx + dx, centre.dy + 0.005);
      canvas.drawCircle(eye, 0.055, _glowPaint);
      canvas.save();
      canvas.translate(eye.dx, eye.dy);
      canvas.scale(1, open);
      canvas.drawCircle(Offset.zero, 0.021, _eyePaint);
      canvas.restore();
    }
  }

  void _drawArms(Canvas canvas) {
    _limbPaint.strokeWidth = 0.065;
    for (final side in const [-1.0, 1.0]) {
      // Angles are measured from straight down; positive swings forward.
      // Arms swing opposite to the leg on the same side.
      final double swing = math.sin(_walkPhase + (side > 0 ? math.pi : 0));
      double upper = 0.08 + _walkWeight * swing * 0.45;
      double elbow = 0.20 + _walkWeight * 0.35 * (0.5 + 0.5 * swing);
      // In the air the arms drift back and up a little, more on the way down.
      upper = _mix(upper, -0.35 - _fallLean * 0.45 + side * 0.1, _airWeight);
      elbow = _mix(elbow, 0.30, _airWeight);

      final Offset shoulder = Offset(0.09 * side, _shoulderY + 0.03);
      final Offset elbowPt = shoulder + _polar(math.pi / 2 - upper, _upperArm);
      final Offset hand =
          elbowPt + _polar(math.pi / 2 - upper - elbow, _foreArm);
      canvas.drawLine(shoulder, elbowPt, _limbPaint);
      canvas.drawLine(elbowPt, hand, _limbPaint);
    }
  }

  void _drawLegs(Canvas canvas) {
    _limbPaint.strokeWidth = 0.085;
    for (final side in const [-1.0, 1.0]) {
      final double swing = math.sin(_walkPhase + (side > 0 ? 0 : math.pi));
      // Standing: legs straight down, slightly apart. Running: thighs swing,
      // and the knee folds as the leg comes through.
      double thigh = 0.04 * side + _walkWeight * swing * 0.55;
      final double lift =
          0.5 + 0.5 * math.cos(_walkPhase + (side > 0 ? 0 : math.pi));
      double knee = _walkWeight * 0.8 * lift * (swing > 0 ? 1 : 0.2);
      // Airborne: legs trail a little, one ahead of the other, and straighten
      // out into the fall so the landing is feet-first.
      final double tuck = side > 0 ? 0.45 : -0.25;
      thigh = _mix(thigh, tuck - _fallLean * 0.25, _airWeight);
      final double airKnee =
          (side > 0 ? 0.9 : 0.3) * (1 - _fallLean.clamp(0.0, 1.0) * 0.7);
      knee = _mix(knee, airKnee, _airWeight);

      final Offset hip = Offset(0.045 * side, _hipY + 0.02);
      final Offset kneePt = hip + _polar(math.pi / 2 - thigh, _thigh);
      final Offset foot = kneePt + _polar(math.pi / 2 - thigh + knee, _shin);
      canvas.drawLine(hip, kneePt, _limbPaint);
      canvas.drawLine(kneePt, foot, _limbPaint);
      // A foot.
      canvas.drawLine(foot, foot + const Offset(0.075, 0.0), _limbPaint);
    }
  }

  static Offset _polar(double angle, double length) =>
      Offset(math.cos(angle) * length, math.sin(angle) * length);

  static double _mix(double a, double b, double t) => a + (b - a) * t;
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
