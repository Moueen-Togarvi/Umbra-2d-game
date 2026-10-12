import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../physics/collision_layers.dart';
import 'character_preset.dart';
import 'character_rig.dart';

enum RagdollPart {
  head,
  torso,
  pelvis,
  frontUpperArm,
  frontForearm,
  backUpperArm,
  backForearm,
  frontThigh,
  frontShin,
  frontFoot,
  backThigh,
  backShin,
  backFoot,
}

/// Passive articulated physics. The controller must disable its capsule
/// before stepping this rig, and restore it only after a validated recovery.
class CharacterRagdoll {
  CharacterRagdoll._({required this.world, required this.initialPose});

  static int _nextGroup = -1;
  final World world;
  final CharacterRigPose initialPose;
  final Map<RagdollPart, Body> bodies = {};
  final List<RevoluteJoint> joints = [];
  final Map<RigJoint, (Body, Vector2)> _bindings = {};
  double _elapsed = 0;
  double _stableFor = 0;
  bool _destroyed = false;

  static CharacterRagdoll activate({
    required World world,
    required CharacterRigPose pose,
    required Vector2 velocity,
    CharacterPreset preset = CharacterPreset.raincoat,
    double totalMassKilograms = GameConfig.playerMassKilograms,
    Object? userData,
  }) {
    final ragdoll = CharacterRagdoll._(world: world, initialPose: pose);
    final double h = pose.height;
    final int group = _nextGroup--;
    if (_nextGroup < -32000) _nextGroup = -1;

    ShapeDef material(double mass, double area) => ShapeDef(
      density: mass * (totalMassKilograms / 20.4) / area,
      material: SurfaceMaterial(friction: 0.55, restitution: 0),
      filter: Filter(
        categoryBits: CollisionLayers.ragdoll,
        maskBits:
            CollisionLayers.solid |
            CollisionLayers.ragdoll |
            CollisionLayers.sensor,
        groupIndex: group,
      ),
      enableSensorEvents: true,
      enableContactEvents: true,
      enableHitEvents: true,
    );

    Body segment(
      RagdollPart part,
      Vector2 a,
      Vector2 b,
      double radius,
      double mass,
    ) {
      final double length = math.max((b - a).length, radius * 2 + 0.002);
      final double angle = math.atan2(b.y - a.y, b.x - a.x) - math.pi / 2;
      final body = world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: (a + b) * 0.5,
          rotation: Rot.fromAngle(angle),
          linearVelocity: velocity.clone(),
          linearDamping: 0.10,
          angularDamping: 1.5,
          isBullet: true,
          userData: userData,
          name: 'ragdoll-${part.name}',
        ),
      );
      body.createShape(
        Capsule(
          center1: Vector2(0, -length / 2 + radius),
          center2: Vector2(0, length / 2 - radius),
          radius: radius,
        ),
        material(
          mass,
          math.pi * radius * radius + 2 * radius * (length - 2 * radius),
        ),
      );
      ragdoll.bodies[part] = body;
      return body;
    }

    void bind(RigJoint node, Body body) =>
        ragdoll._bindings[node] = (body, body.localPoint(pose[node]));

    final head = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: pose[RigJoint.head].clone(),
        rotation: Rot.fromAngle(pose.headAngle),
        linearVelocity: velocity.clone(),
        linearDamping: 0.10,
        angularDamping: 1.5,
        isBullet: true,
        userData: userData,
        name: 'ragdoll-head',
      ),
    );
    final double headRadius = h * 0.12;
    head.createShape(
      Circle(radius: headRadius),
      material(2.4, math.pi * headRadius * headRadius),
    );
    ragdoll.bodies[RagdollPart.head] = head;
    bind(RigJoint.head, head);
    final torso = segment(
      RagdollPart.torso,
      pose[RigJoint.neck],
      pose[RigJoint.waist],
      h * 0.064,
      6,
    );
    final pelvis = segment(
      RagdollPart.pelvis,
      pose[RigJoint.waist],
      pose[RigJoint.pelvis],
      h * 0.064,
      3,
    );
    for (final node in [
      RigJoint.neck,
      RigJoint.chest,
      RigJoint.waist,
      RigJoint.frontShoulder,
      RigJoint.backShoulder,
    ]) {
      bind(node, torso);
    }
    for (final node in [RigJoint.pelvis, RigJoint.frontHip, RigJoint.backHip]) {
      bind(node, pelvis);
    }

    void hinge(
      Body a,
      Body b,
      Vector2 anchor,
      double lower,
      double upper, {
      bool relativeToPose = false,
    }) {
      final reference = relativeToPose ? _angle(b.angle - a.angle) : 0.0;
      ragdoll.joints.add(
        world.createRevoluteJoint(
          RevoluteJointDef(
            bodyA: a,
            bodyB: b,
            localAnchorA: a.localPoint(anchor),
            localAnchorB: b.localPoint(anchor),
            referenceAngle: reference,
            enableLimit: true,
            lowerAngle: lower,
            upperAngle: upper,
            // No balance motors: this is a passive knockdown rig.
            enableMotor: false,
            collideConnected: false,
          ),
        ),
      );
    }

    hinge(torso, head, pose[RigJoint.neck], -0.65, 0.65, relativeToPose: true);
    hinge(
      torso,
      pelvis,
      pose[RigJoint.waist],
      -0.40,
      0.40,
      relativeToPose: true,
    );

    for (final front in const [false, true]) {
      final shoulder = front ? RigJoint.frontShoulder : RigJoint.backShoulder;
      final elbow = front ? RigJoint.frontElbow : RigJoint.backElbow;
      final hand = front ? RigJoint.frontHand : RigJoint.backHand;
      final hip = front ? RigJoint.frontHip : RigJoint.backHip;
      final knee = front ? RigJoint.frontKnee : RigJoint.backKnee;
      final ankle = front ? RigJoint.frontAnkle : RigJoint.backAnkle;
      final heel = front ? RigJoint.frontHeel : RigJoint.backHeel;
      final toe = front ? RigJoint.frontToe : RigJoint.backToe;
      final upperArm = segment(
        front ? RagdollPart.frontUpperArm : RagdollPart.backUpperArm,
        pose[shoulder],
        pose[elbow],
        h * 0.022,
        0.8,
      );
      final forearm = segment(
        front ? RagdollPart.frontForearm : RagdollPart.backForearm,
        pose[elbow],
        pose[hand],
        h * 0.019,
        0.6,
      );
      final thigh = segment(
        front ? RagdollPart.frontThigh : RagdollPart.backThigh,
        pose[hip],
        pose[knee],
        h * 0.028,
        1.6,
      );
      final shin = segment(
        front ? RagdollPart.frontShin : RagdollPart.backShin,
        pose[knee],
        pose[ankle],
        h * 0.025,
        1.1,
      );
      final foot = segment(
        front ? RagdollPart.frontFoot : RagdollPart.backFoot,
        pose[heel],
        pose[toe],
        h * 0.016,
        0.4,
      );
      bind(elbow, upperArm);
      bind(hand, forearm);
      bind(knee, thigh);
      bind(ankle, shin);
      bind(heel, foot);
      bind(toe, foot);
      hinge(torso, upperArm, pose[shoulder], -2.9, 2.9, relativeToPose: true);
      final right = pose.facing > 0;
      hinge(
        upperArm,
        forearm,
        pose[elbow],
        right ? -2.70 : -0.04,
        right ? 0.04 : 2.70,
      );
      hinge(pelvis, thigh, pose[hip], -1.55, 1.55, relativeToPose: true);
      hinge(
        thigh,
        shin,
        pose[knee],
        right ? -0.04 : -2.65,
        right ? 2.65 : 0.04,
      );
      hinge(shin, foot, pose[ankle], -0.90, 0.90, relativeToPose: true);
    }
    // Native capsule tolerances can slightly change a short part's area.
    // Normalize from native mass, retaining the anatomical mass ratios.
    final nativeMass = ragdoll.bodies.values.fold<double>(
      0,
      (sum, body) => sum + body.mass,
    );
    for (final body in ragdoll.bodies.values) {
      body.shapes.single.density *= totalMassKilograms / nativeMass;
    }
    return ragdoll;
  }

  static double _angle(double value) =>
      (value + math.pi) % (math.pi * 2) - math.pi;

  Vector2 get pelvisPosition => bodies[RagdollPart.pelvis]!.position;
  Vector2 get velocity => bodies[RagdollPart.pelvis]!.linearVelocity;

  CharacterRigPose get pose => CharacterRigPose(
    joints: {
      for (final entry in _bindings.entries)
        entry.key: entry.value.$1.worldPoint(entry.value.$2),
    },
    height: initialPose.height,
    facing: initialPose.facing,
    preset: initialPose.preset,
    blink: true,
    headAngle: bodies[RagdollPart.head]!.angle,
    lanternVisible: false,
    ragdoll: true,
  );

  void update(double dt) {
    if (_destroyed) return;
    _elapsed += dt;
    final settled = bodies.values.every(
      (body) =>
          body.linearVelocity.length < 0.38 && body.angularVelocity.abs() < 1.4,
    );
    _stableFor = settled ? _stableFor + dt : 0;
  }

  bool get isStable => !_destroyed && _elapsed >= 0.7 && _stableFor >= 0.32;

  double get maximumAnchorError {
    double error = 0;
    for (final joint in joints) {
      error = math.max(
        error,
        (joint.bodyA.worldPoint(joint.localAnchorA) -
                joint.bodyB.worldPoint(joint.localAnchorB))
            .length,
      );
    }
    return error;
  }

  /// Find a nearby supported standing capsule with full overhead clearance.
  /// A conservative overlap test rejects recovery underneath roofs/crates.
  Vector2? recoveryPosition({
    required double capsuleHeight,
    required double capsuleWidth,
  }) {
    if (!isStable) return null;
    final query = QueryFilter(
      categoryBits: CollisionLayers.ragdoll,
      maskBits: CollisionLayers.solid,
    );
    for (final offset in const [0.0, -0.24, 0.24, -0.48, 0.48, -0.72, 0.72]) {
      final double x = pelvisPosition.x + offset;
      RayHit? support;
      world.castRay(
        Vector2(x, pelvisPosition.y - capsuleHeight * 0.5),
        Vector2(0, capsuleHeight * 1.6),
        (hit) {
          if (hit.shape.isSensor || hit.normal.y > -0.75) return -1;
          if (support == null || hit.fraction < support!.fraction) {
            support = hit;
          }
          return hit.fraction;
        },
        filter: query,
      );
      if (support == null) continue;
      final floor = support!;
      final double slope = -floor.normal.x / floor.normal.y;
      final double radius = capsuleWidth / 2;
      final double slopeGap = radius * (math.sqrt(1 + slope * slope) - 1);
      final centre = Vector2(
        x,
        floor.point.y - capsuleHeight / 2 - slopeGap - 0.014,
      );
      final bounds = Aabb(
        Vector2(x - radius + 0.01, centre.y - capsuleHeight / 2 + 0.01),
        Vector2(
          x + radius - 0.01,
          centre.y + capsuleHeight / 2 - radius * 0.45,
        ),
      );
      final obstructed = world
          .overlapAabb(bounds, filter: query)
          .any((shape) => !shape.isSensor && shape != floor.shape);
      if (obstructed) continue;
      // Queries ignore interiors when their ray starts inside a solid. Test
      // the future capsule's centre/top as well, including the support body.
      final interiorBlocked = world
          .overlapAabb(bounds, filter: query)
          .any(
            (shape) =>
                !shape.isSensor &&
                (shape.testPoint(centre) ||
                    shape.testPoint(
                      Vector2(x, centre.y - capsuleHeight / 2 + radius),
                    )),
          );
      if (!interiorBlocked) return centre;
    }
    return null;
  }

  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    for (final body in bodies.values) {
      body.destroy();
    }
    bodies.clear();
    joints.clear();
    _bindings.clear();
  }
}
