import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/character/character_state.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/ground.dart';
import 'package:umbra/entities/physics_props.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/render/dust.dart';
import 'package:umbra/world/level.dart';

void main() {
  Future<(UmbraGame, Player)> boot(WidgetTester tester) async {
    final game = UmbraGame();
    await tester.pumpWidget(GameWidget(game: game));
    for (
      var i = 0;
      i < 30 && game.world.descendants().whereType<Player>().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(game.pauseEngine);
    return (game, game.world.descendants().whereType<Player>().single);
  }

  void advance(UmbraGame game, double seconds) {
    for (var i = 0; i < (seconds * 120).round(); i++) {
      game.update(1 / 120);
    }
  }

  testWidgets('one running speed, and reversal has inertia', (tester) async {
    final (game, player) = await boot(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    advance(game, 0.3);
    expect(
      player.velocity.x,
      closeTo(GameConfig.moveSpeedMetersPerSecond, 0.1),
    );
    expect(player.state, CharacterState.running);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    advance(game, 1 / 120);
    expect(player.velocity.x, greaterThan(0));
    expect(player.state, CharacterState.turning);
    advance(game, 0.5);
    expect(player.velocity.x, lessThan(-2));
    expect(player.facing, -1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
  });

  testWidgets('turning round passes quickly through a front view', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    expect(player.visualFacing, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    var sawFront = false;
    double? frontAt;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 120);
      if (!sawFront && player.visualFacing.abs() < 0.2) {
        sawFront = true;
        frontAt = i / 120;
      }
      // The body stays whole through the turn.
      final pose = player.rigPoseWorld;
      for (final (a, b, length) in [
        (RigJoint.frontHip, RigJoint.frontKnee, CharacterRig.thigh),
        (RigJoint.backKnee, RigJoint.backAnkle, CharacterRig.shin),
        (RigJoint.frontShoulder, RigJoint.frontElbow, CharacterRig.upperArm),
        (RigJoint.backElbow, RigJoint.backHand, CharacterRig.forearm),
      ]) {
        expect(
          (pose[a] - pose[b]).length,
          closeTo(length * GameConfig.playerHeight, 0.02),
        );
      }
    }
    expect(sawFront, isTrue);
    // He faces about as soon as he moves the other way; the turn itself is
    // over in a moment.
    expect(frontAt, lessThan(0.25));
    expect(player.visualFacing, -1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
  });

  testWidgets('standing about, he looks around and shifts his feet', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    advance(game, 1.0);
    final seen = <IdleAction>{};
    var lastFeet = player.rigFootTargets;
    for (var i = 0; i < 30 * 120; i++) {
      game.update(1 / 120);
      seen.add(player.idleAction);
      // Feet move only by stepping: a planted foot never slides.
      final feet = player.rigFootTargets;
      final planted = player.rigFeetPlanted;
      for (var f = 0; f < 2; f++) {
        if (planted[f] && !player.isSteppingInPlace) {
          expect((feet[f] - lastFeet[f]).length, lessThan(1e-4));
        }
      }
      lastFeet = feet;
      if (i == 8 * 120) {
        expect(
          seen.difference({IdleAction.none}),
          isNotEmpty,
          reason: 'something happens within eight seconds',
        );
      }
    }
    expect(
      seen,
      containsAll(IdleAction.values),
      reason: 'over half a minute he does each of them',
    );
    expect(player.state, CharacterState.idle);
  });

  testWidgets('after a stop the feet step into place instead of sliding', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    advance(game, 0.8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    var steps = 0;
    var wasStepping = false;
    var lastFeet = player.rigFootTargets;
    for (var i = 0; i < 240; i++) {
      game.update(1 / 120);
      if (player.isSteppingInPlace && !wasStepping) steps++;
      wasStepping = player.isSteppingInPlace;
      final feet = player.rigFootTargets;
      if (player.velocity.x.abs() < 0.05 && !player.isSteppingInPlace) {
        for (var f = 0; f < 2; f++) {
          if (player.rigFeetPlanted[f]) {
            expect((feet[f] - lastFeet[f]).length, lessThan(1e-4));
          }
        }
      }
      lastFeet = feet;
    }
    expect(steps, inInclusiveRange(1, 4));
    expect(player.isSteppingInPlace, isFalse);
  });

  group('sliding', () {
    Future<(UmbraGame, Player)> standAt(WidgetTester tester, double x) async {
      final (game, player) = await boot(tester);
      final level = game.world.descendants().whereType<Level>().single;
      player.teleportTo(
        Vector2(x, level.terrain.heightAt(x)! - GameConfig.playerHeight / 2),
      );
      return (game, player);
    }

    testWidgets('a steep bank slides him down it on his feet', (tester) async {
      final (game, player) = await standAt(tester, 35.6);
      var slid = false;
      var fastest = 0.0;
      for (var i = 0; i < 180; i++) {
        game.update(1 / 120);
        if (player.state == CharacterState.sliding) slid = true;
        fastest = math.max(fastest, player.velocity.x);
        expect(player.isDead, isFalse);
      }
      expect(slid, isTrue);
      expect(fastest, greaterThan(3.5), reason: 'faster than he runs');
      expect(player.body.position.x, greaterThan(37));
      // At the bottom he is back on his feet.
      advance(game, 1.0);
      expect(player.isSliding, isFalse);
      expect(player.isDead, isFalse);
    });

    testWidgets('ordinary slopes do not slide', (tester) async {
      final (game, player) = await standAt(tester, 9.3);
      for (var i = 0; i < 180; i++) {
        game.update(1 / 120);
        expect(player.isSliding, isFalse);
      }
      expect(player.velocity.x.abs(), lessThan(0.05));
    });

    testWidgets('he can jump out of a slide', (tester) async {
      final (game, player) = await standAt(tester, 35.6);
      for (var i = 0; i < 120 && !player.isSliding; i++) {
        game.update(1 / 120);
      }
      expect(player.isSliding, isTrue);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      var rose = false;
      for (var i = 0; i < 30; i++) {
        game.update(1 / 120);
        if (player.velocity.y < -3) rose = true;
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(rose, isTrue);
      expect(player.isSliding, isFalse);
    });
  });

  testWidgets('a hard landing throws up dust and jolts the camera', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    final dust = game.world.descendants().whereType<DustField>().single;
    // A small hop: no dust to speak of, no shake.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    advance(game, 0.1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    var shook = 0.0;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 120);
      shook = math.max(shook, game.cameraTrauma);
    }
    expect(player.lastLandingImpact, lessThan(GameConfig.cameraShakeImpact));
    expect(shook, 0);

    // A long drop.
    player.teleportTo(GameConfig.playerSpawn - Vector2(0, 2.6));
    var most = 0;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 120);
      shook = math.max(shook, game.cameraTrauma);
      most = math.max(most, dust.liveMotes);
    }
    expect(player.isDead, isFalse);
    expect(player.lastLandingImpact, greaterThan(GameConfig.hardLandingSpeed));
    expect(shook, greaterThan(0.3));
    expect(most, greaterThanOrEqualTo(10));
    // Both die away.
    advance(game, 1.5);
    expect(game.cameraTrauma, 0);
    expect(dust.liveMotes, 0);
  });

  testWidgets('a landing sinks the pelvis on its spring, then it recovers', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    player.teleportTo(GameConfig.playerSpawn - Vector2(0, 0.9));
    var deepest = 0.0;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 120);
      deepest = math.max(deepest, player.pelvisDrop);
    }
    expect(deepest, greaterThan(0.03), reason: 'the knees fold on landing');
    advance(game, 0.8);
    expect(player.pelvisDrop.abs(), lessThan(0.005), reason: 'and recover');
    // The legs bent to take it: the hip came closer to the planted ankle.
    final pose = player.rigPoseWorld;
    final double legSpan =
        (pose[RigJoint.frontHip] - pose[RigJoint.frontAnkle]).length;
    expect(
      legSpan,
      lessThan((CharacterRig.thigh + CharacterRig.shin) * 1.3 * 0.99),
      reason: 'standing knees stay softly bent, not locked straight',
    );
  });

  testWidgets('a long drop folds the knees; a longer one kills', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    // About 2 m: survivable, but he lands hard and is held for a moment.
    player.teleportTo(GameConfig.playerSpawn - Vector2(0, 2.1));
    var hardLanding = false;
    for (var i = 0; i < 120; i++) {
      game.update(1 / 120);
      hardLanding |= player.state == CharacterState.landing;
    }
    expect(player.isDead, isFalse);
    expect(hardLanding, isTrue);
    expect(player.isOnGround, isTrue);

    // About 5 m: too far. The body goes limp and stays limp.
    player.teleportTo(GameConfig.playerSpawn - Vector2(0, 5.2));
    for (var i = 0; i < 120 && !player.isDead; i++) {
      game.update(1 / 120);
    }
    expect(player.isDead, isTrue);
    expect(player.isRagdoll, isTrue);
    expect(player.body.isEnabled, isFalse);
    advance(game, 1.0);
    expect(player.isRagdoll, isTrue, reason: 'death does not get back up');

    // The death sequence fades out and brings him back.
    advance(game, 2.5);
    expect(player.isDead, isFalse);
    expect(player.body.isEnabled, isTrue);
    expect(
      player.body.position.x,
      closeTo(game.checkpoints.activeCheckpoint.x, 0.05),
    );
  });

  testWidgets(
    'ceiling collision cuts ascent without penetration or double jump',
    (tester) async {
      final (game, player) = await boot(tester);
      final ceiling = Ground.slab(
        left: 1,
        right: 4,
        top: 5.45,
        thickness: 0.25,
        style: GroundStyle.wall,
      );
      await game.world.add(ceiling);
      advance(game, 0.05);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
      var minimumHead = double.infinity;
      for (var i = 0; i < 60; i++) {
        game.update(1 / 120);
        minimumHead = math.min(
          minimumHead,
          player.body.position.y - GameConfig.playerHeight / 2,
        );
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      expect(minimumHead, greaterThanOrEqualTo(5.68));
      advance(game, 0.4);
      expect(player.isOnGround, isTrue);
    },
  );

  for (final vertical in [false, true]) {
    testWidgets(
      '${vertical ? 'vertical' : 'horizontal'} platform carries idle player and jump inherits velocity',
      (tester) async {
        final (game, player) = await boot(tester);
        final platform = MovingPlatform(
          from: Vector2(3, 4.8),
          to: vertical ? Vector2(3, 3.2) : Vector2(7, 4.8),
          size: Vector2(2, 0.25),
          speed: 0.6,
        );
        await game.world.add(platform);
        advance(game, 0.05);
        player.teleportTo(
          platform.body.position -
              Vector2(0, 0.125 + GameConfig.playerHeight / 2),
        );
        advance(game, 0.3);
        final offset = player.body.position - platform.body.position;
        advance(game, 1);
        expect(player.isOnGround, isTrue);
        expect(
          (player.body.position - platform.body.position - offset).length,
          lessThan(0.05),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
        advance(game, 0.05);
        expect(player.isOnGround, isFalse);
        if (!vertical) expect(player.velocity.x, closeTo(0.6, 0.04));
        expect(player.velocity.y, lessThan(-4.4));
        await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
      },
    );
  }

  testWidgets('planted feet do not skate during the run', (tester) async {
    final (game, player) = await boot(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    advance(game, 0.4);
    var plantedSamples = 0;
    var flightSamples = 0;
    var largestSlide = 0.0;
    // The heel and toe soles of each drawn boot. As the foot rolls the
    // touching part moves from heel to toe, but whichever part is on the
    // ground must not slide along it.
    List<Vector2> soles() {
      final pose = player.rigPoseWorld;
      return [
        for (final front in const [true, false])
          ...() {
            final ankle =
                pose[front ? RigJoint.frontAnkle : RigJoint.backAnkle];
            final heel = pose[front ? RigJoint.frontHeel : RigJoint.backHeel];
            final toe = pose[front ? RigJoint.frontToe : RigJoint.backToe];
            final along = (toe - heel).normalized();
            final down = Vector2(-along.y, along.x) * player.facing;
            final sole = down * (CharacterRig.ankleHeight * 1.3);
            return [
              ankle - along * (CharacterRig.heelReach * 1.3) + sole,
              toe + sole,
            ];
          }(),
      ];
    }

    bool touching(List<Vector2> all, int i) {
      final foot = i ~/ 2 * 2;
      return all[i].y > math.max(all[foot].y, all[foot + 1].y) - 0.004;
    }

    var previous = soles();
    final plantedFor = [0, 0];
    for (var i = 0; i < 120; i++) {
      game.update(1 / 120);
      final current = soles();
      final planted = player.rigFeetPlanted;
      for (final foot in const [0, 1]) {
        plantedFor[foot] = planted[foot] ? plantedFor[foot] + 1 : 0;
        // Once the foot has settled onto its contact (a few steps).
        if (plantedFor[foot] <= 8) continue;
        for (final part in [foot * 2, foot * 2 + 1]) {
          if (!touching(current, part) || !touching(previous, part)) continue;
          plantedSamples++;
          largestSlide = math.max(
            largestSlide,
            (current[part].x - previous[part].x).abs(),
          );
        }
      }
      if (!planted[0] && !planted[1]) flightSamples++;
      previous = current;
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    expect(plantedSamples, greaterThan(15));
    expect(largestSlide, lessThan(0.006));
    expect(
      flightSamples,
      greaterThan(10),
      reason: 'a run has moments with both feet off the ground',
    );
  });

  testWidgets('debug knockdown disables the capsule and recovers', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    expect(player.body.mass, closeTo(GameConfig.playerMassKilograms, 0.01));
    final before = player.body.position.clone();
    player.knockDown();
    expect(player.isRagdoll, isTrue);
    expect(player.body.isEnabled, isFalse);
    expect((player.cameraPosition - before).length, lessThan(0.25));
    for (
      var i = 0;
      i < 120 * 10 && (player.isRagdoll || !player.body.isEnabled);
      i++
    ) {
      game.update(1 / 120);
    }
    expect(player.isRagdoll, isFalse);
    expect(player.body.isEnabled, isTrue);
    advance(game, 0.3);
    expect(player.isOnGround, isTrue);
    expect(player.state, CharacterState.idle);
  });

  testWidgets(
    'a knocked-down body landing on stakes dies and respawns cleanly',
    (tester) async {
      final (game, player) = await boot(tester);
      player.teleportTo(
        Vector2((GameConfig.gapStartX + GameConfig.gapEndX) / 2, 2),
      );
      player.knockDown();
      advance(game, 1);
      expect(player.isDead, isTrue);
      advance(game, 3);
      expect(player.isRagdoll, isFalse);
      expect(player.body.isEnabled, isTrue);
      expect(
        player.body.position.x,
        closeTo(game.checkpoints.activeCheckpoint.x, 0.05),
      );
      expect(player.isOnGround, isTrue);
    },
  );
}
