import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart';

import '../character/character_interactions.dart';
import '../character/character_preset.dart';
import '../character/character_ragdoll.dart';
import '../character/character_state.dart';
import '../character/foot_placement.dart';
import '../config/game_config.dart';
import '../config/palette.dart';
import '../input/player_intent.dart';
import '../physics/collision_layers.dart';
import '../render/raincoat_silhouette.dart';

/// One stable capsule owns locomotion. Constraint interactions may take over;
/// ragdoll explicitly disables the capsule until safe recovery has completed.
class Player extends BodyComponent {
  Player({required this._intent, required Vector2 spawnPosition})
    : _spawnPosition = spawnPosition.clone(),
      _lastPosition = spawnPosition.clone(),
      super(paint: Paint()..color = Palette.silhouette, renderBody: false);

  final PlayerIntent _intent;
  final Vector2 _spawnPosition;
  final Vector2 _lastPosition;
  final FootPlacement _feet = FootPlacement();
  RaincoatSilhouette _figure = RaincoatSilhouette(
    height: GameConfig.playerHeight,
  );
  CharacterPreset _preset = CharacterPreset.raincoat;
  CharacterRagdoll? _ragdoll;
  CharacterRigPose? _recoveryPose;
  double _recoveryTime = 0;
  late CharacterInteractions interactions;
  late Shape _capsule;
  bool _crouched = false;
  double _crouchWeight = 0;

  CharacterState state = CharacterState.idle;
  bool debugEnabled = false;
  bool _grounded = false;
  double _supportSlope = 0;
  double _supportY = 0;
  Vector2 _supportVelocity = Vector2.zero();
  double _timeSinceGrounded = double.infinity;
  double _timeSinceJumpPressed = double.infinity;
  double _anticipationTime = 0;
  bool _jumping = false;
  bool _jumpCutApplied = false;
  double _facing = 1;
  double _walkPhase = 0;
  double _walkWeight = 0;
  double _runWeight = 0;
  double _airWeight = 0;
  double _fallLean = 0;
  double _bodyLean = 0;
  double _landing = 0;
  double _takeoff = 0;
  double _previousVerticalSpeed = 0;
  double _time = 0;
  double _nextBlinkAt = 2.5;
  double _blinkRemaining = 0;
  double _actualSpeed = 0;
  double _gripWeight = 0;

  bool get isOnGround => _grounded;
  double get facing => _facing;
  int get presetIndex => _preset.index;
  bool get isRagdoll => _ragdoll != null;
  Vector2 get velocity => _ragdoll?.velocity ?? body.linearVelocity;
  Vector2 get cameraPosition => _ragdoll?.pelvisPosition ?? body.position;
  String get interactionLabel => interactions.mode.name;
  List<Vector2> get rigFootTargets => _feet.targets;
  CharacterRigPose get rigPoseWorld =>
      _ragdoll?.pose ?? _figure.solve(_pose).translated(body.position);
  bool get isCrouching => _crouched;
  double get strideMeters =>
      GameConfig.walkStrideMeters * (0.73 + _runWeight * 0.27);

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

