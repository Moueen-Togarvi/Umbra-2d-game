import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/game/umbra_game.dart';

/// Boots the story (title first) with the engine paused, so the test steps
/// time itself.
Future<UmbraGame> bootCampaign(WidgetTester tester) async {
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

/// Steps the game until [done], letting asynchronous loads finish.
Future<void> stepUntil(
  WidgetTester tester,
  UmbraGame game,
  bool Function() done, {
  int frames = 900,
}) async {
  for (var i = 0; i < frames && !done(); i++) {
    game.update(1 / 60);
    if (i % 4 == 0) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump();
    }
  }
}

/// From the title into chapter [index] (from 0), once it is his to play.
Future<T> enterChapter<T>(
  WidgetTester tester,
  UmbraGame game,
  int index,
) async {
  for (var i = 0; i < 180; i++) {
    game.update(1 / 60);
  }
  game.director!.playChapter(index);
  await stepUntil(
    tester,
    game,
    () => game.director!.isPlaying && !game.director!.isBusy,
  );
  await stepUntil(tester, game, () => !game.intent.isScripted);
  return game.stage! as T;
}
