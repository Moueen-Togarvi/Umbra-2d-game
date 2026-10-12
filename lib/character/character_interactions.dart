import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';

import '../entities/physics_props.dart';
import '../config/game_config.dart';

enum InteractionMode { none, pushing, pulling, hanging, swinging, climbing }

/// Owns interaction constraints, with no dependency on the player controller.
/// Call after the world step, before locomotion. A constrained hang/swing/climb
/// owns movement; pulling leaves bounded ground locomotion with the controller.
class CharacterInteractions {
  CharacterInteractions({
    required this.world,
    required this.playerBody,
    required this.width,
    required this.height,
    this.pullForce = GameConfig.pullForceNewtons,
    this.swingAcceleration = GameConfig.swingAcceleration,
  });

  final Forge2DWorld world;
  final Body playerBody;
  final double width, height, pullForce, swingAcceleration;
  InteractionMode mode = InteractionMode.none;
  PhysicsCrate? grabbedCrate;
  SwingRope? attachedRope;
  Body? pushResistanceBody;
  MotorJoint? _motor;
  DistanceJoint? _ropeHand;
  Vector2? _crateGripLocal;
  Body? _ledgeBody;
  Vector2? _ledgeLocal;
  double _ledgeFacing = 1;
  int _climbStage = 0;
  double _climbTime = 0;
  bool releasedThisStep = false;
  bool _requireInteractRelease = false;

  bool get controlsMotion =>
      mode == InteractionMode.hanging ||
      mode == InteractionMode.swinging ||
      mode == InteractionMode.climbing;

  /// Pulling backs away while the chest and hands still face the held object.
  double? get facingOverride {
    if (grabbedCrate?.isReady ?? false) {
      return (grabbedCrate!.body.position.x - playerBody.position.x).sign;
    }
    if (_ledgeBody?.isValid ?? false) return _ledgeFacing;
    return null;
  }

  Vector2? get gripWorld {
    if (attachedRope?.isReady ?? false) return attachedRope!.grip;
    if (grabbedCrate?.isReady ?? false) {
      return grabbedCrate!.body.worldPoint(_crateGripLocal!);
    }
    if (_ledgeBody?.isValid ?? false) {
      final grip = _ledgeBody!.worldPoint(_ledgeLocal!);
      // Hands release the rim once the torso rises past arm reach.
      return mode == InteractionMode.climbing &&
              !_handCanReach(grip, _ledgeFacing)
          ? null
          : grip;
    }
    return _pushGrip?.clone();
  }

  Vector2? _pushGrip;

  void update(
    double dt, {
    required double axis,
    required double facing,
    required bool grounded,
    required bool interactPressed,
    required bool interactHeld,
    required bool jumpPressed,
    bool crouchHeld = false,
  }) {
    releasedThisStep = false;
    if (!interactHeld) _requireInteractRelease = false;
    pushResistanceBody = null;
    _pushGrip = null;
    if (!playerBody.isValid || !playerBody.isEnabled) {
      release();
      return;
    }
    if (mode == InteractionMode.pushing) mode = InteractionMode.none;

    if (mode == InteractionMode.swinging) {
      if (!(attachedRope?.isReady ?? false) ||
          !interactHeld ||
          jumpPressed ||
          crouchHeld) {
        release();
        releasedThisStep = true;
        if (interactHeld) _requireInteractRelease = true;
      } else {
        final radius = playerBody.position - attachedRope!.anchor;
        final tangent = Vector2(radius.y, -radius.x)..normalize();
        if (playerBody.linearVelocity.length < 8) {
          playerBody.applyForce(
            tangent * (axis * playerBody.mass * swingAcceleration),
          );
        }
      }
      return;
    }

    if (mode == InteractionMode.hanging || mode == InteractionMode.climbing) {
      if (!(_ledgeBody?.isValid ?? false) || crouchHeld || !interactHeld) {
        release();
        releasedThisStep = true;
        if (interactHeld) _requireInteractRelease = true;
      } else if (mode == InteractionMode.hanging &&
          (jumpPressed || axis * _ledgeFacing > 0.5)) {
        mode = InteractionMode.climbing;
        _climbStage = 0;
        _climbTime = 0;
      }
      if (mode == InteractionMode.climbing) _advanceClimb(dt);
      return;
    }

    if (mode == InteractionMode.pulling) {
      if (!(grabbedCrate?.isReady ?? false) ||
          !interactHeld ||
          jumpPressed ||
          !_crateHandsCanReach(gripWorld!, facingOverride ?? facing)) {
        release();
        releasedThisStep = true;
        if (interactHeld) _requireInteractRelease = true;
      } else {
        pushResistanceBody = grabbedCrate!.body;
      }
      return;
    }

    if (!_requireInteractRelease &&
        (interactPressed || (interactHeld && !grounded))) {
      final crateHit = _crateInReach(facing, width / 2 + 0.13);
      if (crateHit != null && grounded) {
        _grabCrate(crateHit);
        return;
      }
      final rope = _ropeInReach(facing);
      if (rope != null) {
        _grabRope(rope);
        return;
      }
      if (!grounded && _grabLedge(facing)) return;
    }

    if (grounded && axis != 0) {
      final crateHit = _crateInReach(axis.sign, width / 2 + 0.025);
      if (crateHit != null) {
        mode = InteractionMode.pushing;
        pushResistanceBody = crateHit.shape.body;
        _pushGrip = crateHit.point;
      }
    }
  }

