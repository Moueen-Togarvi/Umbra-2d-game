import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';

import '../character/character_interactions.dart';
import '../character/character_ragdoll.dart';
import '../character/character_rig.dart' show Gait;
import '../character/character_state.dart';
import '../character/foot_placement.dart';
import '../character/ground_probe.dart';
import '../character/limb_physics.dart';
import '../config/game_config.dart';
import '../config/palette.dart';
import '../input/player_intent.dart';
import '../physics/collision_layers.dart';
import '../render/character_silhouette.dart';
import '../story/figures.dart' show Calm;

/// What he does with himself while standing about.
enum IdleAction { none, lookUp, lookBack, shiftFeet }

/// One stable capsule owns locomotion. Constraint interactions may take over;
/// ragdoll explicitly disables the capsule until safe recovery has completed.
///
/// The controller is tuned to LIMBO's boy: one running speed, a fixed-height
/// jump, ledges and ropes caught by themselves, and a body that simply goes
/// limp when it falls too far or is hit too hard. Death is permanent until
/// the [DeathSequence] fades out and puts him back at the checkpoint.
class Player extends BodyComponent {
  Player({required this._intent, required Vector2 spawnPosition})
    : _spawnPosition = spawnPosition.clone(),
      _lastPosition = spawnPosition.clone(),
      super(paint: Paint()..color = Palette.silhouette, renderBody: false);

  final PlayerIntent _intent;
  final Vector2 _spawnPosition;
  final Vector2 _lastPosition;
  final FootPlacement _feet = FootPlacement();
  final LimbPhysics _limbs = LimbPhysics(height: GameConfig.playerHeight);

  /// The pose last solved and run through the leg physics, in world metres.
  /// Drawn as is, and handed to the ragdoll when he goes limp.
  CharacterRigPose? _drawnPose;

  /// The pelvis rides on a spring: landings and footstrikes push it down,
  /// the legs fold under it, and it springs back. Metres, positive down.
  double _pelvisDrop = 0;
  double _pelvisSpeed = 0;

  /// How low the hips must sit to reach the planted feet, followed on a
  /// critically damped spring so a new foothold is sunk into, not dropped
  /// to (fractions of height; NaN until first worked out).
  double _hipFloor = double.nan;
  double _hipFloorSpeed = 0;
  List<bool> _wasPlanted = const [true, true];
  final CharacterSilhouette _figure = CharacterSilhouette(
    height: GameConfig.playerHeight,
  );
  final Paint _contactShadow = Paint();
  CharacterRagdoll? _ragdoll;
  CharacterRigPose? _recoveryPose;
  double _recoveryTime = 0;
  late CharacterInteractions interactions;

  CharacterState state = CharacterState.idle;
  bool debugEnabled = false;

  /// Not drawn: inside a house, before a scene brings him out.
  bool hidden = false;

  /// Whether what he stands on is free to move (a raft, a plank).
  bool _onLoose = false, _onProp = false;

  /// How deep his feet are in water (set by the water he is in): he wades
  /// slowly through it.
  double waterDepth = 0;
  final Map<Object, double> _waterDepths = {};
  void reportWaterDepth(Object source, double depth) {
    if (depth > 0) {
      _waterDepths[source] = depth;
    } else {
      _waterDepths.remove(source);
    }
    waterDepth = _waterDepths.values.fold(0.0, math.max);
  }

  /// A scene has him look back over his shoulder, or up, and hold it.
  bool forceLookBack = false;
  bool forceLookUp = false;
  bool _dead = false;
  bool _grounded = false;

  /// Down low: crouched or sitting, on a capsule shortened from the top.
  bool _low = false;
  Shape? _capsule;
  double _lowStill = 0;

  /// How far into the crouch and the sit he is drawn, each following its
  /// goal on a critically damped spring so he settles without a bob.
  final Calm _crouch = Calm(0, hertz: 2.2), _sit = Calm(0, hertz: 1.3);

  /// How many times he has sat down, so a sound can go with it.
  int sitDowns = 0;

  /// Whether the ground is under his centre, not just under one side of
  /// the capsule; if not, which side has it (+1 ahead in x, −1 behind).
  bool _centreSupported = false;
  double _edgeSide = 0;
  bool _steppingBack = false;

  // Balancing at an edge he has just stopped at.
  double _teeterTime = -1;
  bool _teeterArmed = true;
  double _sinceRunning = double.infinity;
  int _teeters = 0;
  final Vector2 _teeterLip = Vector2.zero();
  double _supportSlope = 0;
  double _supportY = 0;
  Vector2 _supportVelocity = Vector2.zero();
  double _timeSinceGrounded = double.infinity;
  double _timeSinceJumpPressed = double.infinity;
  double _anticipationTime = 0;
  bool _jumping = false;
  int _landings = 0;
  double? _pendingLanding;
  double _lastLandingImpact = 0;
  final Vector2 _lastLandingAt = Vector2.zero();
  bool _sliding = false;
  double _slideCarry = 0;
  double _slideWeight = 0;
  double _facing = 1;

  /// The way the body is drawn facing: cos of a turn angle that sweeps
  /// through a front view (0) in [GameConfig.turnSeconds].
  double _turnAngle = 0;
  double _gaitPhase = 0;
  double _gaitWeight = 0;
  double _airWeight = 0;

  /// The arms go into their airborne pose only on a jump or a real fall,
  /// not for a moment's hop over a bump, and ease in and out of it.
  double _armAirWeight = 0;
  double _airSeconds = 0;

  /// Legs kicking with a rope swing, −1 to 1.
  double _swingKick = 0;
  double _fallLean = 0;
  double _bodyLean = 0;
  double _landing = 0;
  double _hardLanding = 0;

  /// The landing crouches as drawn: they come on over a few frames
  /// instead of in one, so the body and arms sink into a landing rather
  /// than jumping into it.
  double _landingDrawn = 0;
  double _hardLandingDrawn = 0;

  /// The jump's crouch and spring as drawn, eased the same way.
  double _anticipationDrawn = 0;
  double _takeoffDrawn = 0;
  double _hardLandingHold = 0;
  double _takeoff = 0;
  double _pushWeight = 0;
  double _pullWeight = 0;
  double _effort = 0;
  Shape? _brace;
  double _braceBuilt = 0;
  double _braceFacing = 1;
  double _hairSway = 0;
  double _previousVerticalSpeed = 0;
  double _time = 0;
  double _nextBlinkAt = 2.5;
  double _blinkRemaining = 0;
  double _actualSpeed = 0;
  double _gripWeight = 0;

  // Idle life: after standing still a while, now and then he looks up,
  // looks round at the camera, or shifts his feet.
  final math.Random _idleRandom = math.Random(11);
  final List<IdleAction> _idleBag = [];
  IdleAction _idleAction = IdleAction.none;
  IdleAction _lastIdleAction = IdleAction.none;
  double _stillSeconds = 0;
  double _idleActionTime = 0;
  double _nextIdleAt = GameConfig.idleFirstSeconds;
  double _lookUp = 0;
  double _headTurn = 0;

  bool get isOnGround => _grounded;

  /// Crouched or sitting, on the short capsule.
  bool get isLow => _low;

  /// Whether he stands on something that moves (a crate, a plank, a lift)
  /// rather than the ground.
  bool get onProp => _onProp;

