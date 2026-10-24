// The boy close up on a rope: catching it, hanging, swinging, climbing up
// and down, and kicking off:
//   flutter test tool/capture/capture_rope_test.dart
// Frames go to build/chapters-preview/rope/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/physics_props.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  testWidgets('rope', (tester) async {
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
    final rope = SwingRope(anchor: Vector2(34, 0.5), length: 3);
    await game.world.add(rope);
    void step(double seconds) {
      for (var i = 0; i < (seconds * 120).round(); i++) {
        game.update(1 / 120);
      }
    }

    step(0.2);
    final dir = Directory('build/chapters-preview/rope')
      ..createSync(recursive: true);
    var n = 0;
    Future<void> shot(String what) async {
      final view = game.camera.viewfinder;
      final keepSize = view.visibleGameSize?.clone();
      final keepAt = view.position.clone();
      view.visibleGameSize = Vector2(5, 2.25);
      view.position = player.body.position.clone();
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

    player.teleportTo(rope.grip + Vector2(0, GameConfig.playerHeight * 0.42));
    step(0.4);
    await shot('caught');
    step(1.2);
    await shot('hanging');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    for (var i = 0; i < 4; i++) {
      step(0.35);
      await shot('swinging');
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    step(0.6);
    await shot('climbing_up');
    step(0.6);
    await shot('climbing_up');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    step(0.5);
    await shot('climbing_down');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    step(0.15);
    await shot('kick_off');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    step(0.3);
    await shot('in_the_air');
  });
}
