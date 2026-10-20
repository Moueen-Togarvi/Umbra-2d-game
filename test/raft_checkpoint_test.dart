import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'support/campaign.dart';
import 'support/route_pilot.dart';

void main() {
  testWidgets('raft can be boarded and crossed after checkpoint restore', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    final chapter = await enterChapter<JourneyChapter>(tester, game, 11);
    chapter.resumeAt('checkpoint-2');
    await stepUntil(
      tester,
      game,
      () => chapter.checkpoints.activeCheckpoint.x > 100,
    );
    final pilot = RoutePilot(game);
    for (var i = 0; i < 60 * 60 && chapter.player.body.position.x < 128; i++) {
      pilot.tick();
      game.update(1 / 60);
      if (chapter.player.isDead) break;
    }
    expect(chapter.player.isDead, isFalse);
    expect(chapter.player.body.position.x, greaterThanOrEqualTo(128));
  });
}
