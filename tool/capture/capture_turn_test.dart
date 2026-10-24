// The boy close up turning round, from a run and from standing, a frame
// every 1/60 s through the turn:
//   flutter test tool/capture/capture_turn_test.dart
// Frames go to build/chapters-preview/turn/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  testWidgets('turn', (tester) async {
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
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(game.pauseEngine);
    final player = game.world.descendants().whereType<Player>().single;
    void step(double seconds) {
      for (var i = 0; i < (seconds * 120).round(); i++) {
        game.update(1 / 120);
      }
    }

    player.teleportTo(Vector2(19, 5));
    step(0.2);
    final dir = Directory('build/chapters-preview/turn')
      ..createSync(recursive: true);
    var n = 0;
    Future<void> shot(String what) async {
      final view = game.camera.viewfinder;
      final keepSize = view.visibleGameSize?.clone();
      final keepAt = view.position.clone();
      view.visibleGameSize = Vector2(3.2, 1.44);
      view.position = player.body.position + Vector2(0, -0.05);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(const ui.Color(0xFFEDEBE6), ui.BlendMode.src);
      game.render(canvas);
      final picture = recorder.endRecording();
      if (keepSize != null) view.visibleGameSize = keepSize;
      view.position = keepAt;
      final bytes = await tester.runAsync(() async {
        final image = await picture.toImage(1600, 720);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      picture.dispose();
      File(
        '${dir.path}/${(n++).toString().padLeft(2, '0')}_$what.png',
      ).writeAsBytesSync(bytes!);
    }

    step(1);
    // From a run.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(0.8);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    for (var i = 0; i < 4; i++) {
      step(1 / 30);
    }
    for (var i = 0; i < 10; i++) {
      step(1 / 60);
      await shot('run_turn');
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    step(1.5);
    // From standing.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    for (var i = 0; i < 10; i++) {
      step(1 / 60);
      await shot('stand_turn');
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
  });
}
