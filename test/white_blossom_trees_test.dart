import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/render/white_blossom_tree.dart';

void main() {
  testWidgets('every chapter has three blossom trees on solid ground', (
    tester,
  ) async {
    final game = UmbraGame(campaign: true);
    await tester.pumpWidget(GameWidget(game: game));
    for (var i = 0; i < 80 && game.stage?.isLoaded != true; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 35)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 180; i++) {
      game.update(1 / 60);
    }
    game.pauseEngine();
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });

    for (var chapterIndex = 0; chapterIndex < 15; chapterIndex++) {
      if (chapterIndex > 0) {
        game.director!.playChapter(chapterIndex);
        for (var frame = 0; frame < 900; frame++) {
          game.update(1 / 60);
          if (game.director!.isPlaying &&
              !game.director!.isBusy &&
              game.stage?.isLoaded == true) {
            break;
          }
          if (frame % 4 == 0) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 2)),
            );
            await tester.pump();
          }
        }
      }

      final chapter = game.stage! as Chapter;
      final trees = chapter.children.whereType<WhiteBlossomTree>().toList();
      expect(
        trees,
        hasLength(3),
        reason: 'chapter ${chapter.number} must have three trees',
      );
      for (var i = 0; i < trees.length; i++) {
        expect(trees[i].position.x, closeTo(chapter.blossomTreeXs[i], .001));
      }
      for (final tree in trees) {
        expect(
          chapter.terrain.segmentAt(tree.position.x),
          isNotNull,
          reason: 'chapter ${chapter.number}: tree cannot stand over a pit',
        );
        expect(
          tree.position.y,
          closeTo(chapter.groundAt(tree.position.x) + .08, .001),
        );
      }
    }
  });
}
