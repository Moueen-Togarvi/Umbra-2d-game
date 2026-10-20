import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'support/campaign.dart';

void main() {
  testWidgets('ending keeps its sixty-second timeline at five FPS', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    game.settings.setFlag('soundOn', false);
    final chapter = await enterChapter<Chapter>(tester, game, 39);
    chapter.complete();
    final director = game.director!;
    await stepUntil(tester, game, () => director.cardTitle == 'The End');
    for (var i = 0; i < 59 * 5; i++) {
      game.update(0.2);
    }
    expect(director.cardTitle, 'for playing');
    expect(director.cardAlpha, greaterThan(0));
    expect(director.eyes, 0);
    for (var i = 0; i < 6; i++) {
      game.update(0.2);
    }
    expect(director.cardAlpha, 0, reason: 'credits fade ends at sixty seconds');
    expect(director.eyes, 0, reason: 'eyes follow the post-credit silence');
    for (var i = 0; i < 8; i++) {
      game.update(0.2);
    }
    expect(director.eyes, greaterThan(0));
  });

  testWidgets(
    'muted ending completes after chapter 40 and shows sixty seconds of credits',
    (tester) async {
      final game = await bootCampaign(tester);
      game.settings.setFlag('soundOn', false);
      final chapter = await enterChapter<Chapter>(tester, game, 39);
      chapter.complete();
      final director = game.director!;
      await stepUntil(tester, game, () => director.cardTitle == 'The End');
      expect(director.index, 39);
      for (var i = 0; i < 60 * 59; i++) {
        game.update(1 / 60);
      }
      expect(
        director.eyes,
        0,
        reason: 'red eyes must wait until the music/credits timeline ends',
      );
      for (var i = 0; i < 60 * 5; i++) {
        game.update(1 / 60);
      }
      expect(director.eyes, greaterThan(0));
      await stepUntil(tester, game, () => director.showingTitle, frames: 1200);
      expect(director.showingTitle, isTrue);
    },
  );
}
