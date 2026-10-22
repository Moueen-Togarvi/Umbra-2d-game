// The boy for the main menu, drawn by the game itself on a clear canvas,
// close up, standing still and facing right:
//   flutter test tool/capture/capture_menu_boy_test.dart
// Writes assets/images/ui/menu_boy.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/config/game_config.dart';

import '../../test/support/campaign.dart';

void main() {
  testWidgets('menu boy', (tester) async {
    const size = Size(1600, 720);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final game = await bootCampaign(tester);
    final chapter = await enterChapter<Chapter>(tester, game, 1);
    const x = 30.0;
    final player = chapter.player;
    player.teleportTo(
      Vector2(x, chapter.groundAt(x) - GameConfig.playerHeight / 2),
    );
    // A step to the right, then still until he has settled.
    game.intent.setKeyboardState(axis: 1);
    for (var i = 0; i < 12; i++) {
      game.update(1 / 60);
    }
    game.intent.setKeyboardState(axis: 0);
    for (var i = 0; i < 240; i++) {
      game.update(1 / 60);
    }
    // 500 px to the metre: he stands about 650 px tall.
    const double ppm = 500, w = 520, h = 760;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..translate(w / 2, h / 2)
      ..scale(ppm)
      ..translate(-player.body.position.x, -player.body.position.y);
    player.renderTree(canvas);
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(w.toInt(), h.toInt());
      // Trimmed to what is drawn, so the foot of the image is his shadow.
      final rgba = (await image.toByteData())!;
      var left = image.width, top = image.height, right = 0, bottom = 0;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (rgba.getUint8((y * image.width + x) * 4 + 3) > 8) {
            if (x < left) left = x;
            if (x > right) right = x;
            if (y < top) top = y;
            if (y > bottom) bottom = y;
          }
        }
      }
      final trim = ui.PictureRecorder();
      ui.Canvas(
        trim,
      ).drawImage(image, Offset(-left.toDouble(), -top.toDouble()), ui.Paint());
      final trimmed = await trim.endRecording().toImage(
        right - left + 1,
        bottom - top + 1,
      );
      final data = await trimmed.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    File('assets/images/ui/menu_boy.png').writeAsBytesSync(bytes!);
  });
}
