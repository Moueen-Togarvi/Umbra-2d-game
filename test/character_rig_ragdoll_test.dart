import 'dart:math' as math;

import 'package:flame/game.dart' show GameWidget;
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_ragdoll.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/physics/collision_layers.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/physics_props.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  setUpAll(initializeForge2D);

  test('IK keeps bone lengths while clamping unreachable hand targets', () {
    const h = 1.3;
    for (final facing in const [-1.0, 1.0]) {
      final rig = CharacterRig(height: h);
      for (var frame = 0; frame < 16; frame++) {
        final pose = rig.solve(
          CharacterPose(
            facing: facing,
            gait: 1,
            gaitPhase: frame * math.pi / 8,
            frontHand: const Offset(1.5, -1.5),
          ),
        );
        for (final front in const [false, true]) {
          final hip = pose[front ? RigJoint.frontHip : RigJoint.backHip];
          final knee = pose[front ? RigJoint.frontKnee : RigJoint.backKnee];
          final ankle = pose[front ? RigJoint.frontAnkle : RigJoint.backAnkle];
          final shoulder =
              pose[front ? RigJoint.frontShoulder : RigJoint.backShoulder];
          final elbow = pose[front ? RigJoint.frontElbow : RigJoint.backElbow];
          final hand = pose[front ? RigJoint.frontHand : RigJoint.backHand];
          expect((hip - knee).length, closeTo(h * CharacterRig.thigh, 2e-6));
          expect((knee - ankle).length, closeTo(h * CharacterRig.shin, 2e-6));
          expect(
            (shoulder - elbow).length,
            closeTo(h * CharacterRig.upperArm, 2e-6),
          );
          expect(
            (elbow - hand).length,
            closeTo(h * CharacterRig.forearm, 2e-6),
          );
        }
      }
    }
  });

  test('LIMBO proportions: a big head and short legs', () {
    const h = 1.3;
    final pose = CharacterRig(height: h).solve(const CharacterPose());
    // Skull plus hair, from the solved head centre (see CharacterSilhouette).
    final double hairTop = pose[RigJoint.head].y - h * 0.20;
    final double chin = pose[RigJoint.head].y + h * 0.13;
    const double soles = h / 2;
    final double total = soles - hairTop;
    expect((chin - hairTop) / total, inInclusiveRange(0.30, 0.40));
    expect((soles - pose[RigJoint.frontHip].y) / total, lessThan(0.36));
    expect(total, closeTo(h, h * 0.04), reason: 'fills the capsule');
  });

  for (final facing in const [-1.0, 1.0]) {
    test('native ragdoll transfers pose without teleport facing $facing', () {
      final world = World(gravity: Vector2(0, 16));
      addTearDown(world.destroy);
      world
          .createBody(BodyDef(position: Vector2(0, 3.5)))
          .createShape(
            Polygon.box(10, 0.5),
            ShapeDef(filter: Filter(categoryBits: CollisionLayers.terrain)),
          );
      final start = CharacterRig(height: 1.3)
          .solve(
            CharacterPose(gait: 0.65, gaitPhase: 0.8, air: 0.3, facing: facing),
          )
          .translated(Vector2(0, 1.9));
      final ragdoll = CharacterRagdoll.activate(
        world: world,
        pose: start,
        velocity: Vector2(1.4, -0.3),
      );
      expect(ragdoll.bodies.length, 13);
      expect(ragdoll.joints.length, 12);
      expect(
        ragdoll.bodies.values.fold<double>(0, (sum, body) => sum + body.mass),
        closeTo(40, 0.01),
      );
      for (final joint in RigJoint.values) {
        expect((ragdoll.pose[joint] - start[joint]).length, lessThan(3e-6));
      }
      for (final body in ragdoll.bodies.values) {
        expect(
          (body.linearVelocity - Vector2(1.4, -0.3)).length,
          lessThan(1e-6),
        );
        expect(body.shapes.single.filter.groupIndex, lessThan(0));
      }
      var maxError = 0.0;
      for (var step = 0; step < 720; step++) {
        world.step(1 / 120, subStepCount: 4);
        ragdoll.update(1 / 120);
        maxError = math.max(maxError, ragdoll.maximumAnchorError);
        for (final body in ragdoll.bodies.values) {
          expect(body.position.x.isFinite && body.position.y.isFinite, isTrue);
          expect(body.linearVelocity.length, lessThan(20));
        }
      }
      expect(maxError, lessThan(0.06));
      expect(ragdoll.isStable, isTrue);
      expect(
        ragdoll.recoveryPosition(capsuleHeight: 1.3, capsuleWidth: 0.42),
        isNotNull,
      );
      for (final joint in ragdoll.joints) {
        expect(
          joint.angle,
          inInclusiveRange(joint.lowerLimit - 0.10, joint.upperLimit + 0.10),
        );
      }
      ragdoll.destroy();
    });
  }

  test('planted soles stay on their targets and grabbing blends hands', () {
    const h = 1.3;
    final rig = CharacterRig(height: h);
    final grounded = rig.solve(
      const CharacterPose(
        gait: 1,
        gaitPhase: math.pi,
        frontFoot: Offset(-0.18, 0.5),
        backFoot: Offset(0.18, 0.5),
      ),
    );
    expect(grounded[RigJoint.frontAnkle].x, closeTo(-0.18 * h, 2e-6));
    expect(grounded[RigJoint.backAnkle].x, closeTo(0.18 * h, 2e-6));
    for (final ankle in [RigJoint.frontAnkle, RigJoint.backAnkle]) {
      expect(
        grounded[ankle].y + CharacterRig.ankleHeight * h,
        closeTo(0.5 * h, 2e-6),
      );
    }
    final from = rig.solve(
      const CharacterPose(frontHand: Offset(0.2, 0), interactionWeight: 0),
    );
    final middle = rig.solve(
      const CharacterPose(frontHand: Offset(0.2, 0), interactionWeight: 0.5),
    );
    final to = rig.solve(
      const CharacterPose(frontHand: Offset(0.2, 0), interactionWeight: 1),
    );
    expect(
      (middle[RigJoint.frontHand] -
              (from[RigJoint.frontHand] + to[RigJoint.frontHand]) * 0.5)
          .length,
      lessThan(2e-6),
    );
    final hanging = rig.solve(
      const CharacterPose(
        hanging: 1,
        frontHand: Offset(0, -0.38),
        backHand: Offset(0, -0.36),
        interactionWeight: 1,
      ),
    );
    expect(
      (hanging[RigJoint.frontHand] - Vector2(0, -0.38 * h)).length,
      lessThan(2e-6),
    );
    expect(
      (hanging[RigJoint.backHand] - Vector2(0, -0.36 * h)).length,
      lessThan(2e-6),
    );
  });

  test('recovery refuses a supported position under a low ceiling', () {
    final world = World(gravity: Vector2(0, 16));
    addTearDown(world.destroy);
    final ground = world.createBody(BodyDef(position: Vector2(0, 3.5)));
    ground.createShape(
      Polygon.box(10, 0.5),
      ShapeDef(filter: Filter(categoryBits: CollisionLayers.terrain)),
    );
    final start = CharacterRig(
      height: 1.3,
    ).solve(const CharacterPose()).translated(Vector2(0, 2.25));
    final ragdoll = CharacterRagdoll.activate(
      world: world,
      pose: start,
      velocity: Vector2.zero(),
    );
    for (var step = 0; step < 1200; step++) {
      world.step(1 / 120, subStepCount: 4);
      ragdoll.update(1 / 120);
    }
    expect(ragdoll.isStable, isTrue);
    ground.createShape(
      Polygon.offsetBox(10, 0.10, center: Vector2(0, -1.3)),
      ShapeDef(filter: Filter(categoryBits: CollisionLayers.terrain)),
    );
    expect(
      ragdoll.recoveryPosition(capsuleHeight: 1.3, capsuleWidth: 0.42),
      isNull,
    );
    ragdoll.destroy();
  });

  test(
    'backwards pull lean keeps both hands at the grip without moving feet',
    () {
      for (final facing in const [-1.0, 1.0]) {
        final rig = CharacterRig(height: 1.3);
        final before = rig.solve(
          CharacterPose(
            facing: facing,
            gait: 0.25,
            bodyLean: -0.08,
            frontFoot: const Offset(0.045, 0.5),
            backFoot: const Offset(-0.045, 0.5),
          ),
        );
        final held = rig.solve(
          CharacterPose(
            facing: facing,
            gait: 0.25,
            bodyLean: -0.08,
            frontFoot: const Offset(0.045, 0.5),
            backFoot: const Offset(-0.045, 0.5),
            frontHand: const Offset(0.228, -0.023),
            backHand: const Offset(0.228, -0.0077),
          ),
        );
        expect(
          (held[RigJoint.frontHand] -
                  Vector2(0.228 * 1.3 * facing, -0.023 * 1.3))
              .length,
          lessThan(2e-6),
        );
        expect(
          (held[RigJoint.backHand] -
                  Vector2(0.228 * 1.3 * facing, -0.0077 * 1.3))
              .length,
          lessThan(2e-6),
        );
        for (final joint in [
          RigJoint.frontHip,
          RigJoint.backHip,
          RigJoint.frontAnkle,
          RigJoint.backAnkle,
        ]) {
          expect((held[joint] - before[joint]).length, lessThan(2e-6));
        }
      }
    },
  );

  testWidgets('rendered hands remain on the real rope grip during a swing', (
    tester,
  ) async {
    final game = UmbraGame();
    await tester.pumpWidget(GameWidget(game: game));
    for (
      var frame = 0;
      frame < 30 && game.world.descendants().whereType<Player>().isEmpty;
      frame++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    for (var frame = 0; frame < 60; frame++) {
      game.stepEngine(stepTime: 1 / 120);
    }
    final player = game.world.descendants().whereType<Player>().single;
    final rope = game.world.descendants().whereType<SwingRope>().single;
    player.teleportTo(rope.grip + Vector2(0, GameConfig.playerHeight * 0.40));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    for (var frame = 0; frame < 24; frame++) {
      game.stepEngine(stepTime: 1 / 120);
    }
    expect(player.interactionLabel, 'swinging');
    double maximumGap = 0;
    for (var frame = 0; frame < 240; frame++) {
      game.stepEngine(stepTime: 1 / 120);
      expect(player.interactionLabel, 'swinging');
      final grip = player.interactions.gripWorld!;
      final pose = player.rigPoseWorld;
      maximumGap = math.max(
        maximumGap,
        (pose[RigJoint.frontHand] - grip).length,
      );
      maximumGap = math.max(
        maximumGap,
        (pose[RigJoint.backHand] - grip - Vector2(0, 0.02)).length,
      );
    }
    expect(maximumGap, lessThan(0.025));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
  });
}
