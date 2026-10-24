import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/character/ground_probe.dart';
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

  testWidgets('running footfall cues stop in the air and while idle', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    advance(game, 0.4);
    final idleSteps = player.footfalls;
    advance(game, 0.4);
    expect(player.footfalls, idleSteps);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    advance(game, 0.65);
    expect(player.footfalls, greaterThan(idleSteps));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    advance(game, 0.13);
    expect(player.isOnGround, isFalse);
    final airborneSteps = player.footfalls;
    advance(game, 0.2);
    expect(player.isOnGround, isFalse);
    expect(player.footfalls, airborneSteps);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    advance(game, 1.0);
    final stoppedSteps = player.footfalls;
    advance(game, 0.4);
    expect(player.footfalls, stoppedSteps);
  });

  testWidgets('slow walking and running sound every newly planted foot', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    for (final axis in [0.15, 1.0]) {
      game.intent.setKeyboardState(axis: axis);
      advance(game, 0.3);
      var contacts = 0;
      final before = player.footfalls;
      var planted = player.rigFeetPlanted;
      for (var i = 0; i < 90; i++) {
        game.update(1 / 60);
        final next = player.rigFeetPlanted;
        if (player.isOnGround) {
          for (var f = 0; f < 2; f++) {
            if (next[f] && !planted[f]) contacts++;
          }
        }
        planted = next;
      }
      expect(
        contacts,
        greaterThan(0),
        reason: 'axis $axis has visible contacts',
      );
      expect(
        player.footfalls - before,
        contacts,
        reason: 'one cue per contact, even below 20% gait weight',
      );
      game.intent.setKeyboardState(axis: 0);
      advance(game, 0.4);
    }
  });

  testWidgets('turning round passes quickly through a front view', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    expect(player.visualFacing, 1);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    var sawFront = false;
    double? frontAt;
    final knees = <RigJoint, List<Vector2>>{};
    for (var i = 0; i < 120; i++) {
      game.update(1 / 120);
      if (!sawFront && player.visualFacing.abs() < 0.2) {
        sawFront = true;
        frontAt = i / 120;
      }
      // The body stays whole through the turn: no bone stretched, and none
      // shorter than a bone pointing partly at the camera would look.
      final pose = player.rigPoseWorld;
      for (final (a, b, length) in [
        (RigJoint.frontHip, RigJoint.frontKnee, CharacterRig.thigh),
        (RigJoint.backKnee, RigJoint.backAnkle, CharacterRig.shin),
        (RigJoint.frontShoulder, RigJoint.frontElbow, CharacterRig.upperArm),
        (RigJoint.backElbow, RigJoint.backHand, CharacterRig.forearm),
      ]) {
        final double seen = (pose[a] - pose[b]).length;
        expect(seen, lessThan(length * GameConfig.playerHeight + 0.02));
        expect(seen, greaterThan(length * GameConfig.playerHeight * 0.3));
      }
      // And the knees do not flip from one side to the other as he passes
      // face-on: no jolt from one frame to the next.
      for (final knee in const [RigJoint.frontKnee, RigJoint.backKnee]) {
        final seen = knees.putIfAbsent(knee, () => [])
          ..add(pose[knee] - player.body.position);
        if (seen.length > 3) seen.removeAt(0);
        if (seen.length == 3) {
          expect(
            (seen[2] - seen[1] * 2 + seen[0]).length,
            lessThan(0.06),
            reason: '$knee at ${i / 120} s',
          );
        }
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

  group('at a pit edge', () {
    // The pit between areas 04 and 05: the far bank starts at 63.4 m.
    const double lip = 63.4;

    Future<(UmbraGame, Player, Level)> bootAtPit(WidgetTester tester) async {
      final (game, player) = await boot(tester);
      final level = game.world.descendants().whereType<Level>().single;
      return (game, player, level);
    }

    Vector2 standing(Level level, double x) =>
        Vector2(x, level.terrain.heightAt(x)! - GameConfig.playerHeight / 2);

    testWidgets('he steps back so he never stands over the drop', (
      tester,
    ) async {
      final (game, player, level) = await bootAtPit(tester);
      // Put down with his middle 6 cm out over the pit.
      player.teleportTo(standing(level, lip + 0.15) - Vector2(0.21, 0));
      advance(game, 1.5);
      expect(player.isDead, isFalse);
      expect(player.isOnGround, isTrue);
      expect(player.isCentreSupported, isTrue);
      expect(player.body.position.x, greaterThan(lip));
      // Both feet stand on the ground from heel to toe.
      final pose = player.rigPoseWorld;
      for (final (heel, toe) in [
        (RigJoint.frontHeel, RigJoint.frontToe),
        (RigJoint.backHeel, RigJoint.backToe),
      ]) {
        for (final end in [pose[heel], pose[toe]]) {
          final ground = probeGround(
            game.world,
            end.x,
            end.y - 0.1,
            0.2,
            ignore: player.body,
          );
          expect(ground, isNotNull, reason: 'over the gap at x=${end.x}');
        }
      }
    });

    testWidgets('stopping at the lip he balances a moment, once', (
      tester,
    ) async {
      final (game, player, level) = await bootAtPit(tester);
      player.teleportTo(standing(level, lip + 2.2));
      advance(game, 0.5);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
      for (var i = 0; i < 240 && player.body.position.x > lip + 0.35; i++) {
        game.update(1 / 120);
      }
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
      var teetered = 0;
      var was = false;
      for (var i = 0; i < 360; i++) {
        game.update(1 / 120);
        if (player.isTeetering && !was) teetered++;
        was = player.isTeetering;
      }
      expect(teetered, 1);
      expect(player.isDead, isFalse);
      expect(player.isTeetering, isFalse, reason: 'and then stands still');
    });

    testWidgets('on open ground he just stops', (tester) async {
      final (game, player, level) = await bootAtPit(tester);
      player.teleportTo(standing(level, 66));
      advance(game, 0.5);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
      advance(game, 0.6);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
      for (var i = 0; i < 240; i++) {
        game.update(1 / 120);
        expect(player.isTeetering, isFalse);
      }
    });
  });

  testWidgets('the body sinks into a landing instead of jumping', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    player.teleportTo(GameConfig.playerSpawn - Vector2(0, 2.4));
    final pelvis = <Vector2>[], capsule = <Vector2>[];
    for (var i = 0; i < 150; i++) {
      game.update(1 / 120);
      pelvis.add(player.rigPoseWorld[RigJoint.pelvis].clone());
      capsule.add(player.body.position.clone());
    }
    expect(player.isDead, isFalse);
    double worst(List<Vector2> path) {
      var most = 0.0;
      for (var i = 1; i + 1 < path.length; i++) {
        most = math.max(most, (path[i + 1] - path[i] * 2 + path[i - 1]).length);
      }
      return most;
    }

    // The capsule stops dead; the hips are cushioned.
    expect(worst(pelvis), lessThan(worst(capsule) * 0.8));
    // And never jump relative to the capsule.
    for (var i = 1; i < pelvis.length; i++) {
      final step = (pelvis[i] - capsule[i]) - (pelvis[i - 1] - capsule[i - 1]);
      expect(step.length, lessThan(0.06));
    }
  });

  testWidgets('swinging on a rope end the legs kick with the swing', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    final rope = game.world.descendants().whereType<SwingRope>().single;
    player.teleportTo(rope.grip + Vector2(0, GameConfig.playerHeight * 0.40));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    var forward = 0.0, samples = 0;
    for (var i = 0; i < 720; i++) {
      game.update(1 / 120);
      if (player.interactionLabel != 'swinging') continue;
      if (player.velocity.x * player.facing > 1.2) {
        final pose = player.rigPoseWorld;
        forward +=
            (pose[RigJoint.frontAnkle].x - pose[RigJoint.frontHip].x) *
            player.facing;
        samples++;
      }
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    expect(samples, greaterThan(20));
    expect(forward / samples, greaterThan(0.06), reason: 'feet out ahead');
  });

  testWidgets('in a jump and a fall the arms stay bent, never stretched', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    const double full =
        (CharacterRig.upperArm + CharacterRig.forearm) *
        GameConfig.playerHeight;
    var longest = 0.0;
    void watch() {
      final pose = player.rigPoseWorld;
      for (final (shoulder, hand) in [
        (RigJoint.frontShoulder, RigJoint.frontHand),
        (RigJoint.backShoulder, RigJoint.backHand),
      ]) {
        longest = math.max(longest, (pose[hand] - pose[shoulder]).length);
      }
    }

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    advance(game, 0.4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    for (var i = 0; i < 90; i++) {
      game.update(1 / 120);
      if (!player.isOnGround) watch();
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    player.teleportTo(GameConfig.playerSpawn - Vector2(0, 2.4));
    for (var i = 0; i < 70; i++) {
      game.update(1 / 120);
      if (!player.isOnGround) watch();
    }
    expect(longest, lessThan(full * 0.88));
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
