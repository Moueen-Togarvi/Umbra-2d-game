// Measures how much the boy's hands shake, in the real game. Not part of
// the test suite; run it on demand:
//
//   flutter test tool/capture/arm_jitter_test.dart
//
// For each scene it follows each hand relative to its shoulder at the
// 120 Hz simulation rate and prints:
//   jitter  mean and largest frame-to-frame change of the hand's velocity
//           (the second difference of its position), in millimetres; a
//           smooth swing scores low, shaking scores high
//   swing   how far the hand travels forward and back (the arm swing),
//           in centimetres, so calming the shake can't hide a lost swing
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

  /// Steps [seconds] at 120 Hz and reports the hands' jitter and swing.
  void measure(String scene, UmbraGame game, Player player, double seconds) {
    final paths = <List<Vector2>>[[], []];
    for (var i = 0; i < (seconds * 120).round(); i++) {
      game.update(1 / 120);
      final pose = player.rigPoseWorld;
      paths[0].add(pose[RigJoint.frontHand] - pose[RigJoint.frontShoulder]);
      paths[1].add(pose[RigJoint.backHand] - pose[RigJoint.backShoulder]);
    }
    final out = StringBuffer(scene.padRight(12));
    for (var h = 0; h < 2; h++) {
      final path = paths[h];
      var sum = 0.0, most = 0.0;
      var low = double.infinity, high = -double.infinity;
      for (var i = 1; i + 1 < path.length; i++) {
        final double a = (path[i + 1] - path[i] * 2 + path[i - 1]).length;
        sum += a;
        most = math.max(most, a);
      }
      for (final p in path) {
        final double forward = p.x * player.facing;
        low = math.min(low, forward);
        high = math.max(high, forward);
      }
      out.write(
        '  ${h == 0 ? 'front' : 'back '} jitter '
        '${(sum / (path.length - 2) * 1000).toStringAsFixed(2)} mm mean, '
        '${(most * 1000).toStringAsFixed(1)} mm max, '
        'swing ${((high - low) * 100).toStringAsFixed(1)} cm',
      );
    }
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
