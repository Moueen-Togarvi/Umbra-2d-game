// The new puzzle rooms as the route pilot plays them, a frame at each
// telling moment:
//   flutter test tool/capture/capture_puzzles_test.dart
// Frames go to build/chapters-preview/puzzles/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flame/components.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'package:umbra/game/umbra_game.dart';

import '../../test/support/campaign.dart';
import '../../test/support/route_pilot.dart';

/// Where in each kind of room a frame is taken, metres from its start.
const _moments = <PuzzleKind, List<double>>{
  PuzzleKind.traps: [7.5, 18.6, 27.5],
  PuzzleKind.plateGate: [9.5, 19.5, 24.0],
  PuzzleKind.bridge: [11.0, 15.5, 21.5],
  PuzzleKind.chase: [6.5, 17.8, 30.5],
  PuzzleKind.rockfall: [10.0, 18.0, 28.0],
  PuzzleKind.bats: [9.0, 15.0, 20.0],
  PuzzleKind.spikes: [12.0, 21.0, 26.0],
  PuzzleKind.barrel: [2.6, 8.0, 14.0, 23.0, 29.0],
  PuzzleKind.zipline: [9.0, 14.0, 20.0, 26.0],
  PuzzleKind.logBridge: [14.0, 15.5, 17.5],
  PuzzleKind.wolves: [6.0, 12.0, 16.5, 22.0],
  PuzzleKind.crows: [9.0, 14.0, 20.0],
  PuzzleKind.pullCrate: [6.0, 10.0, 14.0, 20.0],
  PuzzleKind.fireflies: [7.0, 13.0, 20.0],
  PuzzleKind.bog: [9.0, 14.0, 22.0],
  PuzzleKind.cages: [13.5, 17.0],
  PuzzleKind.ropeClimb: [15.0, 16.6, 20.0],
  PuzzleKind.cageLift: [14.5, 15.9, 18.0],
  PuzzleKind.drawbridge: [13.0, 13.7, 17.5],
  PuzzleKind.hammer: [14.0, 20.0],
  PuzzleKind.levers: [8.0, 12.0, 20.5],
  PuzzleKind.twoRopes: [14.0, 17.5, 20.0],
  PuzzleKind.stalactites: [12.0, 18.0, 24.0],
  PuzzleKind.raft: [13.0, 18.0],
  PuzzleKind.sluice: [9.0, 15.0, 19.5, 23.0],
  PuzzleKind.logFloat: [12.0, 16.0, 20.0],
  PuzzleKind.floatCrate: [8.5, 10.5, 13.0, 20.0],
  PuzzleKind.sinkingRaft: [15.0, 18.0, 20.5],
  PuzzleKind.collapse: [8.0, 16.0, 24.0],
  PuzzleKind.crusher: [10.5, 15.0, 21.0],
  PuzzleKind.coffinHands: [10.0, 16.0, 23.0],
  PuzzleKind.twoCrates: [12.0, 21.0, 23.0],
  PuzzleKind.sleeper: [15.0, 19.5, 24.0],
  PuzzleKind.heavyLight: [10.0, 15.0, 20.0, 22.0],
  PuzzleKind.fallingFloor: [13.0, 18.0, 23.0],
  PuzzleKind.boulder: [9.0, 20.0, 27.0, 30.0],
  PuzzleKind.barrelRun: [8.0, 16.0, 24.0],
  PuzzleKind.floodRise: [8.0, 13.0, 17.0, 20.0],
  PuzzleKind.bookcase: [14.0, 15.5, 17.5],
  PuzzleKind.fireJets: [11.0, 16.0, 21.0],
  PuzzleKind.fallingStairs: [11.0, 16.0, 21.0],
  PuzzleKind.timedDoor: [8.7, 15.0, 21.0],
  PuzzleKind.bell: [5.0, 8.3, 14.0],
  PuzzleKind.moonWindow: [12.0, 17.0, 23.0],
  PuzzleKind.watchEye: [10.0, 18.0, 25.0],
  PuzzleKind.chandelier: [14.0, 18.0, 23.0],
  PuzzleKind.fireChase: [8.0, 16.0, 24.0],
  PuzzleKind.lantern: [10.0, 20.0],
  PuzzleKind.crawl: [15.0],
  PuzzleKind.pendulum: [14.0, 18.0],
  PuzzleKind.bellGate: [10.0, 15.0, 20.0],
  PuzzleKind.tripwire: [10.5, 18.0, 21.0],
  PuzzleKind.twoPlates: [11.0, 17.0, 20.5],
  PuzzleKind.leapRope: [10.0, 14.0, 17.0],
  PuzzleKind.seesaw: [16.0],
  PuzzleKind.burningRope: [15.5, 17.5, 20.0],
  PuzzleKind.boulderChase: [8.0, 16.0, 24.0],
  PuzzleKind.movingPlatform: [12.5, 16.0, 21.0],
  PuzzleKind.drain: [10.0, 18.0],
  PuzzleKind.rope: [17.0],
  PuzzleKind.weight: [12.0],
  PuzzleKind.crate: [15.0],
  PuzzleKind.oil: [12.0, 20.0],
};