  /// Sliding down a steep slope on his feet.
  bool get isSliding => _sliding;

  /// Holding a rope.
  bool get isOnRope => isLoaded && interactions.attachedRope != null;

  /// Balancing at an edge he has just stopped at.
  bool get isTeetering => _teeterTime >= 0;

  /// How far into the balancing pose he is: in over 0.15 s, out over the
  /// last 0.4 s.
  double get _teeterWeight {
    if (_teeterTime < 0) return 0;
    final double t = _teeterTime;
    final double rise = (t / 0.15).clamp(0.0, 1.0);
    final double fall = ((GameConfig.teeterSeconds - t) / 0.4).clamp(0.0, 1.0);
    return _smooth(math.min(rise, fall));
  }

  /// How many times he has started balancing at an edge, and the lip of
  /// the last one, for the earth that crumbles off it.
  int get teeters => _teeters;
  Vector2 get teeterLip => _teeterLip;

  /// Whether the ground is under the middle of him.
  bool get isCentreSupported => _centreSupported;

  /// How many times he has landed, so dust and the camera can react to
  /// each new landing; and the last one's impact speed (m/s) and where his
  /// feet hit the ground.
  int get landings => _landings;
  double get lastLandingImpact => _lastLandingImpact;
  Vector2 get lastLandingAt => _lastLandingAt;
  double get facing => _facing;

  /// The drawn facing: ±1 side-on, passing through 0 (a front view) while
  /// turning round.
  double get visualFacing => math.cos(_turnAngle);
  bool get isRagdoll => _ragdoll != null;

  /// True from the moment the body goes limp until the checkpoint respawn.
  bool get isDead => _dead;

  /// His eyes' colour and glow (white and 1, as they are, until the end).
  set eyeColor(Color value) => _figure.eyeColor = value;
  set eyeGlow(double value) => _figure.eyeGlow = value;

  Vector2 get velocity => _ragdoll?.velocity ?? body.linearVelocity;
  Vector2 get cameraPosition => _ragdoll?.pelvisPosition ?? body.position;
  String get interactionLabel => interactions.mode.name;
  List<Vector2> get rigFootTargets => _feet.targets;

  /// Whether each foot (front, back) is planted rather than swinging.
  List<bool> get rigFeetPlanted => _feet.planted;
  CharacterRigPose get rigPoseWorld =>
      _ragdoll?.pose ??
      _drawnPose ??
      _figure.solve(_pose).translated(body.position);

  /// How far the pelvis spring is compressed, metres.
  double get pelvisDrop => _pelvisDrop;

  /// What he is doing while standing about, if anything.
  IdleAction get idleAction => _idleAction;

  /// Whether a foot is taking a step in place (settling or shifting).
  bool get isSteppingInPlace => _feet.stepping;

