import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/chapters/chapters.dart';
import 'support/campaign.dart';

void main() {
  testWidgets('campaign advances and unlocks all forty chapters before ending', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    await enterChapter<Chapter>(tester, game, 0);
    final director = game.director!;
    // Completion is injected here to isolate progression; separate route tests
    // earn completion using movement controls in every chapter.
    for (var i = 0; i < 39; i++) {
      director.chapter!.complete();
      await stepUntil(
        tester,
        game,
        () => director.index == i + 1 && director.isPlaying && !director.isBusy,
        frames: 1800,
      );
      expect(director.index, i + 1);
      expect(director.chapter!.id, Chapters.all[i + 1].id);
      expect(director.progress.current, i + 1);
      expect(director.progress.reached, greaterThanOrEqualTo(i + 1));
      expect(director.cardTitle, isNot('The End'));
    }
    expect(director.chapter!.id, 'dawn');
    director.chapter!.complete();
    await stepUntil(tester, game, () => director.cardTitle == 'The End');
    expect(director.cardTitle, 'The End');
  });
}
