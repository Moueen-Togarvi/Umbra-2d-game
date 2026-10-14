// Renders real gameplay frames to PNG for visual review. Not part of the test
// suite; run it on demand:
//
//   flutter test tool/capture/capture_frames_test.dart
//
// Frames go to build/limbo-preview/. Each scene also writes the player's
// screen position per frame to scenes.json, so tools/contact_sheet.py can crop
// close-ups of the boy into contact sheets.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show Rot;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/physics_props.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/world/level.dart';

const int width = 1600, height = 720;
final Directory out = Directory('build/limbo-preview');

void main() {
  final scenes = <String, List<Map<String, Object>>>{};

  Future<(UmbraGame, Player)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final game = UmbraGame();
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(1600, 720)),
        child: GameWidget(game: game),
      ),
    );
    for (
      var i = 0;
      i < 30 && game.world.descendants().whereType<Player>().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });
    return (game, game.world.descendants().whereType<Player>().single);
  }

  void step(UmbraGame game, double seconds) {
    for (var i = 0; i < (seconds * 60).round(); i++) {
      game.update(1 / 60);
    }
  }

  Future<void> shot(
    WidgetTester tester,
    UmbraGame game,
    Player player,
    String scene,
    String name,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawColor(game.backgroundColor(), ui.BlendMode.src);
    game.render(canvas);
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(width, height);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    picture.dispose();
    final dir = Directory('${out.path}/$scene')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!);
    final camera = game.camera;
    final double ppm = height / camera.visibleWorldRect.height;
    final cam = camera.viewfinder.position;
    final p = player.cameraPosition;
    (scenes[scene] ??= []).add({
      'file': '$scene/$name.png',
      'x': width / 2 + (p.x - cam.x) * ppm,
      'y': height / 2 + (p.y - cam.y) * ppm,
      'ppm': ppm,
      'state': player.state.name,
      'worldX': p.x,
      'worldY': p.y,
    });
  }

  Future<void> burst(
    WidgetTester tester,
    UmbraGame game,
    Player player,
    String scene,
    int frames, {
    double every = 1 / 30,
    String prefix = 'f',
  }) async {
    for (var i = 0; i < frames; i++) {
      await shot(
        tester,
        game,
        player,
        scene,
        '${prefix}_${i.toString().padLeft(3, '0')}',
      );
      step(game, every);
    }
  }

  tearDownAll(() {
    // Merged into what is there, so one scene can be re-captured alone.
    final file = File('${out.path}/scenes.json');
    final merged = <String, Object?>{
      if (file.existsSync())
        ...(jsonDecode(file.readAsStringSync()) as Map<String, Object?>),
      ...scenes,
    };
    file.writeAsStringSync(const JsonEncoder.withIndent(' ').convert(merged));
  });

  testWidgets('idle, run cycle, stop and turn', (tester) async {
    final (game, player) = await boot(tester);
    step(game, 1.5);
    await burst(tester, game, player, 'idle', 6, every: 0.5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await burst(tester, game, player, 'start', 12, every: 1 / 30);
    step(game, 0.4);
    await burst(tester, game, player, 'run', 30);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await burst(tester, game, player, 'stop', 15);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(game, 0.6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    await burst(tester, game, player, 'turn', 18);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
  });

  testWidgets('jumps and landings', (tester) async {
    final (game, player) = await boot(tester);
    step(game, 0.5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await burst(tester, game, player, 'jump_stand', 24);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    step(game, 0.5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(game, 0.6);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await burst(tester, game, player, 'jump_run', 24);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    // A drop from a height: a hard landing.
    player.teleportTo(Vector2(3, 3.2));
    await burst(tester, game, player, 'hard_landing', 36);
  });

  testWidgets('pit death and fade', (tester) async {
    final (game, player) = await boot(tester);
    final level = game.world.descendants().whereType<Level>().single;
    final x = GameConfig.gapStartX - 2.5;
    player.teleportTo(
      Vector2(x, level.terrain.heightAt(x)! - GameConfig.playerHeight / 2),
    );
    step(game, 1.2);
    // Dropped straight into the middle of the pit, onto the stakes.
    player.teleportTo(
      Vector2((GameConfig.gapStartX + GameConfig.gapEndX) / 2, 5.2),
    );
    await burst(tester, game, player, 'death', 40, every: 1 / 20);
    await burst(tester, game, player, 'death_fade', 16, every: 0.2);
  });

  testWidgets('push, rope and ledge', (tester) async {
    final (game, player) = await boot(tester);
    final level = game.world.descendants().whereType<Level>().single;
    final crate = game.world.descendants().whereType<PhysicsCrate>().firstWhere(
      (c) => c.massKg < 20,
    );
    final px = crate.body.position.x - 1.2;
    player.teleportTo(
      Vector2(px, level.terrain.heightAt(px)! - GameConfig.playerHeight / 2),
    );
    step(game, 0.3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(game, 0.6);
    await burst(tester, game, player, 'push', 12, every: 0.1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

    final rope = game.world.descendants().whereType<SwingRope>().single;
    player.teleportTo(rope.grip + Vector2(-1.4, 1.1));
    step(game, 0.4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(game, 0.15);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await burst(tester, game, player, 'rope', 40, every: 1 / 20);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
    // Climb up, then down, then jump off.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
    await burst(tester, game, player, 'rope_climb', 24, every: 1 / 15);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyS);
    await burst(tester, game, player, 'rope_down', 12, every: 1 / 15);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await burst(tester, game, player, 'rope_jump', 12, every: 1 / 20);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);

    const ledgeX = 73.0;
    final gx = ledgeX - 1.6;
    player.teleportTo(
      Vector2(gx, level.terrain.heightAt(gx)! - GameConfig.playerHeight / 2),
    );
    step(game, 0.4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(game, 0.2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    step(game, 0.05);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await burst(tester, game, player, 'ledge', 40, every: 1 / 20);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
  });

  testWidgets('standing at a pit edge and on a slope', (tester) async {
    final (game, player) = await boot(tester);
    final level = game.world.descendants().whereType<Level>().single;
    // Walked up to the lip of the first pit, as far as the capsule allows.
    for (final x in const [
      GameConfig.gapStartX - 0.12,
      GameConfig.gapStartX - 0.25,
    ]) {
      player.teleportTo(
        Vector2(x, level.terrain.heightAt(x)! - GameConfig.playerHeight / 2),
      );
      step(game, 1.5);
      await burst(
        tester,
        game,
        player,
        'edge',
        3,
        every: 0.4,
        prefix: 'x${(x * 100).round()}',
      );
    }
    // Standing on the slope, then running down it.
    const slopeX = 9.0;
    player.teleportTo(
      Vector2(
        slopeX,
        level.terrain.heightAt(slopeX)! - GameConfig.playerHeight / 2,
      ),
    );
    step(game, 1.5);
    await burst(tester, game, player, 'slope', 3, every: 0.4, prefix: 'idle');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(game, 0.4);
    await burst(
      tester,
      game,
      player,
      'slope',
      12,
      every: 1 / 30,
      prefix: 'run',
    );
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
  });

  testWidgets('round 1c: idle, slide, heavy push, tumbling crate', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    final level = game.world.descendants().whereType<Level>().single;
    Vector2 standing(double x) =>
        Vector2(x, level.terrain.heightAt(x)! - GameConfig.playerHeight / 2);

    // Standing about long enough to look around and shift his feet, where
    // the fog is light enough to see his face.
    player.teleportTo(standing(22));
    step(game, 2.4);
    await burst(tester, game, player, 'idle_life', 36, every: 0.25);

    // Running over the crest of the quarry bank and sliding down it.
    player.teleportTo(standing(34.2));
    step(game, 0.3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(game, 0.25);
    await burst(tester, game, player, 'slide', 30, every: 1 / 30);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

    // Pushing the heavy crate.
    final heavy = game.world.descendants().whereType<PhysicsCrate>().firstWhere(
      (c) => c.massKg > 20,
    );
    player.teleportTo(standing(heavy.body.position.x - 1.4));
    step(game, 0.3);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    step(game, 0.8);
    await burst(tester, game, player, 'push_heavy', 12, every: 0.1);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);

    // The light crate shoved to the lip of the first pit and over it.
    final light = game.world.descendants().whereType<PhysicsCrate>().firstWhere(
      (c) => c.massKg < 20,
    );
    const lipX = GameConfig.gapStartX - 0.9;
    light.body.setTransform(
      Vector2(lipX, level.terrain.heightAt(lipX)! - light.size.y / 2 - 0.03),
      const Rot.identity(),
    );
    light.body.linearVelocity = Vector2.zero();
    player.teleportTo(standing(lipX - 1.3));
    step(game, 0.4);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyD);
    await burst(tester, game, player, 'crate_tumble', 30, every: 1 / 15);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyD);
  });

  testWidgets('round 1e: pit edge, logs, rocks, teeter, pull', (tester) async {
    final (game, player) = await boot(tester);
    final level = game.world.descendants().whereType<Level>().single;
    Vector2 standing(double x) =>
        Vector2(x, level.terrain.heightAt(x)! - GameConfig.playerHeight / 2);

    // The spot of the user's phone screenshot: the pit between areas 04
    // and 05, walked up to from the right and stopped at the lip.
    player.teleportTo(standing(65.4));
    step(game, 1.0);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    for (var i = 0; i < 200 && player.body.position.x > 63.75; i++) {
      step(game, 1 / 60);
    }
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await burst(tester, game, player, 'teeter', 24, every: 1 / 20);
    step(game, 1.5);
    await shot(tester, game, player, 'pit_phone', 'at_lip');

    // Logs and boulders, each seen from just before it.
    for (final x in const [37.4, 51.8, 56.6, 66.8, 82.8]) {
      player.teleportTo(standing(x));
      step(game, 2.5);
      await shot(tester, game, player, 'props', 'x${x.round()}');
    }

    // Pulling the heavy crate backwards.
    final heavy = game.world.descendants().whereType<PhysicsCrate>().firstWhere(
      (c) => c.massKg > 20,
    );
    // Next to it, facing it: take hold and back away dragging it.
    player.teleportTo(standing(heavy.body.position.x - heavy.size.x / 2 - 0.3));
    step(game, 0.5);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyE);
    step(game, 0.2);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    step(game, 0.4);
    await burst(tester, game, player, 'pull', 16, every: 1 / 15);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyE);
  });

  testWidgets('environment along the level', (tester) async {
    final (game, player) = await boot(tester);
    final level = game.world.descendants().whereType<Level>().single;
    for (final x in const [6.0, 22.0, 37.0, 52.0, 68.0, 86.0]) {
      final double y = level.terrain.heightAt(x)!;
      player.teleportTo(Vector2(x, y - GameConfig.playerHeight / 2));
      step(game, 2.5);
      await shot(tester, game, player, 'environment', 'x${x.round()}');
    }
  });
}
