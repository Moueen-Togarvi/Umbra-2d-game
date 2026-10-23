// The boy close up going low: sitting down, sitting, creeping forward and
// back, stopping and standing again, with numbers for what looks wrong:
//   flutter test tool/capture/capture_crouch_test.dart
// Frames go to build/chapters-preview/crouch/; the numbers are printed:
// how far any knee or ankle went below the ground, how fast a foot that
// should be planted slid along it, and the worst frame-to-frame jolt of
// the knees and ankles (relative to the hips), in millimetres.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  testWidgets('crouch', (tester) async {
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
    final player = game.world.descendants().whereType<Player>().single;
    const double h = GameConfig.playerHeight;

    // What is measured as it goes.
    var below = 0.0, slide = 0.0, jolt = 0.0;
    var phase = 'start';
    final worst = <String, List<double>>{};
    void note(int i, double v) {
      final w = worst.putIfAbsent(phase, () => [0, 0, 0]);
      w[i] = math.max(w[i], v);
    }

    var worstTop = double.infinity;
    final last = <RigJoint, List<Vector2>>{};
    final lastAnkle = <RigJoint, Vector2>{};
    void measure() {
      final pose = player.rigPoseWorld;
      final double ground = player.body.position.y + h / 2;
      for (final j in const [
        RigJoint.frontKnee,
        RigJoint.backKnee,
        RigJoint.frontAnkle,
        RigJoint.backAnkle,
      ]) {
        below = math.max(below, pose[j].y - ground);
        note(0, pose[j].y - ground);
        final hip =
            pose[j == RigJoint.frontKnee || j == RigJoint.frontAnkle
                ? RigJoint.frontHip
                : RigJoint.backHip];
        final rel = pose[j] - hip;
        final seen = last.putIfAbsent(j, () => []);
        seen.add(rel);
        if (seen.length > 3) seen.removeAt(0);
        if (seen.length == 3) {
          jolt = math.max(jolt, (seen[2] - seen[1] * 2 + seen[0]).length);
          note(2, (seen[2] - seen[1] * 2 + seen[0]).length);
        }
      }
      // A foot at the ground should stay put while it is down.
      if (player.isOnGround) {
        for (final j in const [RigJoint.frontAnkle, RigJoint.backAnkle]) {
          final now = pose[j];
          final was = lastAnkle[j];
          if (was != null &&
              (now.y - ground).abs() < 0.045 &&
              (was.y - ground).abs() < 0.045) {
            slide = math.max(slide, (now.x - was.x).abs() * 120);
            note(1, (now.x - was.x).abs() * 120);
          }
          lastAnkle[j] = now.clone();
        }
      }
      if (player.isLow) {
        final double top = pose[RigJoint.head].y - CharacterRig.headRadius * h;
        worstTop = math.min(
          worstTop,
          top - (ground - h * GameConfig.lowHeightRatio),
        );
      }
    }

    void step(double seconds, [String? what]) {
      if (what != null) phase = what;
      for (var i = 0; i < (seconds * 120).round(); i++) {
        game.update(1 / 120);
        measure();
      }
    }

    var n = 0;
    final dir = Directory('build/chapters-preview/crouch')
      ..createSync(recursive: true);
    Future<void> shot(String what) async {
      // Close on the boy.
      final view = game.camera.viewfinder;
      final keepSize = view.visibleGameSize?.clone();
      final keepAt = view.position.clone();
      view.visibleGameSize = Vector2(4.4, 1.98);
      view.position = player.body.position + Vector2(0, -0.2);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFFEDEBE6), ui.BlendMode.src);
      game.render(canvas);
      final picture = recorder.endRecording();
      if (keepSize != null) view.visibleGameSize = keepSize;
      view.position = keepAt;
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
      File(
        '${dir.path}/${(n++).toString().padLeft(2, '0')}_$what.png',
      ).writeAsBytesSync(bytes!);
    }

    final intent = game.intent;
    player.teleportTo(Vector2(19, 5));
    step(1.5, 'standing');
    // Only what follows counts.
    below = 0;
    slide = 0;
    jolt = 0;
    last.clear();
    lastAnkle.clear();
    await shot('standing');
    intent.setKeyboardState(sit: true);
    step(0.2, 'going_low');
    await shot('going_low');
    step(0.4, 'low_still');
    await shot('low_still');
    step(1.6, 'sitting');
    await shot('sitting');
    intent.setKeyboardState(sit: true, axis: 1);
    step(0.25, 'creep_start');
    await shot('creep_start');
    step(0.5, 'creeping');
    await shot('creeping');
    step(0.35, 'creeping');
    await shot('creeping');
    intent.setKeyboardState(sit: true, axis: 0);
    step(0.3, 'stopped_low');
    await shot('stopped_low');
    intent.setKeyboardState(sit: true, axis: -1);
    step(0.7, 'creeping_back');
    await shot('creeping_back');
    intent.setKeyboardState(sit: false, axis: 0);
    step(0.3, 'standing_up');
    await shot('standing_up');
    step(1.0, 'standing');
    await shot('standing');
    // For comparison: walking upright, then turning back.
    intent.setKeyboardState(axis: 1);
    step(1.0, 'walk');
    intent.setKeyboardState(axis: -1);
    step(1.0, 'walk_turn');
    intent.setKeyboardState(axis: 1, sit: true);
    step(1.2, 'creep_again');
    intent.setKeyboardState(axis: 0, sit: true);
    step(0.4, 'creep_stop');
    intent.setKeyboardState(axis: 0, sit: false);
    for (final MapEntry(:key, :value) in worst.entries) {
      // ignore: avoid_print
      print(
        'PHASE ${key.padRight(14)} below ${(value[0] * 1000).toStringAsFixed(0)} mm'
        '  slide ${(value[1] * 100).toStringAsFixed(0)} cm/s'
        '  jolt ${(value[2] * 1000).toStringAsFixed(1)} mm',
      );
    }
    // ignore: avoid_print
    print(
      'CROUCH below ground ${(below * 1000).toStringAsFixed(0)} mm, '
      'planted foot slide ${(slide * 100).toStringAsFixed(0)} cm/s, '
      'leg jolt ${(jolt * 1000).toStringAsFixed(1)} mm, '
      'head under low top by ${(worstTop * 100).toStringAsFixed(1)} cm',
    );
  });
}
