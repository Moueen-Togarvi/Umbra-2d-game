import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'support/campaign.dart';
import 'support/route_pilot.dart';

void main() {
  testWidgets(
    'restart immediately after pressing a control restores its latch',
    (tester) async {
      final game = await bootCampaign(tester);
      final chapter = await enterChapter<JourneyChapter>(tester, game, 35);
      final room = chapter.rooms.firstWhere(
        (r) => r.kind == PuzzleKind.returnLoop,
      );
      chapter.resumeAt('checkpoint-${chapter.rooms.indexOf(room)}');
      await stepUntil(
        tester,
        game,
        () => chapter.player.body.position.x >= room.x,
      );
      final pilot = RoutePilot(game);
      for (var frame = 0; frame < 60 * 90 && !room.pedal!.pressed; frame++) {
        pilot.tick();
        game.update(1 / 60);
      }
      expect(room.pedal!.pressed, isTrue);
      game.intent.clear();
      chapter.restartCheckpoint();
      for (var frame = 0; frame < 60; frame++) {
        game.update(1 / 60);
      }
      expect(room.pedal!.pressed, isFalse);
      expect(room.solved, isFalse);
      expect(room.water!.level, closeTo(room.floor - 1.6, .001));
      expect(chapter.player.isDead, isFalse);
    },
  );
}
