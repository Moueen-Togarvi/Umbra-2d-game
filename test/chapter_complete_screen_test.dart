import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'support/campaign.dart';

void main() {
  testWidgets('completion choices wait, restart, advance and return to menu', (
    tester,
  ) async {
    final game = await bootCampaign(tester, completionOverlay: true);
    await enterChapter<Chapter>(tester, game, 0);
    final director = game.director!;

    director.chapter!.complete();
    game.update(1 / 60);
    await tester.pump();
    expect(director.awaitingChoice, isTrue);
    expect(find.text('CHAPTER COMPLETE'), findsOneWidget);
    expect(find.text('NEXT CHAPTER'), findsOneWidget);
    expect(find.text('RESTART'), findsOneWidget);
    expect(find.text('MAIN MENU'), findsOneWidget);
    expect(director.index, 0);
    expect(game.progress.current, 1);

    await tester.tap(find.text('RESTART'));
    await stepUntil(
      tester,
      game,
      () => director.isPlaying && !director.isBusy && director.index == 0,
    );
    expect(director.awaitingChoice, isFalse);
    expect(game.progress.current, 0);

    director.chapter!.complete();
    game.update(1 / 60);
    await tester.pump();
    await tester.tap(find.text('NEXT CHAPTER'));
    await stepUntil(
      tester,
      game,
      () => director.isPlaying && !director.isBusy && director.index == 1,
    );
    expect(director.index, 1);

    director.chapter!.complete();
    game.update(1 / 60);
    await tester.pump();
    await tester.tap(find.text('MAIN MENU'));
    await stepUntil(tester, game, () => director.showingTitle);
    expect(director.showingTitle, isTrue);
    expect(game.progress.current, 2);
  });
}