  @override
  Body createBody() {
    final playerBody = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: _spawnPosition.clone(),
        fixedRotation: true,
        enableSleep: false,
        isBullet: true,
        userData: this,
      ),
    );
    _capsule = _createCapsule(playerBody);
    return playerBody;
  }

  /// His capsule: full height, or when [_low] shortened from the top, the
  /// soles where they were. The mass stays the same either way.
  Shape _createCapsule(Body target) {
    const radius = GameConfig.playerWidth / 2;
    const halfHeight = GameConfig.playerHeight / 2;
    final double height = _capsuleHeight;
    final double area =
        2 * radius * (height - 2 * radius) + math.pi * radius * radius;
    return target.createShape(
      Capsule(
        center1: Vector2(0, halfHeight - height + radius),
        center2: Vector2(0, halfHeight - radius),
        radius: radius,
      ),
      ShapeDef(
        density: GameConfig.playerMassKilograms / area,
        material: SurfaceMaterial(friction: 0, restitution: 0),
        filter: Filter(
          categoryBits: CollisionLayers.player,
          maskBits: CollisionLayers.all,
        ),
        enableSensorEvents: true,
        enableContactEvents: true,
        enableHitEvents: true,
      ),
    );
  }

  double get _capsuleHeight =>
      GameConfig.playerHeight * (_low ? GameConfig.lowHeightRatio : 1);

  void _setLow(bool low) {
    if (low == _low) return;
    _low = low;
    final Shape? old = _capsule;
    if (old != null && old.isValid) old.destroy();
    _capsule = _createCapsule(body);
  }

  /// Down while sit is held on the ground (sitting still, creeping when
  /// moving); up again when it is let go, if there is room to stand.
  void _updateLow(double dt, bool jumpPressed) {
    final bool want =
        _intent.isSitHeld &&
        !jumpPressed &&
        (_grounded || (_low && _timeSinceGrounded < 0.2)) &&
        (interactions.mode == InteractionMode.none ||
            interactions.mode == InteractionMode.pushing) &&
        !_sliding &&
        waterDepth < 0.25 &&
        _hardLandingHold <= 0;
    if (want != _low) {
      if (want || _standingClear()) {
        _setLow(want);
      } else if (jumpPressed) {
        // No room to stand: no jump either.
        _timeSinceJumpPressed = double.infinity;
      }
    }
    final bool still = _intent.horizontalAxis == 0 && _actualSpeed.abs() < 0.3;
    final double before = _lowStill;
    _lowStill = _low && still ? _lowStill + dt : 0;
    final bool sitting = _lowStill >= GameConfig.sitAfterSeconds;
    if (sitting && before < GameConfig.sitAfterSeconds) sitDowns++;
    _sit.step(sitting ? 1 : 0, dt);
    _crouch.step(_low && !sitting ? 1 : 0, dt);
  }

  /// Whether there is room over him to stand up from low.
  bool _standingClear() {
    final double top = body.position.y - GameConfig.playerHeight / 2;
    final double lowTop =
        body.position.y +
        GameConfig.playerHeight / 2 -
        GameConfig.playerHeight * GameConfig.lowHeightRatio;
    var clear = true;
    for (final x in const [
      -GameConfig.playerWidth * 0.4,
      0.0,
      GameConfig.playerWidth * 0.4,
    ]) {
      world.castRay(
        Vector2(body.position.x + x, lowTop + 0.02),
        Vector2(0, top - lowTop - 0.04),
        (hit) {
          if (hit.shape.body == body || hit.shape.isSensor) return -1;
          clear = false;
          return 0;
        },
        filter: QueryFilter(maskBits: CollisionLayers.solid),
      );
    }
    return clear;
  }

  /// Back to full height at once (a death, a respawn), and the pose with it.
  void _resetLow() {
    _setLow(false);
    _lowStill = 0;
    _crouch.value = 0;
    _sit.value = 0;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    interactions = CharacterInteractions(
      world: world,
      playerBody: body,
      width: GameConfig.playerWidth,
      height: GameConfig.playerHeight,
    );
  }

  RayHit? _supportBelow() {
    RayHit? closest;
    final soleY = body.position.y + GameConfig.playerHeight / 2;
    var centre = false;
    var sides = 0.0;
    for (final offset in const [0.0, -0.10, 0.10]) {
      world.castRay(
        Vector2(body.position.x + offset, soleY - 0.20),
        Vector2(0, 0.29),
        (hit) {
          if (hit.shape.body == body ||
              hit.shape.isSensor ||
              hit.normal.y > -math.cos(GameConfig.maximumSlopeRadians)) {
            return -1;
          }
          final slope = -hit.normal.x / hit.normal.y;
          final centreGap = hit.point.y - soleY - offset * slope;
          final capsuleGap =
              GameConfig.playerWidth / 2 * (math.sqrt(1 + slope * slope) - 1);
          if (centreGap > capsuleGap + (_grounded ? 0.07 : 0.02)) return -1;
          final relativeVelocity =
              body.linearVelocity - hit.shape.body.linearVelocity;
          if (relativeVelocity.dot(hit.normal) > 0.65) return -1;
          if (closest == null || hit.point.y < closest!.point.y) closest = hit;
          if (offset == 0) {
            centre = true;
          } else {
            sides += offset.sign;
          }
          return hit.fraction;
        },
        filter: QueryFilter(maskBits: CollisionLayers.solid),
      );
    }
    _centreSupported = centre;
    // Ground under only one side of him: which side. He steps back until
    // it is under the middle and both sides of him — but only from a real
    // drop, not from a slope or a bump falling away under the other side.
    _edgeSide = sides.sign;
    if (_edgeSide != 0 &&
        probeGround(
              world,
              body.position.x - _edgeSide * 0.10,
              soleY - 0.2,
              0.6,
              ignore: body,
            ) !=
            null) {
      _edgeSide = 0;
    }
    return closest;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!body.isValid) {
      if (kDebugMode) debugPrint('Umbra physics: invalid player body handle');
      return;
    }
    _time += dt;
    if (_intent.consumeKnockdownRequest() && _ragdoll == null && !_dead) {
      knockDown();
    }
    if (_ragdoll != null) {
      _updateRagdoll(dt);
      _intent.consumeJumpRequest();
      _intent.consumeInteractRequest();
      return;
    }
    if (_recoveryPose != null) {
      _recoveryTime += dt;
      state = CharacterState.recovering;
      if (_recoveryTime >= GameConfig.recoveryBlendSeconds) {
        // A crate can enter the recovery space during the visual blend.
        // Do not re-enable a solid capsule inside it.
        if (!_recoverySpaceClear()) return;
        _recoveryPose = null;
        body.isEnabled = true;
        _feet.reset();
        _limbs.reset();
      }
      return;
    }

    final measuredVelocity = body.linearVelocity;
    final wasGrounded = _grounded;
    final support = _supportBelow();
    _grounded = support != null;
    _onLoose = support != null && support.shape.body.type == BodyType.dynamic;
    _onProp = support != null && support.shape.body.type != BodyType.static;
    if (support != null) {
      _supportSlope = -support.normal.x / support.normal.y;
      _supportY =
          support.point.y + (body.position.x - support.point.x) * _supportSlope;
      _supportVelocity = support.shape.body.linearVelocity;
    }
    if (_grounded && !wasGrounded) {
      final impact = _previousVerticalSpeed - _supportVelocity.y;
      _jumping = false;
      _landings++;
      _lastLandingImpact = impact;
      _lastLandingAt.setValues(body.position.x, _supportY);
      if (impact > GameConfig.deathImpactSpeed) {
        die();
        return;
      }
      // The body takes the landing from the next step, when the capsule
      // has actually stopped: taken now, the hips would start sinking
      // while it is still falling, and jolt.
      _pendingLanding = impact;
    } else if (_pendingLanding != null) {
      final double impact = _pendingLanding!;
      _pendingLanding = null;
      if (impact > GameConfig.hardLandingSpeed) {
        _hardLanding = 1;
        _hardLandingHold = GameConfig.hardLandingSeconds;
      } else {
        _landing = (impact / 7).clamp(0.0, 1.0);
      }
      // The landing's real speed goes into the pelvis spring: the body
      // keeps sinking for a moment and the knees fold to catch it.
      _pelvisSpeed += impact.clamp(0.0, GameConfig.deathImpactSpeed) * 0.385;
    }
    for (final hit in world.physicsWorld.contactEvents.hit) {
      if (hit.approachSpeed > GameConfig.deathImpactSpeed &&
          hit.shapeA.isValid &&
          hit.shapeB.isValid &&
          (hit.shapeA.body == body || hit.shapeB.body == body)) {
        die();
        return;
      }
    }

    // On a rope, W and ↑ climb; only the jump button kicks off.
    final jumpPressed =
        _intent.consumeJumpRequest() &&
        !(interactions.attachedRope != null && _intent.lastJumpFromUp);
    final interactPressed = _intent.consumeInteractRequest();
    _intent.consumeInteractRelease();
    interactions.update(
      dt,
      axis: _intent.horizontalAxis,
      facing: _facing,
      grounded: _grounded,
      interactPressed: interactPressed && !_low,
      interactHeld: _intent.isInteractHeld && !_low,
      jumpPressed: jumpPressed,
      downHeld: _intent.isDownHeld,
      upHeld: _intent.isUpHeld,
    );
    if (interactions.controlsMotion) {
      _grounded = false;
      _timeSinceGrounded = double.infinity;
      _timeSinceJumpPressed = double.infinity;
      _anticipationTime = 0;
      _animate(dt, measuredVelocity);
      _selectState();
      _simulateLimbs(dt);
      _previousVerticalSpeed = body.linearVelocity.y;
      return;
    }
    _timeSinceGrounded = _grounded ? 0 : _timeSinceGrounded + dt;
    _updateSliding(dt);
    _timeSinceJumpPressed = jumpPressed && !interactions.releasedThisStep
        ? 0
        : _timeSinceJumpPressed + dt;
    _updateLow(dt, jumpPressed);
    _hardLandingHold = math.max(0, _hardLandingHold - dt);

    final axis = _intent.horizontalAxis;
    // A long drop folds the knees: he stays down for a moment, then runs on.
    final double held = _hardLandingHold > 0 ? 0.15 : 1;
    // Wading: the deeper the water, the heavier each step.
    final double wade = 1 - 0.5 * (waterDepth / 0.9).clamp(0.0, 1.0);
    var speed = GameConfig.moveSpeedMetersPerSecond * held * wade;
    // Moving a crate is a slow, heavy walk, slower the heavier it is.
    final load = interactions.pushResistanceBody;
    if (load != null && load.isValid) {
      final double weight =
          ((load.mass - GameConfig.lightCrateKg) /
                  (GameConfig.heavyCrateKg - GameConfig.lightCrateKg))
              .clamp(0.0, 1.0);
      final bool pulling = interactions.mode == InteractionMode.pulling;
      final double light = pulling
          ? GameConfig.pullSpeedLight
          : GameConfig.pushSpeedLight;
      final double heavy = pulling
          ? GameConfig.pullSpeedHeavy
          : GameConfig.pushSpeedHeavy;
      speed = math.min(speed, light + (heavy - light) * weight);
    }
    // Low he creeps; getting up off the ground he barely moves.
    if (_low) {
      speed = math.min(
        speed,
        GameConfig.crouchSpeedMetersPerSecond * (1 - 0.85 * _sit.value),
      );
    }
    final surfaceScale = _grounded
        ? 1 / math.sqrt(1 + _supportSlope * _supportSlope)
        : 1.0;
    final supportX = _grounded ? _supportVelocity.x : 0.0;
    // Stopped with only one side of him on the ground (his middle over a
    // drop), he steps back onto it. Steering towards the drop walks off it.
    _steppingBack =
        _grounded &&
        axis == 0 &&
        _edgeSide != 0 &&
        !_sliding &&
        interactions.mode == InteractionMode.none &&
        _anticipationTime <= 0 &&
        !_low;
    final target = _steppingBack
        ? supportX + _edgeSide * GameConfig.edgeStepBackSpeed * surfaceScale
        : !_grounded && axis == 0
        ? measuredVelocity.x
        : supportX + axis * speed * surfaceScale;
    final traction = support == null
        ? 1.0
        : (support.shape.friction / 0.6).clamp(0.08, 1.0);
    var acceleration = _grounded
        ? (axis == 0
                  ? GameConfig.groundDeceleration
                  : GameConfig.groundAcceleration) *
              traction
        : GameConfig.airAcceleration;
    // Off the bottom of a slide the speed carries on, braking gently.
    final double relative = measuredVelocity.x - supportX;
    if (_grounded &&
        _slideCarry > 0 &&
        relative.abs() > (target - supportX).abs() &&
        relative * (target - supportX) >= 0) {
      acceleration = GameConfig.slideCarryDeceleration;
    }
    final pushing = interactions.pushResistanceBody != null;
    final interactionForce = interactions.mode == InteractionMode.pulling
        ? GameConfig.pullForceNewtons
        : GameConfig.pushForceNewtons;
    final maxAcceleration = pushing
        ? math.min(acceleration, interactionForce / body.mass)
        : acceleration;
    final newX = _sliding
        ? _slideVelocity(measuredVelocity.x, supportX, axis, dt)
        : _approach(measuredVelocity.x, target, maxAcceleration * dt);
    // Impulse is bounded by mass * acceleration * dt, so physical contacts
    // with a heavy crate or external body still resist the controller.
    final double drive = (newX - measuredVelocity.x) * body.mass;
    body.applyLinearImpulse(Vector2(drive, 0));
    // His feet push back on what they stand on, as hard as it pushes him:
    // running on a plank, a crate or the floor of a hanging cage moves it.
    if (support != null &&
        support.shape.body.type == BodyType.dynamic &&
        support.shape.body.isValid) {
      support.shape.body.applyLinearImpulse(
        Vector2(-drive, 0),
        point: support.point,
      );
    }
    // On the ground he follows it up and down exactly. On something that
    // moves under his weight (a raft, a plank) he rests on it instead, so
    // the contact carries his weight into it and it sinks or tips as it
    // should.
    final bool loose =
        support != null && support.shape.body.type == BodyType.dynamic;
    if (_grounded && !loose) {
      body.linearVelocity = Vector2(
        body.linearVelocity.x,
        _supportVelocity.y + (newX - _supportVelocity.x) * _supportSlope,
      );
    } else if (!_grounded && measuredVelocity.y > 0) {
      body.applyForce(
        Vector2(
          0,
          body.mass *
              GameConfig.gravityMetersPerSecondSquared *
              (GameConfig.fallGravityMultiplier - 1),
        ),
      );
    }

    if (_anticipationTime > 0) {
      _anticipationTime -= dt;
      if (_anticipationTime <= 0) _launchJump();
    } else if (_timeSinceJumpPressed <= GameConfig.jumpBufferSeconds &&
        _timeSinceGrounded <= GameConfig.coyoteTimeSeconds &&
        !_jumping &&
        _hardLandingHold <= 0) {
      _anticipationTime = GameConfig.jumpAnticipationSeconds;
      _timeSinceJumpPressed = double.infinity;
    }

    _animate(dt, measuredVelocity);
    _selectState();
    _simulateLimbs(dt);
    _previousVerticalSpeed = body.linearVelocity.y;
  }

  /// The hips follow the height they need to reach the planted feet on a
  /// critically damped spring (about 8 Hz), instead of dropping to a new
  /// foothold in one frame.
  void _followHipFloor(double dt, CharacterPose pose) {
    final (base, need) = _figure.rig.hipHeights(pose);
    final double target = math.max(base, need);
    if (!_hipFloor.isFinite) {
      _hipFloor = target;
      _hipFloorSpeed = 0;
      return;
    }
    const double omega = 2 * math.pi * 8;
    final double decay = math.exp(-omega * dt);
    final double x = _hipFloor - target;
    final double c = _hipFloorSpeed + x * omega;
    _hipFloor = target + (x + c * dt) * decay;
    _hipFloorSpeed = (_hipFloorSpeed - c * omega * dt) * decay;
  }

  /// Steep ground starts a slide; gentler ground ends it, and the speed
  /// carries on for a moment after.
  void _updateSliding(double dt) {
    _slideCarry = math.max(0, _slideCarry - dt);
    final double angle = math.atan(_supportSlope.abs());
    // A bank slides him down it; something afloat or on a pivot does not:
    // on that he keeps his feet and balances, and only goes if it turns
    // right over.
    final bool free =
        _grounded &&
        !_onLoose &&
        interactions.mode == InteractionMode.none &&
        _anticipationTime <= 0;
    if (!free) {
      if (_sliding && _grounded) _slideCarry = GameConfig.slideCarrySeconds;
      _sliding = false;
    } else if (!_sliding && angle > GameConfig.slideStartRadians) {
      _sliding = true;
    } else if (_sliding && angle < GameConfig.slideStopRadians) {
      _sliding = false;
      _slideCarry = GameConfig.slideCarrySeconds;
    }
  }

  /// Horizontal velocity while sliding: gravity along the slope less a
  /// little friction, capped, with steering only nudging it.
  double _slideVelocity(
    double measured,
    double supportX,
    double axis,
    double dt,
  ) {
    final double theta = math.atan(_supportSlope.abs());
    final double downhill = _supportSlope.sign;
    final double along =
        GameConfig.gravityMetersPerSecondSquared *
        (math.sin(theta) - GameConfig.slideFriction * math.cos(theta));
    final double cap = GameConfig.slideMaxSpeed * math.cos(theta);
    final double vx =
        measured -
        supportX +
        (downhill * along * math.cos(theta) +
                axis * GameConfig.slideSteerAcceleration) *
            dt;
    return supportX + vx.clamp(-cap, cap);
  }

  /// One step of the visual body's physics: the pelvis spring, then the
  /// limbs: legs that hang from the solved hips and stand on the real
  /// ground, and arms that swing from the shoulders or hold on.
  int footfalls = 0;

  /// Feet that have come down on the ground and not yet been heard, each
  /// with how hard and on what. See [drainFootContacts].
  final List<FootContact> _contacts = [];
  final List<double> _lastContact = [-1, -1];

  /// How many times a foot has come down, and the last time it did.
  int footContacts = 0;
  FootContact? lastFootContact;

  /// The feet that have come down since the last call: every stride, and
  /// every little step in place.
  List<FootContact> drainFootContacts() {
    final List<FootContact> out = List.of(_contacts);
    _contacts.clear();
    return out;
  }

  void _simulateLimbs(double dt) {
    // A footstrike while running gives the spring a small kick.
    final planted = _feet.planted;
    for (var i = 0; i < 2; i++) {
      if (_grounded && planted[i] && !_wasPlanted[i]) {
        _pelvisSpeed += 0.28 * _gaitWeight;
        // Slow walking is still a footstrike. Ignore idle weight shifts
        // and sliding, which do not make separate locomotion impacts.
        final bool stride = _actualSpeed.abs() > 0.12;
        if (stride && !isSliding) footfalls++;
        // Every foot that comes down is heard, a stride or a step in
        // place, softer the slower he goes; never twice in a tenth of a
        // second for the same foot.
        if (!isSliding &&
            _time - _lastContact[i] > 0.1 &&
            _contacts.length < 8) {
          _lastContact[i] = _time;
          final Body? on = _feet.supports[i];
          footContacts++;
          _contacts.add(
            lastFootContact = FootContact(
              foot: i,
              x: _feet.targets[i].x,
              onProp: on != null && on.isValid && on.type != BodyType.static,
              stride: stride,
              strength: stride ? 0.35 + 0.35 * _gaitWeight : 0.2,
            ),
          );
        }
      }
    }
    _wasPlanted = planted;
    // About 3.3 Hz and nearly critically damped: one soft dip, no rebound.
    const double stiffness = 420, damping = 37;
    _pelvisSpeed += (-stiffness * _pelvisDrop - damping * _pelvisSpeed) * dt;
    _pelvisDrop = (_pelvisDrop + _pelvisSpeed * dt).clamp(-0.01, 0.30);

    final bool turning = visualFacing.abs() < 0.999;
    final climbFeet = interactions.climbFeet;
    final modes = interactions.ropeFeet != null
        // Feet clamping a rope.
        ? const [LegMode.planted, LegMode.planted]
        // Climbing onto a ledge: each foot planted on the top once it is
        // up, dangling until then.
        : climbFeet != null
        ? [
            for (final foot in climbFeet)
              foot == null ? LegMode.hang : LegMode.planted,
          ]
        : interactions.mode == InteractionMode.hanging ||
              interactions.mode == InteractionMode.swinging
        ? const [LegMode.hang, LegMode.hang]
        : !_grounded
        ? const [LegMode.air, LegMode.air]
        // Mid-turn the feet step round under him rather than stay pinned.
        : turning
        ? const [LegMode.swing, LegMode.swing]
        : [for (final p in planted) p ? LegMode.planted : LegMode.swing];
    final armModes = interactions.gripWorld != null && _gripWeight > 0.6
        ? const [ArmMode.grip, ArmMode.grip]
        : _grounded && !interactions.controlsMotion
        ? const [ArmMode.ground, ArmMode.ground]
        : const [ArmMode.air, ArmMode.air];
    final pose = _pose;
    final target = _figure.solve(pose).translated(body.position);
    // For the next step: where the hips must come down to for the feet.
    _followHipFloor(dt, pose);
    final hands = _handTargets;
    if (turning && hands != null && _gripWeight > 0.6) {
      // The turn narrows the pose; the hands stay on what they hold.
      target.joints[RigJoint.frontHand] = hands[0];
      target.joints[RigJoint.backHand] = hands[1];
    }
    _drawnPose = _limbs.step(
      dt: dt,
      target: target,
      modes: modes,
      armModes: armModes,
      ground: (x, fromY, depth) =>
          probeGround(world, x, fromY, depth, ignore: body),
    );
  }

  void _launchJump() {
    body.applyLinearImpulse(
      Vector2(
        0,
        (-GameConfig.jumpTakeoffSpeed +
                _supportVelocity.y -
                body.linearVelocity.y) *
            body.mass,
      ),
    );
    _grounded = false;
    _jumping = true;
    _takeoff = 1;
    _timeSinceGrounded = double.infinity;
    _feet.reset();
  }

  bool _recoverySpaceClear() {
    final centre = body.position;
    final bounds = Aabb(
      centre -
          Vector2(
            GameConfig.playerWidth * 0.42,
            GameConfig.playerHeight / 2 - 0.025,
          ),
      centre +
          Vector2(
            GameConfig.playerWidth * 0.42,
            GameConfig.playerHeight / 2 - GameConfig.playerWidth * 0.48,
          ),
    );
    return !world
        .overlapAabb(
          bounds,
          filter: QueryFilter(maskBits: CollisionLayers.solid),
        )
        .any((shape) => shape.body != body && !shape.isSensor);
  }

  void _animate(double dt, Vector2 measuredVelocity) {
    _gripWeight = _approach(
      _gripWeight,
      interactions.gripWorld == null ? 0 : 1,
      dt * 12,
    );
    final travelled = body.position - _lastPosition;
    if (kDebugMode && travelled.length > 1.0) {
      debugPrint(
        'Umbra physics: unexpected ${travelled.length.toStringAsFixed(2)} m displacement in ${state.name}',
      );
    }
    _lastPosition.setFrom(body.position);
    final relativeTravel =
        travelled - (_grounded ? _supportVelocity * dt : Vector2.zero());
    _actualSpeed = relativeTravel.x / dt;
    final pulling = interactions.mode == InteractionMode.pulling;
    if (interactions.facingOverride != null) {
      _facing = interactions.facingOverride!;
    } else if (!pulling && !_steppingBack && _actualSpeed.abs() > 0.18) {
      _facing = _actualSpeed.sign;
    } else if (!pulling &&
        body.linearVelocity.x.abs() < 0.18 &&
        _intent.horizontalAxis != 0) {
      _facing = _intent.horizontalAxis.sign;
    }
    // Turning round is a quick pivot through a front view, not a mirror
    // flip: the drawn body turns on an angle, and can turn back mid-way.
    _turnAngle = _approach(
      _turnAngle,
      _facing > 0 ? 0 : math.pi,
      dt * math.pi / GameConfig.turnSeconds,
    );

    final moving = _grounded && !_sliding && _actualSpeed.abs() > 0.12;
    final bool bracing =
        interactions.mode == InteractionMode.pushing ||
        interactions.mode == InteractionMode.pulling;
    if (moving) {
      _gaitPhase +=
          relativeTravel.length *
          (2 *
              math.pi /
              (Gait.strideMeters(_actualSpeed) *
                  FootPlacement.strideScale(bracing)));
    }
    final gaitTarget = moving
        ? (_actualSpeed.abs() / GameConfig.moveSpeedMetersPerSecond).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    _gaitWeight = _approach(_gaitWeight, gaitTarget, dt * 7);
    _pushWeight = _approach(
      _pushWeight,
      interactions.mode == InteractionMode.pushing ||
              interactions.mode == InteractionMode.pulling
          ? 1
          : 0,
      dt * 6,
    );
    _pullWeight = _approach(_pullWeight, pulling ? 1 : 0, dt * 6);
    // Effort: how heavy the crate is, and more when it barely moves.
    final load = interactions.pushResistanceBody;
    double effortTarget = 0;
    if (load != null && load.isValid) {
      final double heavy = (load.mass / 40).clamp(0.0, 1.0);
      final double stalled =
          1 - (load.linearVelocity.x.abs() / 1.2).clamp(0.0, 1.0);
      effortTarget = math.max(heavy, stalled * 0.85);
    }
    _effort = _approach(_effort, effortTarget, dt * 2.5);
    _updateBrace(dt);
    _airWeight = _approach(_airWeight, _grounded ? 0 : 1, dt * 12);
    _airSeconds = _grounded ? 0 : _airSeconds + dt;
    // On a rope with the feet free, the legs kick the way he swings, and
    // the way he pumps.
    final bool freeSwing =
        interactions.mode == InteractionMode.swinging &&
        interactions.ropeFeet == null;
    _swingKick = _approach(
      _swingKick,
      freeSwing
          ? (body.linearVelocity.x * _facing / 2.2 +
                    _intent.horizontalAxis * _facing * 0.5)
                .clamp(-1.0, 1.0)
          : 0,
      dt * 4,
    );
    final bool armsUp = !_grounded && (_jumping || _airSeconds > 0.15);
    // On a jump the arms come up with him at once; on a fall, gently.
    _armAirWeight = _approach(
      _armAirWeight,
      armsUp ? 1 : 0,
      dt * (armsUp ? (_jumping ? 9 : 5) : 6),
    );
    _slideWeight = _approach(_slideWeight, _sliding ? 1 : 0, dt * 6);
    _fallLean = _approach(
      _fallLean,
      (body.linearVelocity.y / 6).clamp(-1.0, 1.0),
      dt * 8,
    );
    final acceleration = (body.linearVelocity.x - measuredVelocity.x) / dt;
    // Lean into a start and back against a skid. Braking without input is
    // a sharper lean back, held briefly, as the feet dig in.
    final braking =
        _grounded &&
        !_sliding &&
        _intent.horizontalAxis == 0 &&
        _actualSpeed.abs() > 1.0 &&
        !interactions.controlsMotion;
    final leanTarget = braking
        ? -0.16
        : (acceleration * _facing / 70).clamp(-0.10, 0.12);
    _bodyLean = _approach(_bodyLean, leanTarget, dt * (braking ? 2.4 : 0.9));
    _hairSway = _approach(
      _hairSway,
      (-acceleration * _facing / 300).clamp(-0.025, 0.025) +
          _gaitWeight * 0.012,
      dt * 0.4,
    );
    _landing = math.max(0, _landing - dt * 5);
    _hardLanding = _hardLandingHold > 0
        ? 1
        : math.max(0, _hardLanding - dt * 3.2);
    _takeoff = math.max(0, _takeoff - dt * 10);
    _landingDrawn = _ease(_landingDrawn, _landing, dt);
    _hardLandingDrawn = _ease(_hardLandingDrawn, _hardLanding, dt);
    _anticipationDrawn = _approach(
      _anticipationDrawn,
      _anticipationTime > 0 ? 1 : 0,
      dt * 20,
    );
    _takeoffDrawn = _ease(_takeoffDrawn, _takeoff, dt);
    _feet.update(
      world: world,
      body: body,
      height: GameConfig.playerHeight,
      phase: _gaitPhase,
      gait: _gaitWeight,
      facing: _facing,
      grounded: _grounded,
      speed: _actualSpeed,
      dt: dt,
      bracing: bracing,
      sliding: _sliding,
    );
    _updateIdle(dt);
    _updateTeeter(dt);
    if (_blinkRemaining > 0) {
      _blinkRemaining -= dt;
    } else if (_time >= _nextBlinkAt) {
      _blinkRemaining = 0.10;
      _nextBlinkAt = _time + 2.5 + (_time * 7.3) % 2.8;
    }
  }

  /// The arms' brace against a crate grows out of the front of the body
  /// while pushing and shrinks away after.
  void _updateBrace(double dt) {
    final double want = interactions.mode == InteractionMode.pushing
        ? GameConfig.pushBraceMeters +
              GameConfig.pushBraceStrainMeters * _effort
        : 0;
    final double length = _approach(
      interactions.braceLength,
      want,
      dt * GameConfig.pushBraceMeters / GameConfig.pushBraceSeconds,
    );
    interactions.braceLength = length;
    if ((length - _braceBuilt).abs() < 0.005 &&
        _braceFacing == _facing &&
        (length > 0) == (_brace != null)) {
      return;
    }
    if (_brace?.isValid ?? false) _brace!.destroy(updateBodyMass: false);
    _brace = null;
    _braceBuilt = length;
    _braceFacing = _facing;
    if (length < 0.005) return;
    // From inside the capsule to [length] beyond its side, at the height of
    // the hands on a crate.
    const double inside = GameConfig.playerWidth / 2 - 0.06;
    final double half = (GameConfig.playerWidth / 2 + length - inside) / 2;
    _brace = body.createShape(
      Polygon.offsetBox(
        half,
        0.08,
        center: Vector2(_facing * (inside + half), 0.10),
      ),
      ShapeDef(
        density: 0,
        updateBodyMass: false,
        material: SurfaceMaterial(friction: 0, restitution: 0),
        filter: Filter(
          categoryBits: CollisionLayers.player,
          maskBits: CollisionLayers.prop,
        ),
      ),
    );
  }

  /// Stopping right at an edge he faces, he balances a moment: arms out,
  /// rocking over the drop, looking down into it. Once per stop.
  void _updateTeeter(double dt) {
    _sinceRunning = _actualSpeed.abs() > 1.0 ? 0 : _sinceRunning + dt;
    final bool free =
        _grounded &&
        !_sliding &&
        !_low &&
        interactions.mode == InteractionMode.none &&
        _hardLandingHold <= 0;
    if (!free || _actualSpeed.abs() > 1.0) _teeterArmed = true;
    if (_teeterTime >= 0) {
      _teeterTime += dt;
      if (_teeterTime > GameConfig.teeterSeconds ||
          !free ||
          _intent.horizontalAxis != 0) {
        _teeterTime = -1;
      }
      return;
    }
    if (!_teeterArmed ||
        !free ||
        _actualSpeed.abs() > 0.4 ||
        _sinceRunning > 0.5 ||
        _intent.horizontalAxis != 0) {
      return;
    }
    final double soleY = body.position.y + GameConfig.playerHeight / 2;
    bool groundAt(double x) =>
        probeGround(world, x, soleY - 0.25, 0.75, ignore: body) != null;
    if (groundAt(body.position.x + _facing * GameConfig.teeterReach)) return;
    // Where the ground ends: the lip the earth crumbles off.
    var lip = body.position.x;
    for (var i = 1; i <= 12; i++) {
      final double x = body.position.x + _facing * i * 0.02;
      if (!groundAt(x)) break;
      lip = x;
    }
    _teeterLip.setValues(lip, _supportY);
    _teeterTime = 0;
    _teeterArmed = false;
    _teeters++;
  }

  void _updateIdle(double dt) {
    final bool still =
        _grounded &&
        state == CharacterState.idle &&
        _intent.horizontalAxis == 0 &&
        !interactions.controlsMotion &&
        interactions.mode == InteractionMode.none &&
        _teeterTime < 0 &&
        _actualSpeed.abs() < 0.12;
    _stillSeconds = still ? _stillSeconds + dt : 0;
    if (!still) {
      _idleAction = IdleAction.none;
      _nextIdleAt = GameConfig.idleFirstSeconds;
    } else if (_idleAction == IdleAction.none && _stillSeconds >= _nextIdleAt) {
      // Drawn from a shuffled bag, so he does each before any again.
      if (_idleBag.isEmpty) {
        final last = _lastIdleAction;
        _idleBag
          ..addAll(const [
            IdleAction.lookUp,
            IdleAction.lookBack,
            IdleAction.shiftFeet,
          ])
          ..shuffle(_idleRandom);
        if (_idleBag.last == last) _idleBag.insert(0, _idleBag.removeLast());
      }
      _idleAction = _idleBag.removeLast();
      _idleActionTime = 0;
      if (_idleAction == IdleAction.shiftFeet) _feet.shiftStance();
    }
    if (_idleAction != IdleAction.none) {
      _idleActionTime += dt;
      final double duration = switch (_idleAction) {
        IdleAction.lookUp => 1.7,
        IdleAction.lookBack => 1.3,
        _ => 0.6,
      };
      if (_idleActionTime >= duration) {
        _lastIdleAction = _idleAction;
        _idleAction = IdleAction.none;
        _nextIdleAt =
            _stillSeconds +
            GameConfig.idleMinGapSeconds +
            _idleRandom.nextDouble() *
                (GameConfig.idleMaxGapSeconds - GameConfig.idleMinGapSeconds);
      }
    }
    _lookUp = _approach(
      _lookUp,
      _idleAction == IdleAction.lookUp || forceLookUp ? 1 : 0,
      dt * 2.6,
    );
    _headTurn = _approach(
      _headTurn,
      _idleAction == IdleAction.lookBack || forceLookBack ? 0.85 : 0,
      dt * 3.5,
    );
  }

  void _selectState() {
    final interactionState = switch (interactions.mode) {
      InteractionMode.pushing => CharacterState.pushing,
      InteractionMode.pulling =>
        _gripWeight < 0.85 ? CharacterState.grabbing : CharacterState.pulling,
      InteractionMode.hanging => CharacterState.hanging,
      InteractionMode.swinging => CharacterState.swinging,
      InteractionMode.climbing => CharacterState.climbing,
      _ => null,
    };
    if (interactionState != null) {
      state = interactionState;
      return;
    }
    if (_anticipationTime > 0) {
      state = CharacterState.jumpAnticipation;
      return;
    }
    if (!_grounded) {
      state = body.linearVelocity.y.abs() < 0.65
          ? CharacterState.jumpApex
          : body.linearVelocity.y < 0
          ? CharacterState.jumpAscending
          : CharacterState.falling;
    } else if (_sliding) {
      state = CharacterState.sliding;
    } else if (_landing > 0.2 || _hardLandingHold > 0) {
      state = CharacterState.landing;
    } else if (_low) {
      state = _lowStill >= GameConfig.sitAfterSeconds
          ? CharacterState.sitting
          : CharacterState.crouching;
    } else if (_intent.horizontalAxis != 0 &&
        _actualSpeed * _intent.horizontalAxis < -0.1) {
      state = CharacterState.turning;
    } else if (_intent.horizontalAxis == 0 && _actualSpeed.abs() > 0.1) {
      state = CharacterState.stopping;
    } else if (_intent.horizontalAxis != 0 &&
        _actualSpeed.abs() < GameConfig.moveSpeedMetersPerSecond * 0.6) {
      state = CharacterState.starting;
    } else if (_actualSpeed.abs() < 0.12) {
      state = CharacterState.idle;
    } else {
      state = CharacterState.running;
    }
  }

  /// Where the hands hold, world metres, front then back: on a rope, each
  /// hand's own grip on it; otherwise both on the one grip.
  List<Vector2>? get _handTargets {
    final rope = interactions.ropeHands;
    if (rope != null) return rope;
    final grip = interactions.gripWorld;
    return grip == null ? null : [grip, grip + Vector2(0, 0.02)];
  }

  CharacterPose get _pose =>
      _buildPose(hipFloor: _hipFloor.isFinite ? _hipFloor : null);

  CharacterPose _buildPose({double? hipFloor}) {
    Offset local(Vector2 point) => Offset(
      (point.x - body.position.x) * _facing / GameConfig.playerHeight,
      (point.y - body.position.y) / GameConfig.playerHeight,
    );
    final targets = _feet.targets;
    final normals = _feet.normals;
    final rolls = _feet.rolls;
    Offset localNormal(Vector2 n) => Offset(n.x * _facing, n.y);
    final hands = _handTargets;
    // Feet clamping a rope: soles pressed to it from behind, toes down.
    final ropeFeet = interactions.ropeFeet;
    final bool clamped = ropeFeet != null;
    const ropeSole = Offset(0.6, -0.8);
    // Climbing onto a ledge: the feet that are up stand on its top.
    final climbFeet = interactions.climbFeet;
    final double? climb = interactions.climbProgress;
    Offset? footAt(int i) {
      if (clamped) {
        return local(
          i == 0 ? ropeFeet : ropeFeet + Vector2(-_facing * 0.02, 0.07),
        );
      }
      if (climbFeet != null) {
        final foot = climbFeet[i];
        return foot == null ? null : local(foot);
      }
      if (!_grounded) return null;
      // Sitting, the feet go out in front and the knees come up.
      return local(targets[i]) + Offset(_sit.value * (i == 0 ? 0.15 : 0.11), 0);
    }

    Offset? normalAt(int i) {
      if (clamped) return ropeSole;
      if (climbFeet != null) {
        return climbFeet[i] == null ? null : const Offset(0, -1);
      }
      return _grounded ? localNormal(normals[i]) : null;
    }

    return CharacterPose(
      facing: visualFacing,
      gaitPhase: _gaitPhase,
      gait: _gaitWeight,
      // Eased both ways, so a landing blends out of the air pose rather
      // than snapping out of it.
      air: _airWeight,
      armAir: _smooth(_armAirWeight),
      fallLean: _fallLean,
      blink: _blinkRemaining > 0,
      groundY: _grounded
          ? (_supportY - body.position.y) / GameConfig.playerHeight
          : 0.5,
      groundSlope: _grounded ? _supportSlope * _facing : 0,
      landing: _landingDrawn,
      hardLanding: _hardLandingDrawn,
      takeoff: _takeoffDrawn,
      bodyLean: _bodyLean,
      push: _pushWeight,
      pull: _pullWeight,
      effort: _effort,
      slide: _slideWeight,
      teeter: _teeterWeight,
      teeterTime: math.max(0, _teeterTime),
      anticipation: _smooth(_anticipationDrawn),
      hanging:
          interactions.mode == InteractionMode.hanging ||
              interactions.mode == InteractionMode.swinging
          ? 1
          // Climbing: out of the hang as he pulls himself up.
          : climb != null
          ? 1 - _smooth((climb / 0.5).clamp(0.0, 1.0))
          : 0,
      climb: climb ?? 0,
      hangLow: interactions.mode == InteractionMode.swinging ? 1 : 0,
      swingKick: _swingKick,
      clock: _time,
      pelvisDrop: _pelvisDrop / GameConfig.playerHeight,
      frontFoot: footAt(0),
      backFoot: footAt(1),
      frontFootNormal: normalAt(0),
      backFootNormal: normalAt(1),
      frontRoll: _grounded ? rolls[0] : 0,
      backRoll: _grounded ? rolls[1] : 0,
      frontHand: hands == null ? null : local(hands[0]),
      backHand: hands == null ? null : local(hands[1]),
      interactionWeight: _gripWeight,
      hipFloor: hipFloor,
      lookUp: _smooth(_lookUp),
      headTurn: _smooth(_headTurn / 0.85) * 0.85,
      crouch: _crouch.value.clamp(0.0, 1.0),
      sit: _sit.value.clamp(0.0, 1.0),
    );
  }

  /// The body goes limp, for good. Used by spikes, long falls and heavy hits.
  void die() {
    if (_dead) return;
    _dead = true;
    if (_recoveryPose != null) {
      _recoveryPose = null;
      body.isEnabled = true;
    }
    if (_ragdoll == null) knockDown();
  }

  /// Hands motion to the articulated ragdoll. Unless dead, the controller
  /// takes back over once the body comes to rest somewhere he can stand.
  void knockDown() {
    if (_ragdoll != null || _recoveryPose != null) return;
    interactions.release();
    final rig = rigPoseWorld;
    _resetLow();
    _ragdoll = CharacterRagdoll.activate(
      world: world.physicsWorld,
      pose: rig,
      velocity: body.linearVelocity,
      userData: this,
    );
    body.isEnabled = false;
    _grounded = false;
    _feet.reset();
    state = CharacterState.ragdoll;
  }

  void _updateRagdoll(double dt) {
    final ragdoll = _ragdoll!;
    ragdoll.update(dt);
    state = CharacterState.ragdoll;
    if (_dead || !ragdoll.isStable) return;
    final recovery = ragdoll.recoveryPosition(
      capsuleHeight: GameConfig.playerHeight,
      capsuleWidth: GameConfig.playerWidth,
    );
    if (recovery == null) return;
    _recoveryPose = ragdoll.pose;
    _recoveryTime = 0;
    ragdoll.destroy();
    _ragdoll = null;
    body.setTransform(recovery, const Rot.identity());
    body.linearVelocity = Vector2.zero();
    _lastPosition.setFrom(recovery);
    _gaitWeight = 0;
    _airWeight = 0;
    _landing = 0;
    _hardLanding = 0;
    _grounded = true;
    _supportY = recovery.y + GameConfig.playerHeight / 2;
    _supportSlope = 0;
    _feet.reset();
    _feet.update(
      world: world,
      body: body,
      height: GameConfig.playerHeight,
      phase: 0,
      gait: 0,
      facing: _facing,
      grounded: true,
      speed: 0,
      dt: dt,
    );
    state = CharacterState.recovering;
  }

  static double _smooth(double t) => t * t * (3 - 2 * t);

  /// Rises to [target] over about 0.07 s; falls with it as it falls.
  static double _ease(double value, double target, double dt) => target > value
      ? value + (target - value) * (1 - math.exp(-dt / 0.035))
      : target;

  static double _approach(double value, double target, double step) =>
      (target - value).abs() <= step
      ? target
      : value + step * (target - value).sign;

  void teleportTo(Vector2 position) {
    interactions.release();
    _ragdoll?.destroy();
    _ragdoll = null;
    _recoveryPose = null;
    _dead = false;
    _resetLow();
    body.isEnabled = true;
    body.setTransform(position, const Rot.identity());
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0;
    _lastPosition.setFrom(position);
    _feet.reset();
    _limbs.reset();
    _drawnPose = null;
    _pelvisDrop = 0;
    _pelvisSpeed = 0;
    _hipFloor = double.nan;
    _pendingLanding = null;
    _grounded = false;
    _jumping = false;
    _timeSinceGrounded = double.infinity;
    _timeSinceJumpPressed = double.infinity;
    _gaitWeight = 0;
    _airWeight = 0;
    _armAirWeight = 0;
    _airSeconds = 0;
    _landing = 0;
    _hardLanding = 0;
    _landingDrawn = 0;
    _hardLandingDrawn = 0;
    _hardLandingHold = 0;
    _takeoff = 0;
    _anticipationTime = 0;
    _gripWeight = 0;
    _bodyLean = 0;
    _pushWeight = 0;
    _pullWeight = 0;
    _effort = 0;
    _sliding = false;
    _slideCarry = 0;
    _slideWeight = 0;
    interactions.braceLength = 0;
    _turnAngle = _facing > 0 ? 0 : math.pi;
    _idleAction = IdleAction.none;
    _teeterTime = -1;
    _teeterArmed = true;
    _stillSeconds = 0;
    _lookUp = 0;
    _headTurn = 0;
    _previousVerticalSpeed = 0;
    state = CharacterState.idle;
  }

  @override
  void render(Canvas canvas) {
    if (hidden) return;
    if (_grounded && _ragdoll == null) {
      final centre = Offset(0, _supportY - body.position.y + 0.008);
      _contactShadow.shader = Gradient.radial(centre, 0.30, const [
        Color(0x88000000),
        Color(0x00000000),
      ]);
      canvas.drawOval(
        Rect.fromCenter(center: centre, width: 0.6, height: 0.065),
        _contactShadow,
      );
    }
    if (_ragdoll != null) {
      _figure.drawRig(canvas, _ragdoll!.pose.translated(-body.position));
    } else if (_recoveryPose != null) {
      final t = (_recoveryTime / GameConfig.recoveryBlendSeconds).clamp(
        0.0,
        1.0,
      );
      final from = _recoveryPose!.translated(-body.position);
      _figure.drawRig(
        canvas,
        from.lerp(_figure.solve(_pose), t * t * (3 - 2 * t)),
      );
    } else {
      canvas.save();
      final drawn = _drawnPose;
      if (drawn != null) {
        // The simulated pose is in world metres; this canvas is centred on
        // the body.
        canvas.translate(-body.position.x, -body.position.y);
        _figure.drawRig(canvas, drawn, hairSway: _hairSway);
      } else {
        _figure.drawRig(canvas, _figure.solve(_pose), hairSway: _hairSway);
      }
      canvas.restore();
    }
    if (debugEnabled) renderDebug(canvas);
  }

  void renderDebug(Canvas canvas) {
    final line = Paint()
      ..color = const Color(0xFF58FFE2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.013;
    const radius = GameConfig.playerWidth / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          -radius,
          GameConfig.playerHeight / 2 - _capsuleHeight,
          radius * 2,
          _capsuleHeight,
        ),
        const Radius.circular(radius),
      ),
      line,
    );
    canvas.drawCircle(Offset.zero, 0.035, line);
    for (final x in const [-0.10, 0.0, 0.10]) {
      canvas.drawLine(
        Offset(x, GameConfig.playerHeight / 2 - 0.2),
        Offset(x, GameConfig.playerHeight / 2 + 0.09),
        line,
      );
    }
    line.color = const Color(0xFFFFB74D);
    for (final target in rigFootTargets) {
      canvas.drawCircle(
        Offset(target.x - body.position.x, target.y - body.position.y),
        0.04,
        line,
      );
    }
    final grip = interactions.gripWorld;
    if (grip != null) {
      canvas.drawCircle(
        Offset(grip.x - body.position.x, grip.y - body.position.y),
        0.05,
        line,
      );
    }
    if (kDebugMode &&
        (!body.position.x.isFinite || !body.position.y.isFinite)) {
      debugPrint('Umbra physics: non-finite player transform in ${state.name}');
    }
  }

  @override
  void onRemove() {
    interactions.dispose();
    _ragdoll?.destroy();
    super.onRemove();
  }
}

/// A foot coming down on the ground: which (0 front, 1 back), where (world
/// x), whether on something that moves (a crate, a plank: wood) rather
/// than the ground, whether in a stride or a step in place, and how hard,
/// 0–1.
class FootContact {
  const FootContact({
    required this.foot,
    required this.x,
    required this.onProp,
    required this.stride,
    required this.strength,
  });

  final int foot;
  final double x;
  final bool onProp, stride;
  final double strength;
}