  RayHit? _solidRay(Vector2 origin, Vector2 translation) {
    RayHit? closest;
    world.castRay(origin, translation, (hit) {
      if (hit.shape.body == playerBody || hit.shape.isSensor) return -1;
      if (closest == null || hit.fraction < closest!.fraction) closest = hit;
      return hit.fraction;
    });
    return closest;
  }

  RayHit? _crateInReach(double direction, double reach) {
    final hit = _solidRay(
      playerBody.position + Vector2(0, height * 0.03),
      Vector2(direction * reach, 0),
    );
    final crate = hit?.shape.body.userData;
    if (crate is! PhysicsCrate) return null;
    // A shoulder-height grip near the crate's upper rim lets both arms carry
    // the load. A second ray checks this actual point rather than inventing it.
    final gripY = math.max(
      playerBody.position.y - height * 0.065,
      crate.body.position.y - crate.size.y / 2 + 0.04,
    );
    final upperHit = _solidRay(
      Vector2(playerBody.position.x, gripY),
      Vector2(direction * reach, 0),
    );
    return upperHit?.shape.body == crate.body &&
            _crateHandsCanReach(upperHit!.point, direction)
        ? upperHit
        : null;
  }

  bool _handCanReach(Vector2 grip, double facing) {
    final shoulder =
        playerBody.position + Vector2(facing * height * 0.07, -height * 0.13);
    return (grip - shoulder).length <= height * 0.30 + 0.025;
  }

  bool _crateHandsCanReach(Vector2 grip, double facing) {
    final centre = playerBody.position;
    final front = centre + Vector2(facing * height * 0.05, -height * 0.13);
    final back = centre + Vector2(-facing * height * 0.05, -height * 0.13);
    return (grip - front).length < height * 0.30 + 0.012 &&
        (grip + Vector2(0, 0.02) - back).length < height * 0.30 + 0.012;
  }

  void _grabCrate(RayHit hit) {
    grabbedCrate = hit.shape.body.userData! as PhysicsCrate;
    _crateGripLocal = grabbedCrate!.body.localPoint(hit.point);
    _motor = world.physicsWorld.createMotorJoint(
      MotorJointDef(
        bodyA: playerBody,
        bodyB: grabbedCrate!.body,
        linearOffset: playerBody.localPoint(grabbedCrate!.body.position),
        maxForce: pullForce,
        maxTorque: 35,
        correctionFactor: 0.15,
        collideConnected: true,
      ),
    );
    mode = InteractionMode.pulling;
  }

  SwingRope? _ropeInReach(double facing) {
    final hand = playerBody.position - Vector2(0, height * 0.40);
    SwingRope? nearest;
    var distance = 0.52;
    for (final shape in world.overlapAabb(
      Aabb(hand - Vector2.all(0.55), hand + Vector2.all(0.55)),
    )) {
      final data = shape.body.userData;
      if (data is! SwingRope || !data.isReady) continue;
      final separation = (data.grip - hand).length;
      final obstruction = _solidRay(hand, data.grip - hand);
      final localGrip = playerBody.localPoint(data.grip);
      // Both arms need room for the short constraint gap and pose blending.
      final reachable =
          localGrip.y < -height * 0.38 &&
          localGrip.y > -height * 0.48 &&
          [-1.0, 1.0].every(
            (side) =>
                (localGrip - Vector2(side * height * 0.05, -height * 0.18))
                    .length <
                height * 0.30 - 0.018,
          );
      if (separation < distance &&
          reachable &&
          (obstruction?.shape.body.userData == data ||
              (obstruction == null && separation < 0.12))) {
        nearest = data;
        distance = separation;
      }
    }
    return nearest;
  }

  void _grabRope(SwingRope rope) {
    attachedRope = rope;
    // Capture the actual grip instead of fixing an imagined overhead hand and
    // adding the initial gap as a second rope. Entry keeps its position and
    // velocity; the solver settles only this short connection afterwards.
    final localHand = playerBody.localPoint(rope.grip);
    _ropeHand = world.physicsWorld.createDistanceJoint(
      DistanceJointDef(
        bodyA: rope.bob,
        bodyB: playerBody,
        localAnchorB: localHand,
        length: 0.015,
        collideConnected: false,
      ),
    );
    mode = InteractionMode.swinging;
  }

