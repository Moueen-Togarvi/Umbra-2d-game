// Frames of the boy sitting down, creeping and standing again, with the
// touch controls on screen:
//   flutter test tool/capture/capture_sit_test.dart
// Frames go to build/chapters-preview/sit/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  testWidgets('sit', (tester) async {
    const size = Size(1600, 720);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final game = UmbraGame();
    await tester.pumpWidget(GameWidget(game: game));
    for (
      var i = 0;
      i < 40 && game.world.descendants().whereType<Player>().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 30; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(game.pauseEngine);

    void step(double seconds) {
      for (var i = 0; i < (seconds * 60).round(); i++) {
        game.update(1 / 60);
      }
    }

    var n = 0;
    Future<void> shot(String what) async {
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(game.backgroundColor(), ui.BlendMode.src);
      game.render(canvas);
      final picture = recorder.endRecording();
      final bytes = await tester.runAsync(() async {
        final image = await picture.toImage(
          size.width.toInt(),
          size.height.toInt(),
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      picture.dispose();
      final dir = Directory('build/chapters-preview/sit')
        ..createSync(recursive: true);
      File(
        '${dir.path}/${(n++).toString().padLeft(2, '0')}_$what.png',
      ).writeAsBytesSync(bytes!);
    }

    final intent = game.intent;
    // On open ground, away from the dark edge of the level.
    final player = game.world.descendants().whereType<Player>().single;
    player.teleportTo(Vector2(19, 5));
    step(1.5);
    await shot('standing');
    intent.setKeyboardState(sit: true);
    for (final t in [0.12, 0.2, 0.3, 0.6]) {
      step(t);
      await shot('sitting_down');
    }
    intent.setKeyboardState(sit: true, axis: 1);
    step(0.5);
    await shot('getting_up_to_creep');
    step(0.6);
    await shot('creeping');
    step(0.4);
    await shot('creeping');
    intent.setKeyboardState(sit: true, axis: 0);
    step(1.0);
    await shot('sitting_again');
    intent.setKeyboardState(sit: false);
    step(0.3);
    await shot('standing_up');
    step(0.8);
    await shot('standing');
  });
}
