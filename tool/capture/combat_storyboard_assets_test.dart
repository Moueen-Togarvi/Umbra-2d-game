// Generates transparent production-renderer figures for the HTML combat
// storyboard. Run with:
//   flutter test tool/capture/combat_storyboard_assets_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/render/character_silhouette.dart';
import 'package:umbra/render/mood.dart';
import 'package:umbra/story/vampire.dart';

const output = 'tool/capture/combat_storyboard_assets';

Future<void> savePicture(
  ui.Picture picture,
  String name,
  int width,
  int height,
) async {
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File('$output/$name.png').writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

CharacterPose grounded({
  double gait = 0,
  double phase = 0,
  double crouch = 0,
  double sit = 0,
  double push = 0,
  double effort = 0,
  double bodyLean = 0,
  ui.Offset? frontHand,
  ui.Offset? backHand,
}) => CharacterPose(
  gait: gait,
  gaitPhase: phase,
  crouch: crouch,
  sit: sit,
  push: push,
  effort: effort,
  bodyLean: bodyLean,
  frontFoot: gait == 0 ? const ui.Offset(.07, .5) : null,
  backFoot: gait == 0 ? const ui.Offset(-.06, .5) : null,
  frontHand: frontHand,
  backHand: backHand,
);

Future<void> hero(String name, CharacterPose pose) async {
  const width = 280, height = 390;
  const scale = 210.0;
  const h = GameConfig.playerHeight;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..translate(width / 2, height - 20 - scale * h / 2)
    ..scale(scale);
  CharacterSilhouette(height: h).draw(canvas, pose);
  await savePicture(recorder.endRecording(), 'hero-$name', width, height);
}

Future<void> enemy(
  String name, {
  double reach = 0,
  bool burning = false,
}) async {
  const width = 360, height = 460;
  final vampire = Vampire(x: 0, groundY: 0, facing: -1)..reachGoal = reach;
  await vampire.onLoad();
  if (burning) vampire.burn();
  for (var i = 0; i < (burning ? 95 : 240); i++) {
    vampire.update(1 / 120);
  }
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder)
    ..translate(width / 2, height - 25)
    ..scale(175);
  vampire.paint(canvas, Vector2.zero(), Mood.night);
  await savePicture(recorder.endRecording(), 'enemy-$name', width, height);
}

void main() {
  testWidgets('production figures for combat storyboard', (tester) async {
    await tester.runAsync(() async {
      Directory(output).createSync(recursive: true);
      await hero('idle', grounded());
      await hero('run', grounded(gait: .9, phase: 1.35, bodyLean: .12));
      await hero(
        'jump',
        const CharacterPose(
          gait: .55,
          gaitPhase: 2.2,
          air: 1,
          fallLean: -.7,
          armAir: 1,
          takeoff: .55,
          bodyLean: .12,
        ),
      );
      await hero('crouch', grounded(crouch: 1, gait: .15, phase: 4.1));
      await hero(
        'push',
        grounded(
          push: 1,
          effort: .8,
          bodyLean: .26,
          frontHand: const ui.Offset(.34, -.05),
          backHand: const ui.Offset(.31, .02),
        ),
      );
      await hero(
        'swing',
        const CharacterPose(
          air: 1,
          hanging: 1,
          hangLow: 1,
          swingKick: .9,
          bodyLean: -.22,
          frontHand: ui.Offset(.07, -.57),
          backHand: ui.Offset(-.03, -.58),
        ),
      );
      await hero('sit', grounded(sit: 1));
      await hero(
        'brace',
        grounded(
          crouch: .45,
          bodyLean: -.2,
          frontHand: const ui.Offset(.25, -.16),
          backHand: const ui.Offset(.21, -.08),
        ),
      );
      await hero(
        'strike',
        grounded(
          bodyLean: .2,
          frontHand: const ui.Offset(.43, -.10),
          backHand: const ui.Offset(.19, -.03),
        ),
      );
      await hero(
        'parry',
        grounded(
          crouch: .25,
          bodyLean: -.12,
          frontHand: const ui.Offset(.28, -.31),
          backHand: const ui.Offset(.22, -.22),
        ),
      );
      await hero(
        'air-strike',
        const CharacterPose(
          air: 1,
          fallLean: .25,
          bodyLean: .28,
          frontHand: ui.Offset(.39, -.08),
          backHand: ui.Offset(.18, -.01),
        ),
      );
      await hero(
        'throw',
        grounded(
          bodyLean: .16,
          frontHand: const ui.Offset(.42, -.19),
          backHand: const ui.Offset(.10, -.08),
        ),
      );
      await enemy('idle');
      await enemy('reach', reach: 1);
      await enemy('burn', reach: .4, burning: true);
    });
  });
}
