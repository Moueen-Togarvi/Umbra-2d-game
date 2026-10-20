import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/chapters/campaign_catalog.dart';
import 'package:umbra/chapters/chapters.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/config/game_settings.dart';
import 'package:umbra/story/progress_store.dart';
import 'package:umbra/input/player_intent.dart';
import 'support/campaign.dart';
import 'support/route_pilot.dart';

void main() {
  test(
    '40 stable chapters, legacy migration, safe checkpoint and settings reset',
    () async {
      expect(Chapters.all.length, 40);
      expect(Chapters.all.map((e) => e.id).toSet().length, 40);
      expect(Chapters.all.last.id, 'dawn');
      final metrics = [
        for (final entry in Chapters.all)
          (() {
            final chapter = entry.build(PlayerIntent());
            return {
              'id': entry.id,
              'number': chapter.number,
              'widthMetres': chapter.width,
              'checkpointCount': chapter.checkpointXs.length,
              'originalWidthMetres': chapter.coreWidth,
              'areaRatio': chapter.coreWidth == 0
                  ? null
                  : chapter.width / chapter.coreWidth,
            };
          })(),
      ];
      Directory('build/review-results').createSync(recursive: true);
      File(
        'build/review-results/campaign-metrics.json',
      ).writeAsStringSync(const JsonEncoder.withIndent('  ').convert(metrics));

      expect(CampaignCatalog.roman(40), 'XL');
      expect(Chapters.numberWord(39), 'THIRTY-NINE');
      // A migration must preserve each original story position, including Dawn.
      const originalPositions = [
        1,
        5,
        6,
        8,
        11,
        13,
        16,
        18,
        20,
        22,
        25,
        28,
        33,
        35,
        40,
      ];
      for (var old = 0; old < originalPositions.length; old++) {
        SharedPreferences.setMockInitialValues({'umbra.reachedChapter': old});
        final migrated = await ProgressStore.load();
        expect(migrated.current, originalPositions[old] - 1);
        expect((await ProgressStore.load()).current, migrated.current);
      }
      SharedPreferences.setMockInitialValues({'umbra.reachedChapter': 10});
      var progress = await ProgressStore.load();
      expect(progress.reached, 24);
      await progress.enter(24);
      await progress.saveCheckpoint('children', 'checkpoint-3');
      progress = await ProgressStore.load();
      expect(progress.current, 24);
      expect(progress.checkpoint, 'checkpoint-3');
      final prefs = await SharedPreferences.getInstance();
      final settings = GameSettings(preferences: prefs);
      settings.set('music', .1);
      settings.setFlag('vibration', false);
      await settings.reset();
      expect(settings.music, .6);
      expect(settings.vibration, isTrue);
      expect((await ProgressStore.load()).checkpoint, 'checkpoint-3');
      await progress.enter(1);
      expect(progress.reached, 24);
      expect(progress.checkpoint, isNull);
    },
  );
  for (final number in JourneyChapter.routes.keys) {
    testWidgets('journey $number controls-only complete route', (tester) async {
      final game = await bootCampaign(tester);
      final chapter = await enterChapter<JourneyChapter>(
        tester,
        game,
        number - 1,
      );
      final pilot = RoutePilot(game);
      var deaths = 0;
      var dead = false;
      double furthest = 0;
      var stuck = 0, frames = 0;
      for (var i = 0; i < 60 * 1200 && !chapter.isComplete; i++) {
        frames++;
        if (!game.intent.isScripted) pilot.tick();
        game.update(1 / 60);
        if (chapter.player.isDead && !dead) {
          deaths++;
          stuck = 0;
          furthest = chapter.checkpoints.activeCheckpoint.x;
        }
        dead = chapter.player.isDead;
        if (chapter.player.body.position.x > furthest + .2) {
          furthest = chapter.player.body.position.x;
          stuck = 0;
        } else {
          stuck++;
        }
        if (deaths > 3 || stuck > 60 * 40) break;
      }
      final output = Directory('build/review-results/routes')
        ..createSync(recursive: true);
      File('${output.path}/${chapter.id}.json').writeAsStringSync(
        jsonEncode({
          'id': chapter.id,
          'number': number,
          'complete': chapter.isComplete,
          'simulationSeconds': frames / 60,
          'deaths': deaths,
          'widthMetres': chapter.width,
          'humanPlaytest': false,
        }),
      );
      if (number == 12) {
        expect(
          chapter.rooms.first.crates.first.body.position.x,
          lessThan(chapter.rooms.first.end),
          reason:
              'coffin cover must remain in its gallery instead of entering the raft pool',
        );
      }
      final p = chapter.player;
      expect(
        chapter.isComplete,
        isTrue,
        reason:
            'chapter $number deaths=$deaths x=${p.body.position.x} '
            'y=${p.body.position.y} mode=${p.interactions.mode} room=${pilot.previous?.kind} '
            'crates=${pilot.previous?.crates.map((c) => c.body.position).toList()} '
            'gate=${pilot.previous?.gate?.travel} pan=${pilot.previous?.pan?.travel} water=${pilot.previous?.water?.level} '
            'pedal=${pilot.previous?.pedal?.body.angle} pressed=${pilot.previous?.pedal?.pressed} '
            'current=${pilot.previous?.water?.current} velocity=${pilot.previous?.crates.map((c) => c.body.linearVelocity).toList()}',
      );
    });
  }
}
