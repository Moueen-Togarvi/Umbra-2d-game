// Frames of the fight for visual review: the slash, a thrown star, the dash,
// a vampire cut down, and Chapter 1's sword, dummy and pouch.
//   flutter test tool/capture/capture_combat_test.dart
// Frames go to build/chapters-preview/combat/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart' show Vector2;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'package:umbra/game/umbra_game.dart';

import '../../test/support/campaign.dart';

final Directory out = Directory('build/chapters-preview/combat');

void main() {
  Future<void> shot(WidgetTester tester, UmbraGame game, String name) async {
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
    out.createSync(recursive: true);
    File('${out.path}/$name.png').writeAsBytesSync(bytes!);
  }

  void step(UmbraGame game, int frames) {
    for (var i = 0; i < frames; i++) {
      game.update(1 / 60);
    }
  }

  Future<void> settle(WidgetTester tester, UmbraGame game) async {
    for (var i = 0; i < 6; i++) {
      step(game, 10);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
  }

  void view(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
  }

  testWidgets('slash, throw and dash against a hunter', (tester) async {
    view(tester);
    final game = await bootCampaign(tester);
    final stage = await enterChapter<JourneyChapter>(tester, game, 3);
    final room = stage.rooms.firstWhere((r) => r.kind == PuzzleKind.patrol);
    final hunter = room.hunter!;
    final x = room.x + 8;
    void place(double gap) {
      stage.player.teleportTo(Vector2(x, stage.groundAt(x) - .65));
      hunter.reset(x + gap);
    }

    // Settle the camera with him well away, then bring him close.
    place(14);
    game.intent.setKeyboardState(axis: 1);
    step(game, 3);
    game.intent.setKeyboardState(axis: 0);
    await settle(tester, game);
    place(1.3);
    step(game, 2);
    await shot(tester, game, 'slash_0_ready');
    game.intent.requestAttack();
    for (var i = 1; i <= 8; i++) {
      step(game, 3);
      await shot(tester, game, 'slash_$i');
    }
    for (final (i, frames) in [(9, 20), (10, 30)]) {
      step(game, frames);
      await shot(tester, game, 'slash_${i}_ash');
    }

    place(14);
    await settle(tester, game);
    place(6);
    step(game, 2);
    game.intent.requestThrow();
    for (var i = 1; i <= 6; i++) {
      step(game, 4);
      await shot(tester, game, 'throw_$i');
    }

    place(14);
    await settle(tester, game);
    game.intent.requestDash();
    for (var i = 1; i <= 4; i++) {
      step(game, 3);
      await shot(tester, game, 'dash_$i');
    }

    // A wind-up: the eyes flare.
    place(.75);
    step(game, 14);
    await shot(tester, game, 'windup');
  });

  testWidgets('Chapter 1: stump, dummy, pouch and the yard', (tester) async {
    view(tester);
    final game = await bootCampaign(tester);
    final home = await enterChapter<Chapter>(tester, game, 0);
    for (final (name, x) in [
      ('home_stump', 18.6),
      ('home_dummy', 26.3),
      ('home_field', 33.0),
      ('home_pouch', 44.0),
      ('home_ditch', 47.5),
      ('home_orchard', 62.0),
    ]) {
      home.player.teleportTo(
        Vector2(x, home.groundAt(x) - .65),
      );
      await settle(tester, game);
      await shot(tester, game, name);
      if (name == 'home_dummy') {
        game.intent.requestAttack();
        step(game, 14);
        await shot(tester, game, 'home_dummy_cut');
      }
    }
  });
}
