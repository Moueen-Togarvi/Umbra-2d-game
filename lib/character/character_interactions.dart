import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';

import '../entities/physics_props.dart';
import '../config/game_config.dart';
import '../physics/collision_layers.dart';
import 'character_rig.dart';
import 'rope_grips.dart';

enum InteractionMode { none, pushing, pulling, hanging, swinging, climbing }

/// Owns interaction constraints, with no dependency on the player controller.
/// Call after the world step, before locomotion. A constrained hang/swing/climb
/// owns movement; pulling leaves bounded ground locomotion with the controller.
///
/// As in LIMBO, ledges and ropes are caught automatically when the child is
/// in the air and reaches them; only grabbing an object needs the action
/// button. Jump kicks off a rope or climbs a ledge; down lets go.
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

  /// How far the arms currently brace out in front of the body, metres:
  /// the push reach extends past it.
  double braceLength = 0;
  MotorJoint? _motor;
  DistanceJoint? _ropeHand;

  /// Where on the body the rope is held, in body-local metres. A rope caught
  /// low is drawn in until it runs down his front, held at the head and
  /// the chest.
  Vector2? _ropeHold;
  Vector2? _ropeHoldTarget;
  double _ropeFacing = 1;
  static const double _ropePullSpeed = 1.1;

  /// Where along the rope each hand holds, climbing hand over hand.
  final RopeGrips ropeGrips = RopeGrips();

  /// +1 climbing up the rope, -1 down, 0 holding still.
  double ropeClimb = 0;
  double _ropeLetGo = 0;
  double _ropeClimbClock = 0;
  Vector2? _crateGripLocal;
  Body? _ledgeBody;
  Vector2? _ledgeLocal;
  double _ledgeFacing = 1;

  /// Climbing up onto a ledge: how far through it (0 to 1), where he
  /// started, and the collision filters his shapes had before it (the
  /// climb passes through the corner, so it switches them off).
  double _climbProgress = 0;
  final Vector2 _climbStart = Vector2.zero();
  final List<(Shape, Filter)> _climbFilters = [];
  bool releasedThisStep = false;
  bool _requireInteractRelease = false;

  /// After letting go of a ledge or rope, the hands stay off it for a moment
  /// so the child does not catch the same hold again on the way down.
  double _catchCooldown = 0;
  static const double _catchCooldownSeconds = 0.4;

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
    // On a rope he keeps facing the way he caught it, whichever way it swings.
    if (attachedRope != null) return _ropeFacing;
    return null;
  }

  Vector2? get gripWorld {
    if (attachedRope?.isReady ?? false) return attachedRope!.grip;
    if (grabbedCrate?.isReady ?? false) {
      return grabbedCrate!.body.worldPoint(_crateGripLocal!);
    }
    if (_ledgeBody?.isValid ?? false) {
      final grip = _ledgeBody!.worldPoint(_ledgeLocal!);
      if (mode != InteractionMode.climbing) return grip;
      // Climbing, the hands hold the corner while he pulls up, then slide
      // onto the top beside him and press down to push him over it.
      final double press = _smoothstep((_climbProgress - 0.55) / 0.3);
      final brace = Vector2(
        playerBody.position.x + _ledgeFacing * 0.07,
        grip.y,
      );
      return grip + (brace - grip) * press;
    }
    return _pushGrip?.clone();
  }

  /// How far through climbing onto a ledge he is, 0 to 1, or null.
  double? get climbProgress =>
      mode == InteractionMode.climbing ? _climbProgress : null;

  /// Climbing onto a ledge, where each foot (front, back) is planted on
  /// its top, or null where that foot is not yet up: the front knee comes
  /// up onto it first, the back foot follows, and both walk in to stand.
  List<Vector2?>? get climbFeet {
    if (mode != InteractionMode.climbing || !(_ledgeBody?.isValid ?? false)) {
      return null;
    }
    final corner = _ledgeBody!.worldPoint(_ledgeLocal!);
    final double p = _climbProgress;
    final double f = _ledgeFacing;
    final double walkIn = _smoothstep((p - 0.75) / 0.25);
    final double stand = corner.x + f * (width / 2 + 0.14);
    Vector2 on(double x) => Vector2(x, corner.y);
    return [
      p >= 0.45
          ? on(_mix(corner.x + f * 0.10, stand + f * 0.09, walkIn))
          : null,
      p >= 0.72
          ? on(_mix(corner.x + f * 0.03, stand - f * 0.08, walkIn))
          : null,
    ];
  }

  static double _smoothstep(double t) {
    final double x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  Vector2? _pushGrip;

  /// On a rope, the front and back hands' grips on it, world metres. A hand
  /// moving to a new grip comes off the rope towards the body.
  List<Vector2>? get ropeHands {
    final rope = attachedRope;
    if (rope == null || !rope.isReady) return null;
    return [
      for (var i = 0; i < 2; i++)
        rope.pointAt(ropeGrips.arcs[i]) +
            Vector2(-_ropeFacing * 0.045 * ropeGrips.lift(i), 0),
    ];
  }

  /// On a rope with enough of it hanging below him, where his feet clamp
  /// it: in front of the shins, the knees bent, pumping as he climbs.
  Vector2? get ropeFeet {
    final rope = attachedRope;
    if (rope == null || !rope.isReady) return null;
    if (rope.length - rope.holdLength < 0.95) return null;
    final double pump = ropeClimb == 0
        ? 0
        : 0.5 + 0.5 * math.sin(_ropeClimbClock * 2 * math.pi * 1.6);
    return playerBody.worldPoint(
      Vector2(_ropeFacing * height * 0.12, height * (0.36 - 0.07 * pump)),
    );
  }

  void update(
    double dt, {
    required double axis,
    required double facing,
    required bool grounded,
    required bool interactPressed,
    required bool interactHeld,
    required bool jumpPressed,
    bool downHeld = false,
    bool upHeld = false,
  }) {
    releasedThisStep = false;
    _catchCooldown = math.max(0, _catchCooldown - dt);
    if (!interactHeld) _requireInteractRelease = false;
    pushResistanceBody = null;
    _pushGrip = null;
    if (!playerBody.isValid || !playerBody.isEnabled) {
      release();
      return;
    }
    if (mode == InteractionMode.pushing) mode = InteractionMode.none;

    if (mode == InteractionMode.swinging) {
      final rope = attachedRope;
      // Down at the bottom of the rope, held a moment, lets go.
      final bool atBottom =
          rope != null && rope.holdLength >= rope.length - 0.1 - 1e-6;
      _ropeLetGo = downHeld && atBottom ? _ropeLetGo + dt : 0;
      if (!(rope?.isReady ?? false) ||
          jumpPressed ||
          _ropeLetGo >= GameConfig.ropeLetGoSeconds) {
        release();
        releasedThisStep = true;
        _catchCooldown = _catchCooldownSeconds;
        // Kicking off with jump is a real push from the legs against the
        // rope: the swing's momentum is kept and some lift is added.
        if (jumpPressed) {
          playerBody.applyLinearImpulse(
            Vector2(0, -GameConfig.ropeJumpSpeed * playerBody.mass),
          );
        }
      } else {
        _settleRopeHold(dt);
        // Climbing: up and down change how much rope is above the hold.
        ropeClimb = 0;
        if (upHeld && rope!.holdLength > SwingRope.minimumHold + 1e-6) {
          rope.holdLength -= GameConfig.ropeClimbUpSpeed * dt;
          ropeClimb = 1;
        } else if (downHeld && !atBottom) {
          rope!.holdLength = math.min(
            rope.length - 0.1,
            rope.holdLength + GameConfig.ropeClimbDownSpeed * dt,
          );
          ropeClimb = -1;
        }
        if (ropeClimb != 0) _ropeClimbClock += dt;
        ropeGrips.update(
          rope!.holdLength,
          dt,
          top: SwingRope.minimumHold - 0.25,
          end: rope.length - 0.03,
        );
        rope.clamp = ropeFeet;
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
      final bool awayFromWall =
          mode == InteractionMode.hanging && axis * _ledgeFacing < -0.5;
      if (!(_ledgeBody?.isValid ?? false) || downHeld || awayFromWall) {
        release();
        releasedThisStep = true;
        _catchCooldown = _catchCooldownSeconds;
      } else if (mode == InteractionMode.hanging &&
          (jumpPressed || axis * _ledgeFacing > 0.5)) {
        _beginClimb();
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

    // Holding the action button near an object takes hold of it.
    if (grounded &&
        !_requireInteractRelease &&
        (interactPressed || interactHeld)) {
      // Far enough for a crate he has just been pushing at arm's length.
      final crateHit = _crateInReach(
        facing,
        width / 2 + GameConfig.pushBraceMeters + 0.06,
      );
      if (crateHit != null) {
        _grabCrate(crateHit);
        return;
      }
    }

    // In the air, ropes and ledges within reach are caught automatically.
    // A ledge is only caught when the child is not steering away from it.
    if (!grounded && _catchCooldown <= 0 && !downHeld) {
      final rope = _ropeInReach(facing);
      if (rope != null) {
        _grabRope(rope.$1, rope.$2, rope.$3, facing);
        return;
      }
      if (axis * facing >= 0 && _grabLedge(facing)) return;
    }

    if (grounded && axis != 0) {
      final crateHit = _crateInReach(
        axis.sign,
        width / 2 + braceLength + 0.025,
      );
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

  /// A shoulder's world position when standing upright, from the rig.
  Vector2 _shoulder(double facing, {required bool front}) {
    final local = CharacterRig.restShoulder(front: front);
    return playerBody.position +
        Vector2(local.x * facing * height, local.y * height);
  }

  /// [slack] allows for the shoulders shrugging up and the arms stretching
  /// as the hands close on a hold that is just out of reach.
  bool _handCanReach(Vector2 grip, double facing, {double slack = 0.025}) =>
      (grip - _shoulder(facing, front: true)).length <=
      height * CharacterRig.armReach + slack;

  /// Both hands on the grip, allowing for the body leaning towards it.
  bool _crateHandsCanReach(Vector2 grip, double facing) {
    final reach = height * CharacterRig.armReach + 0.03;
    final lean = Vector2(facing * height * 0.06, 0);
    return (grip - _shoulder(facing, front: true) - lean).length < reach &&
        (grip + Vector2(0, 0.02) - _shoulder(facing, front: false) - lean)
                .length <
            reach;
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

  /// The nearest point of any rope, anywhere along it, from overhead down
  /// to the shoulders, within the arms' reach and not behind a wall.
  (SwingRope, Vector2, double)? _ropeInReach(double facing) {
    final shoulder = _shoulder(facing, front: true);
    // Reaching up for a rope the shoulders shrug, which buys a little reach.
    final double reach =
        height * (CharacterRig.armReach + CharacterRig.hangShrug * 0.7);
    (SwingRope, Vector2, double)? nearest;
    var distance = reach;
    final seen = <SwingRope>{};
    // A rope's bodies are its anchor and its bob; anywhere between them is
    // rope, so look for either within a rope's length.
    for (final shape in world.overlapAabb(
      Aabb(
        shoulder - Vector2(reach + 0.5, 8),
        shoulder + Vector2(reach + 0.5, reach),
      ),
    )) {
      final data = shape.body.userData;
      if (data is! SwingRope || !data.isReady || !seen.add(data)) continue;
      final (point, arc) = data.nearestOnRope(
        shoulder,
        from: SwingRope.minimumHold,
      );
      final localGrip = playerBody.localPoint(point);
      if (localGrip.y < -height * 0.45 || localGrip.y > -height * 0.05) {
        continue;
      }
      final separation = (point - shoulder).length;
      if (separation >= distance ||
          (point - _shoulder(facing, front: false)).length >= reach) {
        continue;
      }
      final obstruction = _solidRay(shoulder, point - shoulder);
      if (obstruction == null || obstruction.shape.body.userData == data) {
        nearest = (data, point, arc);
        distance = separation;
      }
    }
    return nearest;
  }

  void _grabRope(SwingRope rope, Vector2 point, double arc, double facing) {
    attachedRope = rope;
    _ropeFacing = facing;
    rope.catchAt(point, arc);
    // Capture the actual grip instead of yanking the body to an imagined
    // hold: entry keeps its position and velocity. The hold then moves to
    // the front of the head over a moment, which the solver turns into the
    // body settling below and behind the rope, hugging it.
    _ropeHold = playerBody.localPoint(rope.grip);
    _ropeHoldTarget = Vector2(facing * height * 0.14, -height * 0.30);
    ropeGrips.reset(rope.holdLength);
    ropeClimb = 0;
    _ropeLetGo = 0;
    _attachRopeHand();
    mode = InteractionMode.swinging;
  }

  void _attachRopeHand() {
    if (_ropeHand?.isValid ?? false) _ropeHand!.destroy();
    _ropeHand = world.physicsWorld.createDistanceJoint(
      DistanceJointDef(
        bodyA: attachedRope!.bob,
        bodyB: playerBody,
        localAnchorB: _ropeHold!,
        length: 0.015,
        collideConnected: false,
      ),
    );
  }

  void _settleRopeHold(double dt) {
    final hold = _ropeHold, target = _ropeHoldTarget;
    if (hold == null || target == null) return;
    final Vector2 delta = target - hold;
    if (delta.length < 1e-4) return;
    final double step = math.min(delta.length, _ropePullSpeed * dt);
    hold.add(delta.normalized() * step);
    _attachRopeHand();
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
    if (!_handCanReach(ledge, facing, slack: 0.13)) return false;
    final stand =
        ledge + Vector2(facing * (width / 2 + 0.14), -height / 2 - 0.035);
    if (!_clearAt(stand)) return false;
    _ledgeBody = wall.shape.body;
    _ledgeLocal = _ledgeBody!.localPoint(ledge);
    _ledgeFacing = facing;
    final hang = ledge + Vector2(-facing * (width / 2 + 0.04), height * 0.35);
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
    final Filter mine = playerBody.shapes.first.filter;
    for (final shape in world.overlapAabb(bounds)) {
      if (shape.body == playerBody || shape.isSensor) continue;
      // Only what he would bump into is in the way: not a rope's end
      // swinging past, a chain link or a limb of something limp.
      final Filter theirs = shape.filter;
      if ((theirs.maskBits & mine.categoryBits) == 0 ||
          (theirs.categoryBits & mine.maskBits) == 0) {
        continue;
      }
      if (shape.aabb.overlaps(bounds)) return false;
    }
    return true;
  }

  /// Climbing onto a ledge is a short, scripted mantle — pull up with the
  /// chest over the edge, a knee onto the top, stand — along a smooth path
  /// that never rises above standing height. The path passes through the
  /// corner, so the body's collision with the ground and with props is off
  /// until he stands, and gravity with it.
  void _beginClimb() {
    if (_motor?.isValid ?? false) _motor!.destroy();
    _motor = null;
    mode = InteractionMode.climbing;
    _climbProgress = 0;
    _climbStart.setFrom(playerBody.position);
    _climbFilters.clear();
    for (final shape in playerBody.shapes) {
      final filter = shape.filter;
      _climbFilters.add((shape, filter));
      shape.filter = Filter(
        categoryBits: filter.categoryBits,
        maskBits: filter.maskBits & ~CollisionLayers.solid,
        groupIndex: filter.groupIndex,
      );
    }
    playerBody.gravityScale = 0;
  }

  /// Puts the body's collision and gravity back after a climb.
  void _endClimb() {
    for (final (shape, filter) in _climbFilters) {
      if (shape.isValid) shape.filter = filter;
    }
    _climbFilters.clear();
    if (playerBody.isValid) playerBody.gravityScale = 1;
  }

  /// Where the body's centre is [p] of the way through the climb.
  Vector2 _climbPath(double p, Vector2 corner) {
    final double f = _ledgeFacing;
    final points = [
      _climbStart,
      // Pulled up: chest over the edge, legs against the wall.
      Vector2(corner.x - f * (width / 2 + 0.02), corner.y - height * 0.05),
      // A knee on the top, crouched.
      Vector2(corner.x + f * 0.12, corner.y - height / 2 + 0.18),
      // Standing.
      _standOn(corner),
    ];
    const times = [0.0, 0.45, 0.75, 1.0];
    final double e = _smoothstep(p);
    var segment = 0;
    while (segment < 2 && e > times[segment + 1]) {
      segment++;
    }
    final double t =
        (e - times[segment]) / (times[segment + 1] - times[segment]);
    // A Catmull-Rom curve through the four points: smooth through each.
    Vector2 at(int i) => points[i.clamp(0, 3)];
    final p0 = at(segment - 1), p1 = at(segment);
    final p2 = at(segment + 1), p3 = at(segment + 2);
    final double t2 = t * t, t3 = t2 * t;
    return (p1 * 2 +
            (p2 - p0) * t +
            (p0 * 2 - p1 * 5 + p2 * 4 - p3) * t2 +
            (p1 * 3 - p0 - p2 * 3 + p3) * t3) *
        0.5;
  }

  Vector2 _standOn(Vector2 corner) => Vector2(
    corner.x + _ledgeFacing * (width / 2 + 0.14),
    corner.y - height / 2 - 0.015,
  );

  void _advanceClimb(double dt) {
    final corner = _ledgeBody!.worldPoint(_ledgeLocal!);
    // Something has moved into where he would stand: while he is still
    // below the top, he lets go.
    if (_climbProgress < 0.7 && !_clearAt(_standOn(corner))) {
      release();
      releasedThisStep = true;
      return;
    }
    _climbProgress = math.min(1, _climbProgress + dt / GameConfig.climbSeconds);
    if (_climbProgress >= 1) {
      release();
      playerBody.setTransform(_standOn(corner), const Rot.identity());
      playerBody.linearVelocity = Vector2.zero();
      return;
    }
    final next = _climbPath(
      math.min(1, _climbProgress + dt / GameConfig.climbSeconds),
      corner,
    );
    playerBody.linearVelocity = (next - playerBody.position) / dt;
  }

  /// Destroying constraints preserves the body's physical release velocity.
  void release() {
    attachedRope?.letGo();
    _endClimb();
    ropeClimb = 0;
    _ropeLetGo = 0;
    if (_motor?.isValid ?? false) _motor!.destroy();
    if (_ropeHand?.isValid ?? false) _ropeHand!.destroy();
    _motor = null;
    _ropeHand = null;
    _ropeHold = null;
    _ropeHoldTarget = null;
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
