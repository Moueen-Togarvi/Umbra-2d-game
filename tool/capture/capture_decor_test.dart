// The boy beside each tree standing on the path, to check every tree has
// clear ground of its own and no gap under its foot:
//   flutter test tool/capture/capture_decor_test.dart
// Frames go to build/chapters-preview/decor/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/render/scenery.dart';
import 'package:umbra/render/white_blossom_tree.dart';

import '../../test/support/campaign.dart';

void main() {
  for (final index in [1, 2, 4, 22, 37]) {
    testWidgets('decor ${index + 1}', (tester) async {
      const size = Size(1600, 720);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final game = await bootCampaign(tester);
      final chapter = await enterChapter<Chapter>(tester, game, index);
      final xs = <double>[
        for (final t in chapter.descendants().whereType<WhiteBlossomTree>())
          t.position.x,
        for (final p in chapter.descendants().whereType<SceneryProp>())
          if (p.standsOnPath) p.x,
      ];
      var n = 0;
      for (final x in xs.take(6)) {
        chapter.player.teleportTo(
          Vector2(
            x + 1.2,
            chapter.groundAt(x + 1.2) - GameConfig.playerHeight / 2,
          ),
        );
        for (var i = 0; i < 90; i++) {
          game.update(1 / 60);
        }
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
        final dir = Directory('build/chapters-preview/decor')
          ..createSync(recursive: true);
        File(
          '${dir.path}/ch${index + 1}_${n++}.png',
        ).writeAsBytesSync(bytes!);
      }
    });
  }
}
