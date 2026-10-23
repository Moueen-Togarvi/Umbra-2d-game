// Each chapter's way out as he comes up to it:
//   flutter test tool/capture/capture_exit_gates_test.dart
// Frames go to build/chapters-preview/exits/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/render/chapter_exit_gate.dart';

import '../../test/support/campaign.dart';

void main() {
  final only = Platform.environment['CHAPTERS']
      ?.split(',')
      .map(int.parse)
      .toSet();
  for (var number = 1; number <= 40; number++) {
    if (only != null && !only.contains(number)) continue;
    testWidgets('exit gate $number', (tester) async {
      const size = Size(1280, 720);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final game = await bootCampaign(tester);
      final chapter = await enterChapter<Chapter>(tester, game, number - 1);
      final gates = chapter.children.whereType<ChapterExitGate>();
      if (gates.isEmpty) return;
      final gate = gates.single;
      final x = gate.x - 4.2;
      chapter.player.teleportTo(
        Vector2(x, chapter.groundAt(x) - GameConfig.playerHeight / 2 - .3),
      );
      for (var i = 0; i < 420; i++) {
        // Scenes he skipped past (by being set down here) do not hold the
        // camera.
        chapter.cameraFocus = null;
        game.update(1 / 60);
        if (i % 10 == 0) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 2)),
          );
        }
      }
      if (Platform.environment['CHAPTERS'] != null) {
        // ignore: avoid_print
        print(
          'ch$number gate ${gate.x} h ${gate.height} width ${chapter.width} '
          'ground ${chapter.groundAt(gate.x)} player ${chapter.player.body.position} '
          'dead ${chapter.player.isDead} cam ${game.camera.viewfinder.position}',
        );
      }
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(game.backgroundColor(), ui.BlendMode.src);
      game.render(canvas);
      final picture = recorder.endRecording();
      final bytes = await tester.runAsync(() async {
        final image = await picture.toImage(1280, 720);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      final dir = Directory('build/chapters-preview/exits')
        ..createSync(recursive: true);
      File(
        '${dir.path}/ch${number.toString().padLeft(2, '0')}_${gate.design}.png',
      ).writeAsBytesSync(bytes!);
    });
  }
}
