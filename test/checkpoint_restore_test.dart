import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapters.dart';
import 'package:umbra/chapters/cage.dart';
import 'package:umbra/input/player_intent.dart';
import 'support/campaign.dart';

void main() {
  for (var index = 0; index < Chapters.all.length; index++) {
    final entry = Chapters.all[index];
    testWidgets(
      '${entry.id}: every checkpoint restores into fresh world and survives death',
      (tester) async {
        final game = await bootCampaign(tester);
        final count = entry.build(PlayerIntent()).checkpointXs.length;
        for (var cp = 0; cp < count; cp++) {
          final chapter = entry.build(game.intent)..resumeAt('checkpoint-$cp');
          var loaded = false;
          game.setStage(chapter).then((_) => loaded = true);
          await stepUntil(
            tester,
            game,
            () => loaded && chapter.player.isMounted,
          );
          expect(loaded, isTrue);
          for (var frame = 0; frame < 90; frame++) {
            game.update(1 / 60);
          }
          final saved = chapter.checkpoints.activeCheckpoint;
          if (chapter is CageChapter) {
            if (saved.x >= 7) expect(chapter.cell.isOpen, isTrue);
            if (saved.x >= 63) expect(chapter.bridge.isDown, isTrue);
          }

          expect(saved.x, closeTo(chapter.checkpointXs[cp], .0001));
          expect(
            chapter.player.isDead,
            isFalse,
            reason: '${entry.id} checkpoint $cp cold restore',
          );
          expect(
            chapter.player.body.position.y,
            closeTo(saved.y, .2),
            reason: '${entry.id} checkpoint $cp unsupported spawn',
          );
          chapter.player.die();
          for (var frame = 0; frame < 240; frame++) {
            game.update(1 / 60);
          }
          expect(
            chapter.player.isDead,
            isFalse,
            reason: '${entry.id} checkpoint $cp death loop',
          );
          expect(chapter.player.body.position.x, closeTo(saved.x, .3));
          expect(chapter.player.body.position.y, closeTo(saved.y, .2));
        }
      },
    );
  }
}
