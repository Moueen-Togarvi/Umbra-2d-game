// Renders frames of the story chapters to PNG for visual review. Not part of
// the test suite; run it on demand:
//
//   flutter test tool/capture/capture_chapters_test.dart [--plain-name tour]
//
// Frames go to build/chapters-preview/<scene>/.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/game.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/cage.dart';
import 'package:umbra/chapters/chandeliers.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/chapters/dawn.dart';
import 'package:umbra/chapters/chase.dart';
import 'package:umbra/chapters/forest.dart';
import 'package:umbra/chapters/halls.dart';
import 'package:umbra/chapters/home.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/story/chapter_director.dart';
import 'package:umbra/story/figures.dart';
import 'package:umbra/story/vampire.dart';
import 'package:umbra/render/mood.dart';
import 'package:umbra/ui/title_screen.dart';
import 'package:umbra/ui/pause_screen.dart';

const int width = 1600, height = 720;
final Directory out = Directory('build/chapters-preview');

Future<void> loadFonts() async {
  final loader = FontLoader('Cinzel')
    ..addFont(rootBundle.load('assets/fonts/Cinzel-Variable.ttf'));
  await loader.load();
  // Flutter widget tests otherwise replace platform fonts with Ahem squares.
  final cache = Directory(
    '${File(Platform.resolvedExecutable).parent.path}/../../..',
  );
  final roboto = File(
    '${cache.path}/dart-sdk/bin/resources/devtools/assets/packages/devtools_app_shared/fonts/Roboto/Roboto-Regular.ttf',
  );
  await (FontLoader('Roboto')..addFont(
        Future.value(ByteData.sublistView(await roboto.readAsBytes())),
      ))
      .load();
  await (FontLoader(
    'MaterialIcons',
  )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
}

void main() {
  final GlobalKey frame = GlobalKey();

  Future<UmbraGame> boot(
    WidgetTester tester, {
    Size viewport = const Size(1600, 720),
  }) async {
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.runAsync(loadFonts);
    final game = UmbraGame(campaign: true);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: viewport),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: RepaintBoundary(
            key: frame,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData.dark(),
              home: GameWidget<UmbraGame>(
                game: game,
                overlayBuilderMap: {
                  ChapterDirector.titleOverlay: (context, game) =>
                      TitleScreen(game: game),
                  UmbraGame.pauseOverlay: (context, game) =>
                      PauseScreen(game: game),
                },
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 60 && game.stage?.isLoaded != true; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });
    return game;
  }

  void step(UmbraGame game, double seconds) {
    for (var i = 0; i < (seconds * 60).round(); i++) {
      game.update(1 / 60);
    }
  }

  Future<void> shot(
    WidgetTester tester,
    UmbraGame game,
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
  }

  /// The whole widget tree, overlays included.
  Future<void> screen(WidgetTester tester, String scene, String name) async {
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // The engine is paused, so the game's box does not repaint by itself.
    void dirty(RenderObject o) {
      o.markNeedsPaint();
      o.visitChildren(dirty);
    }

    dirty(boundary);
    await tester.pump();
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final dir = Directory('${out.path}/$scene')..createSync(recursive: true);
    File('${dir.path}/$name.png').writeAsBytesSync(bytes!);
  }

  testWidgets('title', (tester) async {
    final game = await boot(tester);
    step(game, 3);
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await screen(tester, 'title', 'title');
    await shot(tester, game, 'title', 'game_only');
    await tester.tap(find.text('Chapters'));
    await tester.pump(const Duration(milliseconds: 350));
    await screen(tester, 'title', 'chapters');
    // ignore: avoid_print
    print(
      'blackness ${game.blackness} director ${game.director!.blackness} '
      'stage ${game.stage!.blackness} death ${game.deathSequence.blackness} '
      'cam ${game.camera.viewfinder.position}',
    );
  });

  testWidgets('opening', (tester) async {
    final game = await boot(tester);
    step(game, 3);
    final director = game.director!;
    director.begin();
    for (var i = 0; i < 64; i++) {
      await shot(tester, game, 'opening', 'f_${i.toString().padLeft(3, '0')}');
      step(game, 0.25);
    }
    expect(game.intent.isScripted, isFalse);
  });

  testWidgets('tour', (tester) async {
    final game = await boot(tester);
    step(game, 3);
    game.director!.begin();
    step(game, 17);
    final chapter = game.stage! as Chapter;
    for (final x in [
      18.0, 24.0, 29.0, 32.5, 36.5, 42.0, 45.5, 52.0, 59.0, 66.5, //
      72.0, 84.0, 96.0, 104.0, 112.0, 118.0,
    ]) {
      chapter.player.teleportTo(
        Vector2(x, chapter.groundAt(x) - GameConfig.playerHeight / 2),
      );
      step(game, 2.2);
      await shot(tester, game, 'tour', 'x_${x.toStringAsFixed(0)}');
    }
  });

  testWidgets('play', (tester) async {
    final game = await boot(tester);
    step(game, 3);
    game.director!.begin();
    for (var i = 0; i < 60 * 20 && game.intent.isScripted; i++) {
      game.update(1 / 60);
    }
    final home = game.stage! as HomeChapter;
    final player = home.player;
    final intent = game.intent;
    final jumped = <String>{};
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    var frameNo = 0;
    for (var i = 0; i < 60 * 150 && !home.isComplete; i++) {
      intent.setKeyboardState(axis: 1);
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      if (!intent.isScripted) {
        if (grounded && x > 27.5 && x < 28.4 && !jumped.contains('fence')) {
          jump('fence');
        }
        final double cartRight =
            home.cart.body.position.x + home.cart.size.x / 2;
        if (grounded &&
            cartRight > 34.1 &&
            x < 33.7 &&
            feet > 6.9 &&
            !jumped.contains('cart')) {
          jump('cart');
        }
        if (grounded &&
            jumped.contains('cart') &&
            feet < 6.6 &&
            x > 33.3 &&
            !jumped.contains('wall')) {
          jump('wall');
        }
        if (grounded && x > 46.1 && x < 46.6 && !jumped.contains('plank')) {
          jump('plank');
        }
        if (grounded &&
            x > 50.4 &&
            x < 51.2 &&
            feet > 7.0 &&
            !jumped.contains('lip')) {
          jump('lip');
        }
        if (grounded && x > 57.2 && x < 58 && !jumped.contains('log')) {
          jump('log');
        }
        if (grounded && x > 65.3 && x < 66 && !jumped.contains('gully')) {
          jump('gully');
        }
        if (mode == InteractionMode.swinging &&
            x > 68.4 &&
            player.velocity.x > 1.5 &&
            !jumped.contains('release')) {
          jump('release');
        }
        if (grounded && x > 82.3 && x < 83 && !jumped.contains('rock')) {
          jump('rock');
        }
        if (grounded && x > 92.1 && x < 92.8 && !jumped.contains('log2')) {
          jump('log2');
        }
      }
      game.update(1 / 60);
      if (i % 12 == 0) {
        await shot(
          tester,
          game,
          'play',
          'f_${(frameNo++).toString().padLeft(4, '0')}',
        );
      }
    }
  });

  testWidgets('forest tour', (tester) async {
    final game = await boot(tester);
    step(game, 3);
    game.director!.playChapter(1);
    for (var i = 0; i < 400 && !game.director!.isPlaying; i++) {
      game.update(1 / 60);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
    step(game, 3);
    await shot(tester, game, 'forest', 'start');
    final chapter = game.stage! as Chapter;
    for (final x in [
      10.0, 18.0, 33.0, 37.8, 46.0, 60.0, 65.5, 80.0, 92.5, 101.0, //
      122.0, 128.0, 142.0, 160.0, 175.0, 186.0,
    ]) {
      chapter.player.teleportTo(
        Vector2(x, chapter.groundAt(x) - GameConfig.playerHeight / 2),
      );
      step(game, 2.2);
      await shot(
        tester,
        game,
        'forest',
        'x_${x.toStringAsFixed(0).padLeft(3, '0')}',
      );
    }
  });

  Future<void> enterChapter(WidgetTester tester, UmbraGame game, int i) async {
    step(game, 3);
    game.director!.playChapter(i);
    for (var k = 0; k < 900; k++) {
      if (game.director!.isPlaying &&
          !game.director!.isBusy &&
          game.stage?.isLoaded == true) {
        break;
      }
      game.update(1 / 60);
      if (k % 4 == 0) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
    }
  }

  testWidgets('review corridor gameplay', (tester) async {
    final game = await boot(tester);
    await enterChapter(tester, game, 7);
    final halls = game.stage! as HallsChapter;
    for (var i = 0; i < 60 * 120 && halls.player.body.position.x < 32; i++) {
      game.intent.setKeyboardState(axis: 1);
      game.update(1 / 60);
      expect(halls.player.isDead, isFalse);
    }
    expect(halls.player.body.position.x, greaterThanOrEqualTo(32));
    expect(halls.cart.body.position.x, greaterThan(32));
    await shot(tester, game, 'review', 'corridor_gameplay');
  });

  testWidgets('review figures', (tester) async {
    await tester.runAsync(loadFonts);
    final mother = Mother()
      ..presence = 1
      ..reach = .25;
    final enemy = Vampire(x: 0, groundY: 0, facing: 1)..reachGoal = .2;
    await enemy.onLoad();
    for (var i = 0; i < 360; i++) {
      mother.update(1 / 120);
      enemy.update(1 / 120);
    }
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1200, 720),
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, const Offset(0, 720), const [
          Color(0xFF66696B),
          Color(0xFFA1A3A0),
        ]),
    );
    void label(String text, double x, double y, double size) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: size,
            letterSpacing: 2,
            color: const Color(0xFF202224),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(x, y));
    }

    label('UMBRA / IN-GAME FIGURES', 64, 46, 22);
    label('Mother', 245, 640, 18);
    label('Enemy', 795, 640, 18);
    canvas.save();
    canvas.translate(310, 600);
    canvas.scale(210);
    mother.render(canvas, const Rect.fromLTRB(-.41, -2.4, .41, 0));
    canvas.restore();
    canvas.save();
    canvas.translate(840, 600);
    canvas.scale(210);
    enemy.paint(canvas, Vector2.zero(), Mood.night);
    canvas.restore();
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(1200, 720);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes!.buffer.asUint8List();
    });
    picture.dispose();
    enemy.onRemove();
    final dir = Directory('${out.path}/review')..createSync(recursive: true);
    File('${dir.path}/figures.png').writeAsBytesSync(bytes!);
  });

  testWidgets('taken', (tester) async {
    final game = await boot(tester);
    await enterChapter(tester, game, 1);
    final forest = game.stage! as ForestChapter;
    forest.player.teleportTo(Vector2(184, forest.groundAt(184) - 0.65));
    step(game, 1);
    var n = 0;
    for (var i = 0; i < 60 * 12 && !forest.isComplete; i++) {
      game.intent.setKeyboardState(
        axis: forest.player.body.position.x < 190 ? 1 : 0,
      );
      game.update(1 / 60);
      if (i % 8 == 0) {
        await shot(
          tester,
          game,
          'taken',
          'f_${(n++).toString().padLeft(3, '0')}',
        );
      }
    }
  });

  for (final viewport in [const Size(1600, 720), const Size(800, 360)]) {
    testWidgets('review settings ${viewport.width.toInt()}', (tester) async {
      final game = await boot(tester, viewport: viewport);
      await enterChapter(tester, game, 1);
      step(game, 2);
      game.pauseGameplay();
      await tester.pump(const Duration(milliseconds: 100));
      await screen(tester, 'review', 'pause_${viewport.width.toInt()}');
      expect(tester.takeException(), isNull);
      game.settings.set('controlsScale', 1.2);
      game.settings.set('controlsOpacity', .9);
      game.settings.set('brightness', 1.15);
      game.resumeGameplay();
      await tester.pump(const Duration(milliseconds: 16));
      game.pauseEngine();
      step(game, .2);
      await screen(tester, 'review', 'controls_${viewport.width.toInt()}');
      game.pauseGameplay();
      await tester.pump();
      await tester.tap(find.text('MAIN MENU'));
      for (var i = 0; i < 160; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 40));
      }
      game.pauseEngine();
      step(game, 4);
      await tester.pump(const Duration(seconds: 4));
      expect(game.overlays.isActive(ChapterDirector.titleOverlay), isTrue);
      await tester.tap(find.text('Chapters'));
      await tester.pump(const Duration(milliseconds: 400));
      await screen(tester, 'review', 'chapters_${viewport.width.toInt()}');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('cage play', (tester) async {
    final game = await boot(tester);
    await enterChapter(tester, game, 2);
    final cage = game.stage! as CageChapter;
    final player = cage.player;
    final intent = game.intent;
    final jumped = <String>{};
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    var n = 0;
    for (var i = 0; i < 60 * 200 && !cage.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + 0.65;
      final bool grounded = player.isOnGround;
      double axis = 1;
      if (!intent.isScripted) {
        if (!cage.cell.isOpen) {
          final double v = cage.cell.body.linearVelocity.x;
          final double rel = x - cage.cell.body.position.x;
          axis = v.abs() < 0.05 ? 1 : -v.sign;
          if (rel > 0.5) axis = -1;
          if (rel < -0.5) axis = 1;
        } else if (x < CageChapter.ledgeX + 0.3) {
          final double near = cage.cell.body.position.x + cage.cell.width / 2;
          if (grounded &&
              near > CageChapter.ledgeX - 0.5 &&
              !jumped.contains('out')) {
            jump('out');
          }
        }
        if (grounded && x > 17.5 && x < 18.1 && !jumped.contains('beam')) {
          jump('beam');
        }
        if (grounded && x > 35.5 && x < 36.2 && !jumped.contains('step')) {
          jump('step');
        }
        if (grounded &&
            feet < 6 &&
            x > 39.4 &&
            x < 40.0 &&
            !jumped.contains('c1')) {
          jump('c1');
        }
        if (grounded &&
            x > 42.2 &&
            x < 42.7 &&
            feet < 6.2 &&
            !jumped.contains('c2')) {
          jump('c2');
        }
        if (grounded &&
            x > 44.9 &&
            x < 45.4 &&
            feet < 6.2 &&
            !jumped.contains('c3')) {
          jump('c3');
        }
        if (grounded && x > 51.8 && x < 52.3 && !jumped.contains('lever')) {
          jump('lever');
        }
        if (x > 55.6 && x < 57 && !cage.bridge.isDown) {
          axis = 0;
        }
        final guard = cage.guard;
        if (x > 71 && x < 74 && !(guard.facing > 0 && guard.x > 87)) {
          axis = 0;
        }
        if (x > 85.6 && x < 86.4 && !(guard.facing < 0 && guard.x < 84.4)) {
          axis = 0;
        }
      }
      intent.setKeyboardState(axis: axis);
      game.update(1 / 60);
      if (i % 15 == 0) {
        await shot(
          tester,
          game,
          'cage',
          'f_${(n++).toString().padLeft(4, '0')}',
        );
      }
    }
  });

  testWidgets('caves tour', (tester) async {
    final game = await boot(tester);
    await enterChapter(tester, game, 3);
    final chapter = game.stage! as Chapter;
    await shot(tester, game, 'caves', 'start');
    for (final x in [
      14.0, 21.0, 30.0, 44.0, 57.0, 66.0, 72.0, 80.0, 88.0, 100.0, //
      112.0, 119.0, 130.0, 150.0, 175.0, 194.0,
    ]) {
      chapter.player.teleportTo(
        Vector2(x, chapter.groundAt(x) - GameConfig.playerHeight / 2),
      );
      step(game, 2.4);
      await shot(
        tester,
        game,
        'caves',
        'x_${x.toStringAsFixed(0).padLeft(3, '0')}',
      );
    }
  });

  Future<void> tour(
    WidgetTester tester,
    int chapterIndex,
    String scene,
    List<double> xs, {
    double Function(double x)? ground,
  }) async {
    final game = await boot(tester);
    await enterChapter(tester, game, chapterIndex);
    final chapter = game.stage! as Chapter;
    for (final x in xs) {
      final double g = ground?.call(x) ?? chapter.groundAt(x);
      chapter.player.teleportTo(Vector2(x, g - GameConfig.playerHeight / 2));
      step(game, 2.4);
      await shot(
        tester,
        game,
        scene,
        'x_${x.toStringAsFixed(0).padLeft(3, '0')}',
      );
    }
  }

  testWidgets('crypt tour', (tester) async {
    await tour(tester, 4, 'crypt', [
      6,
      20,
      30,
      36,
      46,
      52,
      61,
      74,
      82,
      86,
      92,
      99,
      110,
      130,
      160,
      176,
    ]);
  });

  testWidgets('pit tour', (tester) async {
    await tour(tester, 5, 'pit', [
      6,
      18,
      28,
      33,
      44,
      52,
      62,
      76,
      86,
      94,
      97,
      106,
      120,
      140,
    ]);
  });

  testWidgets('chase tour', (tester) async {
    await tour(
      tester,
      6,
      'chase',
      [5, 14, 23, 27, 34, 44, 50, 57, 66, 71, 80, 87, 90, 104, 120, 130],
      ground: (x) => (x >= 63 && x < 70) || (x > 72.4 && x < 78)
          ? 5.7
          : x >= 106
          ? 4.6
          : x >= 100
          ? 5.8
          : 7.0,
    );
  });

  testWidgets('halls tour', (tester) async {
    await tour(
      tester,
      7,
      'halls',
      [4, 9.5, 16, 26, 38, 46, 51, 57, 60, 63, 66, 70, 74, 80, 90],
      ground: (x) => x >= 61
          ? 3.6
          : x >= 48 && x <= 54
          ? 4.2
          : 7.0,
    );
  });

  testWidgets('chandeliers tour', (tester) async {
    await tour(
      tester,
      8,
      'chandeliers',
      [4, 12, 17, 23, 30, 36, 44, 48, 53, 58, 63, 76, 85, 92, 110, 122],
      ground: (x) => x >= 41 && x <= 49
          ? 4.0
          : x > 32 && x < 41
          ? 7.0 - (x - 32) / 3
          : 7.0,
    );
  });

  testWidgets('castle moments', (tester) async {
    // The bookcase going over, and lying across its gap.
    var game = await boot(tester);
    await enterChapter(tester, game, 6);
    final chase = game.stage! as ChaseChapter;
    chase.player.teleportTo(Vector2(67.5, ChaseChapter.stepTop - 0.65));
    // (The keeper's scene plays first, far behind him.)
    step(game, 3);
    chase.bookcase.body.angularVelocity = 2.2;
    for (var k = 0; k < 4; k++) {
      step(game, 0.25);
      await shot(tester, game, 'moments', 'a_bookcase_$k');
    }
    step(game, 2);
    await shot(tester, game, 'moments', 'a_bookcase_down');

    // One of them burning in the moonlight.
    game = await boot(tester);
    await enterChapter(tester, game, 7);
    final halls = game.stage! as HallsChapter;
    // The rule is shown first, under the open window.
    halls.player.teleportTo(Vector2(10, HallsChapter.floor - 0.65));
    step(game, 9);
    halls.player.teleportTo(Vector2(64.6, HallsChapter.gallery - 0.65));
    halls.windows[0].open();
    halls.keeper
      ..x = 66.8
      ..groundY = HallsChapter.gallery;
    step(game, 1.2);
    halls.windows[1].open();
    for (var k = 0; k < 5; k++) {
      step(game, 0.45);
      await shot(tester, game, 'moments', 'b_moon_$k');
    }

    // The great chandelier coming down on the two in the pit.
    game = await boot(tester);
    await enterChapter(tester, game, 8);
    final hall = game.stage! as ChandeliersChapter;
    hall.player.teleportTo(Vector2(47.6, ChandeliersChapter.gallery - 0.65));
    step(game, 1);
    hall.great.release();
    for (var k = 0; k < 5; k++) {
      step(game, 0.12);
      await shot(tester, game, 'moments', 'c_fall_$k');
    }
    step(game, 2);
    await shot(tester, game, 'moments', 'c_bridge');
  });

  testWidgets('clock tour', (tester) async {
    await tour(tester, 9, 'clock', [
      4,
      12,
      17.5,
      22,
      26,
      30,
      35,
      44,
      49,
      53,
      66,
      80,
      90,
    ]);
  });

  testWidgets('children tour', (tester) async {
    await tour(tester, 10, 'children', [
      5,
      14,
      21,
      31,
      43,
      52,
      60,
      69,
      80,
      88,
      100,
    ]);
  });

  testWidgets('mill tour', (tester) async {
    await tour(tester, 11, 'mill', [
      5,
      12,
      18,
      23,
      28,
      35,
      44,
      54,
      66,
      90,
      110,
    ], ground: (x) => x >= 62 ? 4.0 : 7.0);
  });

  testWidgets('gate tour', (tester) async {
    await tour(tester, 12, 'gate', [
      5,
      12,
      18,
      23,
      28,
      36,
      44,
      53,
      60,
      72,
    ], ground: (x) => x >= 14 && x < 24 ? 5.6 : 7.0);
  });

  testWidgets('storm tour', (tester) async {
    await tour(tester, 13, 'storm', [6, 16, 28, 38, 44, 50, 56, 62, 72, 84]);
  });

  testWidgets('dawn tour', (tester) async {
    await tour(tester, 14, 'dawn', [6, 20, 36, 50, 64, 80, 96, 112, 124]);
  });

  testWidgets('finale', (tester) async {
    final game = await boot(tester);
    await enterChapter(tester, game, 14);
    final dawn = game.stage! as DawnChapter;
    dawn.player.teleportTo(
      Vector2(
        dawn.cottage.door.center.dx - 6.6,
        dawn.groundAt(dawn.cottage.door.center.dx - 6.6) - 0.65,
      ),
    );
    game.intent.setKeyboardState(axis: 1);
    step(game, 0.2);
    game.intent.setKeyboardState(axis: 0);
    for (var k = 0; k < 18; k++) {
      step(game, 0.6);
      await shot(tester, game, 'finale', 'f_${k.toString().padLeft(2, '0')}');
    }
  });
}
