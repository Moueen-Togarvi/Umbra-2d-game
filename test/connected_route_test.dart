import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'package:umbra/game/umbra_game.dart';
import 'support/campaign.dart';
import 'support/route_pilot.dart';

void main() {
  for (final number in [36, 37]) {
    testWidgets(
      'connected chapter $number returns through its drained passage',
      (tester) async {
        final game = await bootCampaign(tester);
        final chapter = await enterChapter<JourneyChapter>(
          tester,
          game,
          number - 1,
        );
        final room = chapter.rooms.firstWhere(
          (r) => r.kind == PuzzleKind.returnLoop,
        );
        final checkpoint = chapter.rooms.indexOf(room);
        chapter.resumeAt('checkpoint-$checkpoint');
        await stepUntil(
          tester,
          game,
          () => chapter.player.body.position.x >= room.x,
        );
        final pilot = RoutePilot(game);
        var upper = false, returned = false, crawled = false;
        var shotUpper = false, shotLower = false;
        final trace = <Object>[];
        for (var frame = 0; frame < 60 * 180; frame++) {
          pilot.tick();
          game.update(1 / 60);
          final p = chapter.player;
          final local = p.body.position.x - room.x;
          final feet = p.body.position.y + .65;
          upper |= local > 24 && feet < room.floor - 2;
          returned |=
              room.pedal!.pressed && local < 17 && feet > room.floor - .3;
          crawled |= returned && local > 24 && local < 35 && p.isLow;
          if (const bool.fromEnvironment('CAPTURE_CONNECTED')) {
            if (!shotUpper && room.pedal!.pressed && feet < room.floor - 2) {
              await capture(tester, game, '$number-upper');
              shotUpper = true;
            }
            if (!shotLower && returned && local > 28 && p.isLow) {
              await capture(tester, game, '$number-lower');
              shotLower = true;
            }
          }
          if (frame % 60 == 0) {
            trace.add({
              'seconds': frame / 60,
              'x': local,
              'feet': feet,
              'lift': room.lift!.travel,
              'chest': room.crates.first.body.position.x - room.x,
              'pedal': room.pedal!.pressed,
              'water': room.water!.level,
            });
          }
          if (p.isDead || local >= room.length + 3) break;
        }
        Directory('build/review-results/connected').createSync(recursive: true);
        File(
          'build/review-results/connected/$number.json',
        ).writeAsStringSync(jsonEncode(trace));
        expect(chapter.player.isDead, isFalse);
        expect(upper, isTrue);
        expect(returned, isTrue);
        expect(crawled, isTrue);
        expect(chapter.player.body.position.x, greaterThan(room.end + 2));
        expect(room.water!.level, closeTo(room.floor - .02, .02));
        if (room.withWatcher) expect(room.hunter!.vampire.gone, isTrue);
        chapter.player.die();
        for (var frame = 0; frame < 240; frame++) {
          game.update(1 / 60);
        }
        expect(chapter.player.isDead, isFalse);
        expect(room.water!.level, closeTo(room.floor - .02, .02));
        expect(room.pedal!.pressed, isTrue);
        expect(room.crates.first.body.position.x, greaterThan(room.x + 36));
        final fresh = JourneyChapter(intent: game.intent, number: number)
          ..resumeAt('checkpoint-${checkpoint + 1}');
        var loaded = false;
        game.setStage(fresh).then((_) => loaded = true);
        await stepUntil(
          tester,
          game,
          () => loaded && fresh.checkpoints.activeCheckpoint.x > room.end,
        );
        for (var frame = 0; frame < 90; frame++) {
          game.update(1 / 60);
        }
        final restored = fresh.rooms[checkpoint];
        expect(restored.pedal!.pressed, isTrue);
        expect(restored.water!.level, closeTo(room.floor - .02, .02));
        expect(restored.lift!.travel, closeTo(-restored.lift!.rise, .03));
        expect(restored.crates.first.body.position.x, greaterThan(room.x + 36));
        if (room.withWatcher) expect(restored.hunter!.vampire.gone, isTrue);
      },
    );
  }
}

Future<void> capture(WidgetTester tester, UmbraGame game, String name) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawColor(game.backgroundColor(), ui.BlendMode.src);
  game.render(canvas);
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(
      game.size.x.round(),
      game.size.y.round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });
  picture.dispose();
  final dir = Directory('build/review-results/connected')
    ..createSync(recursive: true);
  File('${dir.path}/$name.png').writeAsBytesSync(bytes!);
}