void main() {
  final only = Platform.environment['CHAPTERS']
      ?.split(',')
      .map(int.parse)
      .toList();
  for (final number in only ?? [2, 3, 4]) {
    testWidgets('puzzles $number', (tester) async {
      const size = Size(1600, 720);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final game = await bootCampaign(tester);
      final chapter = await enterChapter<Chapter>(tester, game, number - 1);
      final rooms = chapter is JourneyChapter
          ? chapter.rooms
          : chapter.extensionRooms;
      if (chapter is! JourneyChapter) {
        // Straight to the rooms after the chapter's own story.
        final x = rooms.first.x - 1.5;
        chapter.player.teleportTo(
          Vector2(x, chapter.groundAt(x) - GameConfig.playerHeight / 2 - .2),
        );
      }
      final pilot = RoutePilot(game);
      final taken = <String>{};
      final dir = Directory('build/chapters-preview/puzzles')
        ..createSync(recursive: true);
      var best = 0.0;
      var wasDead = false;
      var still = 0;
      for (var i = 0; i < 60 * 300 && !chapter.isComplete; i++) {
        pilot.tick();
        game.update(1 / 60);
        final double x = chapter.player.body.position.x;
        if (chapter.player.isDead && !wasDead) {
          final room = rooms.lastWhere(
            (r) => r.x <= x,
            orElse: () => rooms.first,
          );
          // ignore: avoid_print
          print(
            'DEATH ch$number ${room.kind.name} local=${(x - room.x).toStringAsFixed(2)} '
            'y=${chapter.player.body.position.y.toStringAsFixed(2)}',
          );
        }
        wasDead = chapter.player.isDead;
        if (Platform.environment['TRACE'] != null) {
          final room = rooms.lastWhere(
            (r) => r.x <= x,
            orElse: () => rooms.first,
          );
          final local = x - room.x;
          if (room.kind.name == Platform.environment['TRACE'] &&
              local > double.parse(Platform.environment['FROM'] ?? '11.5') &&
              local < double.parse(Platform.environment['TO'] ?? '15.5')) {
            // ignore: avoid_print
            print(
              'TRACE local=${local.toStringAsFixed(2)} y=${chapter.player.body.position.y.toStringAsFixed(2)} '
              'vx=${chapter.player.velocity.x.toStringAsFixed(2)} water=${room.water?.level.toStringAsFixed(2)} crate=${room.crates.map((c) => '${(c.body.position.x - room.x).toStringAsFixed(2)},${(c.body.position.y - room.floor).toStringAsFixed(2)},${c.body.angle.toStringAsFixed(2)},${c.body.type.name}').toList()} mode=${chapter.player.interactions.mode.name} ball=${room.barrel?.body.position.x.toStringAsFixed(2)}/${room.barrel?.settled}/${room.boards?.broken} casks=${room.casks.map((c) => '${(c.body.position.x - room.x).toStringAsFixed(1)},${c.body.position.y.toStringAsFixed(1)},${c.body.linearVelocity.x.toStringAsFixed(1)}').toList()} vx=${room.hunter?.vampire.x.toStringAsFixed(1)} awake=${room.hunter?.awake} cord=${room.cord?.pulled} pedal=${room.pedal?.pressed}/${room.pedal2?.pressed} solved=${room.solved} pulls=${room.pulls} rope=${chapter.player.isOnRope} cords=${room.cords.map((c) => c.pulled).toList()} '
              ' ground=${chapter.player.isOnGround} dead=${chapter.player.isDead}',
            );
          }
        }
        // Stuck: one frame of it, and stop.
        if (x > best + .05) {
          best = x;
          still = 0;
        } else if (++still == 60 * 40) {
          taken.add('stuck');
          await _save(tester, game, '${dir.path}/ch${number}_stuck.png');
          break;
        }
        for (final room in rooms) {
          final moments = _moments[room.kind];
          if (moments == null) continue;
          for (final (k, at) in moments.indexed) {
            final name = 'ch${number}_${room.kind.name}_$k';
            if (taken.contains(name) || (x - room.x - at).abs() > .15) {
              continue;
            }
            taken.add(name);
            await _save(tester, game, '${dir.path}/$name.png');
          }
        }
      }
    });
  }
}

Future<void> _save(WidgetTester tester, UmbraGame game, String path) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..drawColor(game.backgroundColor(), ui.BlendMode.src);
  game.render(canvas);
  final picture = recorder.endRecording();
  final bytes = await tester.runAsync(() async {
    final image = await picture.toImage(1600, 720);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  });
  File(path).writeAsBytesSync(bytes!);
}
