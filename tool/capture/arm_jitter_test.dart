// Measures how much the boy's hands shake, in the real game. Not part of
// the test suite; run it on demand:
//
//   flutter test tool/capture/arm_jitter_test.dart
//
// For each scene it follows the hands (relative to the shoulders), the
// ankles (relative to the hips) and the pelvis and head (relative to the
// capsule) at the 120 Hz simulation rate and prints, for each, the mean and
// largest frame-to-frame change of velocity (the second difference of
// position) in millimetres: smooth motion scores low, shaking and popping
// score high. "swing" is how far the front hand travels forward and back,
// in centimetres, so calming the shake can't hide a lost swing.
import 'dart:math' as math;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/world/level.dart';

void main() {
  Future<(UmbraGame, Player, Level)> boot(WidgetTester tester) async {
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
    game.pauseEngine();
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });
    final player = game.world.descendants().whereType<Player>().single;
    final level = game.world.descendants().whereType<Level>().single;
    return (game, player, level);
  }

  /// Steps [seconds] at 120 Hz and reports the jitter of the hands
  /// (relative to the shoulders), the ankles (relative to the hips) and the
  /// pelvis and head (relative to the capsule), plus the arm swing.
  void measure(String scene, UmbraGame game, Player player, double seconds) {
    final tracks = <String, (RigJoint, RigJoint?)>{
      'hand F': (RigJoint.frontHand, RigJoint.frontShoulder),
      'hand B': (RigJoint.backHand, RigJoint.backShoulder),
      'ankle F': (RigJoint.frontAnkle, RigJoint.frontHip),
      'ankle B': (RigJoint.backAnkle, RigJoint.backHip),
      'pelvis': (RigJoint.pelvis, null),
      'head': (RigJoint.head, null),
    };
    final paths = {for (final name in tracks.keys) name: <Vector2>[]};
    for (var i = 0; i < (seconds * 120).round(); i++) {
      game.update(1 / 120);
      final pose = player.rigPoseWorld;
      for (final MapEntry(key: name, value: (joint, base)) in tracks.entries) {
        paths[name]!.add(
          pose[joint] - (base == null ? player.body.position : pose[base]),
        );
      }
    }
    final out = StringBuffer(scene.padRight(11));
    for (final MapEntry(key: name, value: path) in paths.entries) {
      var sum = 0.0, most = 0.0;
      for (var i = 1; i + 1 < path.length; i++) {
        final double a = (path[i + 1] - path[i] * 2 + path[i - 1]).length;
        sum += a;
        most = math.max(most, a);
      }
      out.write(
        ' | $name ${(sum / (path.length - 2) * 1000).toStringAsFixed(1)}/'
        '${(most * 1000).toStringAsFixed(0)}',
      );
    }
    var low = double.infinity, high = -double.infinity;
    for (final p in paths['hand F']!) {
      low = math.min(low, p.x * player.facing);
      high = math.max(high, p.x * player.facing);
    }
    out.write(' | swing ${((high - low) * 100).toStringAsFixed(0)} cm');
    // ignore: avoid_print
    print(out);
  }

  testWidgets('hand jitter by scene', (tester) async {
    final (game, player, level) = await boot(tester);
    Vector2 standing(double x) =>
        Vector2(x, level.terrain.heightAt(x)! - GameConfig.playerHeight / 2);

    player.teleportTo(standing(20));
    for (var i = 0; i < 120; i++) {
      game.update(1 / 120);
    }
    measure('standing', game, player, 2);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    for (var i = 0; i < 60; i++) {
      game.update(1 / 120);
    }
    measure('running', game, player, 2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    measure('jump', game, player, 0.75);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

    player.teleportTo(standing(20) - Vector2(0, 2.4));
    measure('fall+land', game, player, 1.5);
  });
}