  Shape _createCapsule(Body target) {
    const radius = GameConfig.playerWidth / 2;
    const halfHeight = GameConfig.playerHeight / 2;
    final height =
        GameConfig.playerHeight *
        (_crouched ? GameConfig.crouchHeightRatio : 1);
    final area = 2 * radius * (height - 2 * radius) + math.pi * radius * radius;
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
          return hit.fraction;
        },
        filter: QueryFilter(maskBits: CollisionLayers.solid),
      );
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
    if (_intent.consumeKnockdownRequest() && _ragdoll == null) knockDown();
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
      }
      return;
    }

    final measuredVelocity = body.linearVelocity;
    final wasGrounded = _grounded;
    final support = _supportBelow();
    _grounded = support != null;
    if (support != null) {
      _supportSlope = -support.normal.x / support.normal.y;
      _supportY =
          support.point.y + (body.position.x - support.point.x) * _supportSlope;
      _supportVelocity = support.shape.body.linearVelocity;
    }
    if (_grounded && !wasGrounded) {
      _landing = (_previousVerticalSpeed / 8).clamp(0.0, 1.0);
      _jumping = false;
      if (_previousVerticalSpeed > GameConfig.knockdownImpactSpeed) {
        knockDown();
        return;
      }
    }
    for (final hit in world.physicsWorld.contactEvents.hit) {
      if (hit.approachSpeed > GameConfig.knockdownImpactSpeed &&
          hit.shapeA.isValid &&
          hit.shapeB.isValid &&
          (hit.shapeA.body == body || hit.shapeB.body == body)) {
        knockDown();
        return;
      }
    }

    _updateCrouch();
    final jumpPressed = _intent.consumeJumpRequest();
    final interactPressed = _intent.consumeInteractRequest();
    _intent.consumeInteractRelease();
    interactions.update(
      dt,
      axis: _intent.horizontalAxis,
      facing: _facing,
      grounded: _grounded,
      interactPressed: interactPressed,
      interactHeld: _intent.isInteractHeld,
      jumpPressed: jumpPressed,
      crouchHeld: _intent.isCrouchHeld,
    );
    if (interactions.controlsMotion) {
      _grounded = false;
      _timeSinceGrounded = double.infinity;
      _timeSinceJumpPressed = double.infinity;
      _anticipationTime = 0;
      _animate(dt, measuredVelocity);
      _selectState();
      return;
    }
    _timeSinceGrounded = _grounded ? 0 : _timeSinceGrounded + dt;
    _timeSinceJumpPressed = jumpPressed && !interactions.releasedThisStep
        ? 0
        : _timeSinceJumpPressed + dt;

    final axis = _intent.horizontalAxis;
    final speed = _crouched
        ? GameConfig.crouchSpeedMetersPerSecond
        : (_intent.isRunHeld
              ? GameConfig.moveSpeedMetersPerSecond
              : GameConfig.walkSpeedMetersPerSecond);
    final surfaceScale = _grounded
        ? 1 / math.sqrt(1 + _supportSlope * _supportSlope)
        : 1.0;
    final supportX = _grounded ? _supportVelocity.x : 0.0;
    final target = !_grounded && axis == 0
        ? measuredVelocity.x
        : supportX + axis * speed * surfaceScale;
    final traction = support == null
        ? 1.0
        : (support.shape.friction / 0.6).clamp(0.08, 1.0);
    final acceleration = _grounded
        ? (axis == 0
                  ? GameConfig.groundDeceleration
                  : GameConfig.groundAcceleration) *
              traction
        : GameConfig.airAcceleration;
    final pushing = interactions.pushResistanceBody != null;
    final interactionForce = interactions.mode == InteractionMode.pulling
        ? GameConfig.pullForceNewtons
        : GameConfig.pushForceNewtons;
    final maxAcceleration = pushing
        ? math.min(acceleration, interactionForce / body.mass)
        : acceleration;
    final newX = _approach(measuredVelocity.x, target, maxAcceleration * dt);
    // Impulse is bounded by mass * acceleration * dt, so physical contacts
    // with a heavy crate or external body still resist the controller.
    body.applyLinearImpulse(
      Vector2((newX - measuredVelocity.x) * body.mass, 0),
    );
    if (_grounded) {
      body.linearVelocity = Vector2(
        body.linearVelocity.x,
        _supportVelocity.y + (newX - _supportVelocity.x) * _supportSlope,
      );
    } else if (measuredVelocity.y > 0) {
      body.applyForce(
        Vector2(
          0,
          body.mass *
              GameConfig.gravityMetersPerSecondSquared *
              (GameConfig.fallGravityMultiplier - 1),
        ),
      );
    }
    if (_jumping &&
        !_intent.isJumpHeld &&
        !_jumpCutApplied &&
        body.linearVelocity.y < 0) {
      body.linearVelocity = Vector2(
        body.linearVelocity.x,
        math.max(
          body.linearVelocity.y,
          -GameConfig.jumpTakeoffSpeed * GameConfig.jumpReleaseSpeedFactor,
        ),
      );
      _jumpCutApplied = true;
    }

    if (_anticipationTime > 0) {
      _anticipationTime -= dt;
      if (_anticipationTime <= 0) _launchJump();
    } else if (_timeSinceJumpPressed <= GameConfig.jumpBufferSeconds &&
        _timeSinceGrounded <= GameConfig.coyoteTimeSeconds &&
        !_jumping &&
        !_crouched) {
      _anticipationTime = GameConfig.jumpAnticipationSeconds;
      _timeSinceJumpPressed = double.infinity;
    }

    _animate(dt, measuredVelocity);
    _selectState();
    _previousVerticalSpeed = body.linearVelocity.y;
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
    _jumpCutApplied = false;
    _takeoff = 1;
    _timeSinceGrounded = double.infinity;
    _feet.reset();
  }

  void _updateCrouch() {
    final desired = _intent.isCrouchHeld && _grounded;
    if (desired == _crouched) return;
    if (!desired && !_standingClear()) return;
    _crouched = desired;
    _capsule.destroy();
    _capsule = _createCapsule(body);
  }

  bool _standingClear() {
    final top = body.position.y - GameConfig.playerHeight / 2;
    final currentTop =
        body.position.y +
        GameConfig.playerHeight / 2 -
        GameConfig.playerHeight * GameConfig.crouchHeightRatio;
    var clear = true;
    for (final x in [
      -GameConfig.playerWidth * 0.4,
      0.0,
      GameConfig.playerWidth * 0.4,
    ]) {
      world.castRay(
        Vector2(body.position.x + x, currentTop + 0.02),
        Vector2(0, top - currentTop - 0.04),
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
    _time += dt;
    RaincoatSilhouette.tick(dt);
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
    } else if (!pulling && _actualSpeed.abs() > 0.18) {
      _facing = _actualSpeed.sign;
    } else if (!pulling &&
        body.linearVelocity.x.abs() < 0.18 &&
        _intent.horizontalAxis != 0) {
      _facing = _intent.horizontalAxis.sign;
    }
    final walking = _grounded && _actualSpeed.abs() > 0.12;
    _runWeight = _approach(
      _runWeight,
      ((_actualSpeed.abs() - GameConfig.walkSpeedMetersPerSecond) /
              (GameConfig.moveSpeedMetersPerSecond -
                  GameConfig.walkSpeedMetersPerSecond))
          .clamp(0.0, 1.0),
      dt * 5,
    );
    if (walking) {
      _walkPhase += relativeTravel.length * (2 * math.pi / strideMeters);
    }
    final walkTarget = walking
        ? (_actualSpeed.abs() / GameConfig.walkSpeedMetersPerSecond).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    _walkWeight = _approach(_walkWeight, walkTarget, dt * 9);
    _airWeight = _approach(_airWeight, _grounded ? 0 : 1, dt * 12);
    _fallLean = _approach(
      _fallLean,
      (body.linearVelocity.y / 7).clamp(-1.0, 1.0),
      dt * 8,
    );
    final acceleration = (body.linearVelocity.x - measuredVelocity.x) / dt;
    _bodyLean = _approach(
      _bodyLean,
      (acceleration * _facing / 80).clamp(-0.08, 0.10),
      dt * 0.8,
    );
    _crouchWeight = _approach(_crouchWeight, _crouched ? 1 : 0, dt * 8);
    _landing = math.max(0, _landing - dt * 5);
    _takeoff = math.max(0, _takeoff - dt * 10);
    _feet.update(
      world: world,
      body: body,
      height: GameConfig.playerHeight,
      phase: _walkPhase,
      stride: strideMeters,
      facing: _facing,
      grounded: _grounded,
      speed: _actualSpeed,
      dt: dt,
    );
    if (_blinkRemaining > 0) {
      _blinkRemaining -= dt;
    } else if (_time >= _nextBlinkAt) {
      _blinkRemaining = 0.10;
      _nextBlinkAt = _time + 2.5 + (_time * 7.3) % 2.8;
    }
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
    } else if (_crouched) {
      state = CharacterState.crouching;
    } else if (_landing > 0.2) {
      state = CharacterState.landing;
    } else if (_intent.horizontalAxis != 0 &&
        _actualSpeed * _intent.horizontalAxis < -0.1) {
      state = CharacterState.turning;
    } else if (_intent.horizontalAxis == 0 && _actualSpeed.abs() > 0.1) {
      state = CharacterState.stopping;
    } else if (_intent.horizontalAxis != 0 && _actualSpeed.abs() < 0.6) {
      state = CharacterState.starting;
    } else if (_actualSpeed.abs() < 0.12) {
      state = CharacterState.idle;
    } else {
      state = _runWeight > 0.35
          ? CharacterState.running
          : CharacterState.walking;
    }
  }

  RaincoatPose get _pose {
    Offset local(Vector2 point) => Offset(
      (point.x - body.position.x) * _facing / GameConfig.playerHeight,
      (point.y - body.position.y) / GameConfig.playerHeight,
    );
    final targets = _feet.targets;
    final grip = interactions.gripWorld;
    return RaincoatPose(
      facing: _facing,
      walkPhase: _walkPhase,
      walk: _walkWeight,
      run: _runWeight,
      air: _grounded ? 0 : _airWeight,
      fallLean: _fallLean,
      blink: _blinkRemaining > 0,
      groundY: _grounded
          ? (_supportY - body.position.y) / GameConfig.playerHeight
          : 0.5,
      groundSlope: _grounded ? _supportSlope * _facing : 0,
      landing: _landing,
      takeoff: _takeoff,
      bodyLean: _bodyLean,
      anticipation: _anticipationTime > 0 ? 1 : 0,
      crouch: _crouchWeight,
      hanging: interactions.controlsMotion ? 1 : 0,
      frontFoot: _grounded ? local(targets[0]) : null,
      backFoot: _grounded ? local(targets[1]) : null,
      frontHand: grip == null ? null : local(grip),
      backHand: grip == null ? null : local(grip + Vector2(0, 0.02)),
      interactionWeight: _gripWeight,
    );
  }

  void knockDown() {
    if (_ragdoll != null || _recoveryPose != null) return;
    interactions.release();
    final rig = _figure.solve(_pose).translated(body.position);
    _ragdoll = CharacterRagdoll.activate(
      world: world.physicsWorld,
      pose: rig,
      velocity: body.linearVelocity,
      preset: _preset,
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
    if (!ragdoll.isStable) return;
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
    _walkWeight = 0;
    _airWeight = 0;
    _landing = 0;
    _crouchWeight = 0;
    if (_crouched) {
      _crouched = false;
      _capsule.destroy();
      _capsule = _createCapsule(body);
    }
    _grounded = true;
    _supportY = recovery.y + GameConfig.playerHeight / 2;
    _supportSlope = 0;
    _feet.reset();
    _feet.update(
      world: world,
      body: body,
      height: GameConfig.playerHeight,
      phase: 0,
      stride: strideMeters,
      facing: _facing,
      grounded: true,
      speed: 0,
      dt: dt,
    );
    state = CharacterState.recovering;
  }

  void selectPreset(int index) {
    if (index < 0 ||
        index >= CharacterPreset.values.length ||
        isRagdoll ||
        _recoveryPose != null) {
      return;
    }
    _preset = CharacterPreset.values[index];
    _figure = RaincoatSilhouette(
      height: GameConfig.playerHeight,
      preset: _preset,
    );
  }

  static double _approach(double value, double target, double step) =>
      (target - value).abs() <= step
      ? target
      : value + step * (target - value).sign;

  void teleportTo(Vector2 position) {
    interactions.release();
    _ragdoll?.destroy();
    _ragdoll = null;
    _recoveryPose = null;
    body.isEnabled = true;
    body.setTransform(position, const Rot.identity());
    body.linearVelocity = Vector2.zero();
    body.angularVelocity = 0;
    _lastPosition.setFrom(position);
    _feet.reset();
    _grounded = false;
    _jumping = false;
    _jumpCutApplied = false;
    _timeSinceGrounded = double.infinity;
    _timeSinceJumpPressed = double.infinity;
    _walkWeight = 0;
    _airWeight = 0;
    _landing = 0;
    _takeoff = 0;
    _anticipationTime = 0;
    _gripWeight = 0;
    _bodyLean = 0;
    _crouchWeight = 0;
    if (_crouched) {
      _crouched = false;
      _capsule.destroy();
      _capsule = _createCapsule(body);
    }
    _previousVerticalSpeed = 0;
    state = CharacterState.idle;
  }

  @override
  void render(Canvas canvas) {
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
      if (_grounded) {
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(0, _supportY - body.position.y + 0.01),
            width: 0.52,
            height: 0.07,
          ),
          Paint()..color = const Color(0x55000000),
        );
      }
      _figure.draw(canvas, _pose);
    }
    if (debugEnabled) renderDebug(canvas);
  }

  void renderDebug(Canvas canvas) {
    final line = Paint()
      ..color = const Color(0xFF58FFE2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.013;
    const radius = GameConfig.playerWidth / 2;
    final h =
        GameConfig.playerHeight *
        (_crouched ? GameConfig.crouchHeightRatio : 1);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-radius, GameConfig.playerHeight / 2 - h, radius * 2, h),
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
