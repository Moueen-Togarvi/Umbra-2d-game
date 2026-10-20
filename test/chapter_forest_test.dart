import 'support/route_pilot.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/cage.dart';
import 'package:umbra/chapters/forest.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  Future<UmbraGame> boot(WidgetTester tester) async {
    final game = UmbraGame(campaign: true);
    await tester.pumpWidget(GameWidget(game: game));
    for (var i = 0; i < 60 && game.stage?.isLoaded != true; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });
    return game;
  }

  /// Steps the game while letting a chapter load (which needs real time).
  Future<void> until(
    WidgetTester tester,
    UmbraGame game,
    bool Function() done, {
    int frames = 900,
  }) async {
    for (var i = 0; i < frames && !done(); i++) {
      driveExtension(game);
      game.update(1 / 60);
      if (i % 4 == 0) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
    }
  }

  testWidgets('a chapter picked from the list is played, with the controls '
      'his', (tester) async {
    final game = await boot(tester);
    for (var i = 0; i < 180; i++) {
      driveExtension(game);
      game.update(1 / 60);
    }
    game.director!.playChapter(4);
    await until(
      tester,
      game,
      () => game.director!.isPlaying && !game.director!.isBusy,
    );
    expect(game.stage, isA<ForestChapter>());
    expect(game.intent.isScripted, isFalse);
    expect(game.director!.showingTitle, isFalse);
    expect(game.blackness, lessThan(0.05));
  });

  testWidgets('chapter two can be played to the clearing, where he is taken', (
    tester,
  ) async {
    final game = await boot(tester);
    for (var i = 0; i < 180; i++) {
      driveExtension(game);
      game.update(1 / 60);
    }
    game.director!.playChapter(4);
    await until(
      tester,
      game,
      () => game.director!.isPlaying && !game.director!.isBusy,
    );
    final forest = game.stage! as ForestChapter;
    final player = forest.player;
    final intent = game.intent;
    final jumped = <String>{};
    var stoodOnCrate = false, climbedTrunk = false, swung = false;
    var glimpsed = false;
    double onCrateFor = 0;
    double releaseCooldown = 0;
    double reached = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 900 && !forest.isComplete; i++) {
      intent.setKeyboardState(axis: 1);
      releaseCooldown -= 1 / 60;
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      if (!intent.isScripted) {
        // The crate goes into the pit first; then down onto it, and up.
        final crate = forest.crate.body;
        final bool fallen =
            crate.position.y > 7.6 &&
            crate.linearVelocity.length < 0.05 &&
            crate.angularVelocity.abs() < 0.05;
        if (x > 35.6 && x < 36.5 && !jumped.contains('down')) {
          // Wait at the lip for the crate to go in and settle, then jump
          // down onto it.
          intent.setKeyboardState(axis: x < 36.2 ? 0.5 : 0);
          if (fallen && grounded) {
            intent.setKeyboardState(axis: 1);
            jump('down');
          }
        }
        if (jumped.contains('down') && !jumped.contains('out') && !grounded) {
          intent.setKeyboardState(
            axis: (crate.position.x - x).clamp(-1.0, 1.0),
          );
        }
        if (grounded && feet > 7.5 && x > 36 && x < 39.2) {
          stoodOnCrate = true;
          // Find his feet after the drop, then jump for the far lip.
          onCrateFor += 1 / 60;
          // To the near edge of the far side, then jump for the lip.
          final double edge = forest.crate.body.position.x + 0.45;
          intent.setKeyboardState(axis: x < edge ? 0.5 : 0);
          if (onCrateFor > 0.5 && x >= edge - 0.05 && !jumped.contains('out')) {
            intent.setKeyboardState(axis: 1);
            jump('out');
          }
        }
        if (grounded && x > 47.2 && x < 47.9 && !jumped.contains('log')) {
          jump('log');
        }
        if (grounded && x > 54.8 && x < 55.4 && !jumped.contains('rock')) {
          jump('rock');
        }
        if (grounded && x > 65.8 && x < 66.5 && !jumped.contains('ravine')) {
          jump('ravine');
        }
        if (mode == InteractionMode.swinging) {
          swung = true;
          if (x > 68.9 && player.velocity.x > 1.5 && releaseCooldown <= 0) {
            releaseCooldown = 2.0;
            jump('release');
          }
        }
        if (grounded && x > 122.4 && x < 123.6 && !jumped.contains('trunk')) {
          jump('trunk');
        }
        if (x > 124 && x < 131 && feet < 7.6 && grounded) climbedTrunk = true;
        if (grounded && x > 165.6 && x < 166.2 && !jumped.contains('rock2')) {
          jump('rock2');
        }
      }
      glimpsed |= forest.stranger.eyes > 0.5;
      driveExtension(game);
      game.update(1 / 60);
      expect(
        player.isDead,
        isFalse,
        reason:
            'died at x=${x.toStringAsFixed(2)} y=${feet.toStringAsFixed(2)} '
            'after $jumped (mode $mode, crate '
            '${forest.crate.body.position})',
      );
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      forest.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; '
          'y ${player.body.position.y.toStringAsFixed(2)} mode '
          '${player.interactions.mode.name} state ${player.state.name} '
          'grounded ${player.isOnGround} scripted ${intent.isScripted}',
    );
    expect(stoodOnCrate, isTrue, reason: 'the crate is the way over stakes');
    expect(swung, isTrue);
    expect(climbedTrunk, isTrue);
    expect(glimpsed, isTrue, reason: 'the vampire was seen far off');
    expect(forest.taker.landed, isTrue);
    // The story moves on to the cage.
    await until(tester, game, () => game.stage is CageChapter, frames: 900);
    expect(game.stage, isA<CageChapter>());
  });
}