  bool _grabLedge(double facing) {
    if (playerBody.linearVelocity.y < -2) return false;
    final position = playerBody.position;
    final wall = _solidRay(
      position - Vector2(0, height * 0.10),
      Vector2(facing * (width / 2 + 0.35), 0),
    );
    if (wall == null ||
        wall.normal.x * facing > -0.75 ||
        wall.shape.body.type == BodyType.dynamic ||
        wall.shape.body.userData is SwingRope) {
      return false;
    }
    final top = _solidRay(
      Vector2(wall.point.x + facing * 0.12, position.y - height * 0.80),
      Vector2(0, height * 0.85),
    );
    if (top == null ||
        top.shape.body != wall.shape.body ||
        top.normal.y > -0.9) {
      return false;
    }
    final ledge = Vector2(wall.point.x, top.point.y);
    if (!_handCanReach(ledge, facing)) return false;
    final stand =
        ledge + Vector2(facing * (width / 2 + 0.14), -height / 2 - 0.035);
    if (!_clearAt(stand)) return false;
    _ledgeBody = wall.shape.body;
    _ledgeLocal = _ledgeBody!.localPoint(ledge);
    _ledgeFacing = facing;
    final hang = ledge + Vector2(-facing * (width / 2 + 0.04), height * 0.39);
    _motor = world.physicsWorld.createMotorJoint(
      MotorJointDef(
        bodyA: _ledgeBody!,
        bodyB: playerBody,
        linearOffset: _ledgeBody!.localPoint(hang),
        maxForce: playerBody.mass * world.gravity.length * 3,
        maxTorque: 0,
        correctionFactor: 0.18,
        collideConnected: true,
      ),
    );
    mode = InteractionMode.hanging;
    return true;
  }

  bool _clearAt(Vector2 centre) {
    final extent = Vector2(width / 2 - 0.025, height / 2 - 0.025);
    final bounds = Aabb(centre - extent, centre + extent);
    for (final shape in world.overlapAabb(bounds)) {
      if (shape.body == playerBody || shape.isSensor) continue;
      if (shape.aabb.overlaps(bounds)) return false;
    }
    return true;
  }

  bool _clearPath(Vector2 from, Vector2 to) {
    final delta = to - from;
    final samples = math.max(1, (delta.length / 0.06).ceil());
    for (var i = 1; i <= samples; i++) {
      if (!_clearAt(from + delta * (i / samples))) return false;
    }
    return true;
  }

  void _advanceClimb(double dt) {
    _climbTime += dt;
    final ledge = _ledgeBody!.worldPoint(_ledgeLocal!);
    final outsideX = ledge.x - _ledgeFacing * (width / 2 + 0.04);
    final insideX = ledge.x + _ledgeFacing * (width / 2 + 0.14);
    final raisedY = ledge.y - height / 2 - 0.08;
    final target = switch (_climbStage) {
      0 => Vector2(outsideX, raisedY),
      1 => Vector2(insideX, raisedY),
      _ => Vector2(insideX, ledge.y - height / 2 - 0.015),
    };
    if (_climbTime > 3 || !_clearPath(playerBody.position, target)) {
      release();
      releasedThisStep = true;
      return;
    }
    final currentTarget = _ledgeBody!.worldPoint(_motor!.linearOffset);
    final delta = target - currentTarget;
    final distance = delta.length;
    final next = distance == 0
        ? target
        : currentTarget + delta * (math.min(distance, 2.3 * dt) / distance);
    _motor!.linearOffset = _ledgeBody!.localPoint(next);
    final velocity = playerBody.linearVelocity;
    if (velocity.length > 3.3) {
      playerBody.linearVelocity = velocity.normalized() * 3.3;
    }
    if ((playerBody.position - target).length < 0.065) {
      if (_climbStage < 2) {
        _climbStage++;
      } else {
        release();
        playerBody.linearVelocity = Vector2.zero();
      }
    }
  }

  /// Destroying constraints preserves the body's physical release velocity.
  void release() {
    if (_motor?.isValid ?? false) _motor!.destroy();
    if (_ropeHand?.isValid ?? false) _ropeHand!.destroy();
    _motor = null;
    _ropeHand = null;
    grabbedCrate = null;
    attachedRope = null;
    _crateGripLocal = null;
    _ledgeBody = null;
    _ledgeLocal = null;
    _pushGrip = null;
    pushResistanceBody = null;
    mode = InteractionMode.none;
  }

  void dispose() => release();
}
