// The water up close as the route pilot plays the chapters that have most
// of it: wading in, the raft, the drains and floods, a crate floating up.
//   flutter test tool/capture/capture_water_test.dart
//   CHAPTERS=9,10 flutter test tool/capture/capture_water_test.dart
//   flutter test tool/capture/capture_water_test.dart --plain-name showcase
// (the caves' pool, a crate dropped in, the river's logs, and drowning).
// Frames go to build/chapters-preview/water/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show Rot;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/caves.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/physics/water.dart';

import '../../test/support/campaign.dart';
import '../../test/support/route_pilot.dart';

void main() {
  final only = Platform.environment['CHAPTERS']
      ?.split(',')
      .map(int.parse)
      .toList();
  testWidgets('water showcase', (tester) async {
    const size = Size(1600, 720);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final game = await bootCampaign(tester);
    final caves = await enterChapter<CavesChapter>(tester, game, 7);
    final dir = Directory('build/chapters-preview/water')
      ..createSync(recursive: true);
    void step(double seconds) {
      for (var i = 0; i < (seconds * 60).round(); i++) {
        game.intent.setKeyboardState(axis: 0);
        game.update(1 / 60);
      }
    }

    Future<void> shot(String name, Vector2 at) async {
      final view = game.camera.viewfinder;
      final keepSize = view.visibleGameSize?.clone();
      final keepAt = view.position.clone();
      view.visibleGameSize = Vector2(9, 4.05);
      view.position = at;
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder)
        ..drawColor(game.backgroundColor(), ui.BlendMode.src);
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
      File('${dir.path}/show_$name.png').writeAsBytesSync(bytes!);
    }

    final player = caves.player;
    const double lift = GameConfig.playerHeight / 2;
    // The pool: the boy at its edge, the crate dropped in from above.
    player.teleportTo(Vector2(21.6, 7.0 - lift));
    step(1);
    final pool = Vector2(24.6, 7.0);
    await shot('pool_still', pool);
    caves.crate.body
      ..setTransform(Vector2(24.4, 5.4), Rot.fromAngle(0.15))
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..isAwake = true;
    for (final (i, wait) in [0.42, 0.1, 0.15, 0.3, 0.6, 1.4].indexed) {
      step(wait);
      await shot('pool_crate_$i', pool);
    }
    // The river: logs coming down on the current.
    player.teleportTo(Vector2(69.4, 6.9 - lift));
    step(3);
    for (var i = 0; i < 3; i++) {
      step(0.8);
      await shot('river_$i', Vector2(player.body.position.x + 3.6, 7.0));
    }
    // In over his head: he cannot swim.
    player.teleportTo(Vector2(25.6, 6.4 - lift));
    for (var i = 0; i < 4; i++) {
      step(0.3);
      await shot('drown_$i', Vector2(25.6, 7.2));
    }
  });

  for (final number in only ?? [9, 10, 14]) {
    testWidgets('water $number', (tester) async {
      const size = Size(1600, 720);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      final game = await bootCampaign(tester);
      final chapter = await enterChapter<JourneyChapter>(
        tester,
        game,
        number - 1,
      );
      final pilot = RoutePilot(game);
      final dir = Directory('build/chapters-preview/water')
        ..createSync(recursive: true);
      var shots = 0, since = 0;
      for (var i = 0; i < 60 * 240 && !chapter.isComplete && shots < 16; i++) {
        pilot.tick();
        game.update(1 / 60);
        since++;
        final double x = chapter.player.body.position.x;
        final near = chapter.descendants().whereType<WaterBody>().any(
          (w) => x > w.left - 1.5 && x < w.right + 1.5,
        );
        if (!near || since < 24) continue;
        since = 0;
        // Closer than play, on the boy.
        final view = game.camera.viewfinder;
        final keepSize = view.visibleGameSize?.clone();
        final keepAt = view.position.clone();
        view.visibleGameSize = Vector2(10, 4.5);
        view.position = chapter.player.body.position + Vector2(0, 0.6);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder)
          ..drawColor(game.backgroundColor(), ui.BlendMode.src);
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
          '${dir.path}/ch${number}_${(shots++).toString().padLeft(2, '0')}.png',
        ).writeAsBytesSync(bytes!);
      }
    });
  }
}
