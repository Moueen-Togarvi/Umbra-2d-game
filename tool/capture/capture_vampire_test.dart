// Deterministic captures of the production vampire renderer for visual review.
// Run once before the edit and once after with VAMPIRE_REVIEW=before/after.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/render/mood.dart';
import 'package:umbra/render/npc_atlas.dart';
import 'package:umbra/story/vampire.dart';

import 'capture_chapters_test.dart' show loadFonts;

const version = String.fromEnvironment('VAMPIRE_REVIEW', defaultValue: 'after');
const hoverReview = bool.fromEnvironment('VAMPIRE_HOVER_REVIEW');
const reviewDirectory = String.fromEnvironment(
  'VAMPIRE_REVIEW_DIR',
  defaultValue: 'build/review-results/vampire-refine-v2',
);
const width = 960, height = 640, fps = 20;
final output = Directory('$reviewDirectory/$version');

void label(
  ui.Canvas canvas,
  String text,
  double x,
  double y, {
  double size = 18,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: text,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: size,
        color: const ui.Color(0xFFDDDDDD),
      ),
    ),
    textDirection: ui.TextDirection.ltr,
  )..layout();
  painter.paint(canvas, ui.Offset(x, y));
}

Future<void> frame(Vampire vampire, String title, String path) async {
  if (hoverReview) {
    title = title
        .replaceAll('Idle', 'Hover')
        .replaceAll('idle', 'hover')
        .replaceAll('Walk', 'Glide')
        .replaceAll('walk', 'glide')
        .replaceAll('chase', 'pursuit')
        .replaceAll('crouch', 'settle');
  }
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 960, 640),
    ui.Paint()
      ..shader = ui.Gradient.linear(ui.Offset.zero, const ui.Offset(0, 640), [
        const ui.Color(0xFF424647),
        const ui.Color(0xFF858887),
      ]),
  );
  label(canvas, '${version.toUpperCase()} / $title', 30, 24, size: 24);
  label(
    canvas,
    'Actual game renderer / same pose and timing',
    30,
    59,
    size: 14,
  );
  canvas.drawLine(
    const ui.Offset(50, 578),
    const ui.Offset(490, 578),
    ui.Paint()..color = const ui.Color(0xFF323536),
  );
  void draw(double x, double y, double scale) {
    canvas.save();
    canvas.translate(x, y);
    canvas.scale(scale);
    canvas.translate(-vampire.x, -vampire.groundY);
    vampire.paint(canvas, Vector2(vampire.x, vampire.groundY), Mood.night);
    canvas.restore();
  }

  draw(270, 578, 211);
  const close = ui.Rect.fromLTWH(530, 210, 400, 350);
  canvas.drawRect(close, ui.Paint()..color = const ui.Color(0xFF686D6C));
  canvas.save();
  canvas.clipRect(close);
  final pose = title.toLowerCase();
  final raised = pose.contains('reach') || pose.contains('shield');
  draw(
    730 - vampire.facing.sign * (raised ? 170 : 80),
    raised
        ? 962
        : (pose.contains('crouch') || pose.contains('landing') ? 700 : 815),
    355,
  );
  canvas.restore();
  label(canvas, 'Hands / 1.7x', 545, 177, size: 16);
  label(canvas, '2D side view', 210, 601, size: 15);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  await File(path).writeAsBytes(data!.buffer.asUint8List());
  image.dispose();
  picture.dispose();
}

Future<Vampire> actor(double facing) async {
  final vampire = Vampire(x: 0, groundY: 0, facing: facing);
  await vampire.onLoad();
  for (var i = 0; i < 240; i++) {
    vampire.update(1 / 120);
  }
  return vampire;
}

void main() {
  testWidgets('vampire leg artwork inspection', (tester) async {
    await tester.runAsync(() async {
      output.createSync(recursive: true);
      await loadFonts();
      final art = await NpcAtlas.load('vampire');
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawColor(const ui.Color(0xFF777D79), ui.BlendMode.src);
      for (var column = 0; column < 2; column++) {
        final left = 50.0 + column * 440;
        art.draw(
          canvas,
          column + 6,
          ui.Rect.fromLTWH(left, 50, 320, 570),
          ui.Paint(),
        );
        for (var i = 1; i < 10; i++) {
          final u = i / 10;
          final line = ui.Paint()..color = const ui.Color(0x667AFFBA);
          canvas.drawLine(
            ui.Offset(left + 320 * u, 50),
            ui.Offset(left + 320 * u, 620),
            line,
          );
          canvas.drawLine(
            ui.Offset(left, 50 + 570 * u),
            ui.Offset(left + 320, 50 + 570 * u),
            line,
          );
          label(canvas, '$u', left + 320 * u, 20, size: 12);
          label(canvas, '$u', left + 325, 50 + 570 * u, size: 12);
        }
      }
      final picture = recorder.endRecording();
      final image = await picture.toImage(880, 660);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File(
        '${output.path}/leg-sockets.png',
      ).writeAsBytes(data!.buffer.asUint8List());
      image.dispose();
      picture.dispose();
    });
  });

  testWidgets('vampire comparison stills and motion', (tester) async {
    await tester.runAsync(() async {
      output.createSync(recursive: true);
      Directory('${output.path}/frames').createSync(recursive: true);
      await File('lib/story/vampire.dart').copy('${output.path}/vampire.dart');
      await File(
        'lib/render/npc_atlas.dart',
      ).copy('${output.path}/npc_atlas.dart');
      await loadFonts();
      final art = await NpcAtlas.load('vampire');
      final rgba = (await art.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final profiles = <Object>[];
      for (final part in [1, 3, 4, 5]) {
        final bounds = art.parts[part];
        final rows = <Object>[];
        for (final fraction in [.05, .1, .2, .5, .75, .85, .95]) {
          final y = (bounds.top + bounds.height * fraction).floor();
          final xs = <int>[];
          for (var x = bounds.left.toInt(); x < bounds.right; x++) {
            if (rgba.getUint8((y * art.image.width + x) * 4 + 3) > 150) {
              xs.add(x);
            }
          }
          rows.add({
            'y': fraction,
            'left': xs.isEmpty ? null : (xs.first - bounds.left) / bounds.width,
            'right': xs.isEmpty ? null : (xs.last - bounds.left) / bounds.width,
          });
        }
        profiles.add({'part': part, 'rows': rows});
      }
      await File(
        '${output.path}/atlas-profile.json',
      ).writeAsString(jsonEncode(profiles));
      final detail = ui.PictureRecorder();
      final detailCanvas = ui.Canvas(detail);
      detailCanvas.drawColor(const ui.Color(0xFF777D79), ui.BlendMode.src);
      art.draw(
        detailCanvas,
        1,
        const ui.Rect.fromLTWH(50, 50, 320, 570),
        ui.Paint(),
      );
      for (var i = 1; i < 10; i++) {
        final u = i / 10;
        final line = ui.Paint()..color = const ui.Color(0x667AFFBA);
        detailCanvas.drawLine(
          ui.Offset(50 + 320 * u, 50),
          ui.Offset(50 + 320 * u, 620),
          line,
        );
        detailCanvas.drawLine(
          ui.Offset(50, 50 + 570 * u),
          ui.Offset(370, 50 + 570 * u),
          line,
        );
        label(detailCanvas, '$u', 50 + 320 * u, 20, size: 12);
        label(detailCanvas, '$u', 375, 50 + 570 * u, size: 12);
      }
      final detailPicture = detail.endRecording();
      final detailImage = await detailPicture.toImage(440, 660);
      final detailData = await detailImage.toByteData(
        format: ui.ImageByteFormat.png,
      );
      await File(
        '${output.path}/torso-sockets.png',
      ).writeAsBytes(detailData!.buffer.asUint8List());
      detailImage.dispose();
      detailPicture.dispose();
      for (final facing in [-1.0, 1.0]) {
        for (final pose in [
          'idle',
          'walk',
          'chase',
          'reach',
          'shield',
          'crouch',
        ]) {
          final vampire = await actor(facing);
          if (pose == 'reach') vampire.reachGoal = 1;
          if (pose == 'shield') vampire.shieldGoal = 1;
          if (pose == 'crouch') vampire.dropFrom(.1);
          for (var i = 0; i < (pose == 'crouch' ? 32 : 180); i++) {
            if (pose == 'walk' || pose == 'chase') {
              vampire.drive(
                x: vampire.x + facing * (pose == 'chase' ? 3.2 : 1.1) / 120,
                groundY: 0,
                dt: 1 / 120,
              );
            }
            vampire.update(1 / 120);
          }
          final direction = facing < 0 ? 'left' : 'right';
          await frame(
            vampire,
            '$pose / $direction',
            '${output.path}/$pose-$direction.png',
          );
          vampire.onRemove();
        }
      }
      final vampire = await actor(1);
      const seconds = 20;
      var caption = '';
      for (var n = 0; n < seconds * fps; n++) {
        for (var sub = 0; sub < 6; sub++) {
          final t = (n * 6 + sub) / 120;
          vampire.reachGoal = 0;
          vampire.shieldGoal = 0;
          if (t < 2) {
            caption = 'Idle / right';
            vampire.mode = VampireMode.stand;
          } else if (t < 5) {
            caption = 'Walk / right';
            vampire.drive(x: vampire.x + 1.1 / 120, groundY: 0, dt: 1 / 120);
          } else if (t < 7.5) {
            caption = 'Reach / right';
            vampire.mode = VampireMode.stand;
            vampire.reachGoal = 1;
          } else if (t < 10) {
            caption = 'Shield / right';
            vampire.mode = VampireMode.stand;
            vampire.shieldGoal = 1;
          } else if (t < 13) {
            caption = 'Turn + fast chase / left';
            vampire.drive(x: vampire.x - 3.2 / 120, groundY: 0, dt: 1 / 120);
          } else if (t < 15) {
            caption = 'Reach + release / left';
            vampire.mode = VampireMode.stand;
            vampire.reachGoal = t < 14.5 ? 1 : 0;
          } else if (t < 18) {
            caption = 'Drop + landing recovery / left';
            if (vampire.mode != VampireMode.drop) vampire.dropFrom(.65);
          } else {
            caption = 'Rest / left';
            vampire.mode = VampireMode.stand;
          }
          vampire.update(1 / 120);
        }
        await frame(
          vampire,
          caption,
          '${output.path}/frames/${n.toString().padLeft(4, '0')}.png',
        );
      }
      vampire.onRemove();
      await File('${output.path}/manifest.json').writeAsString(
        jsonEncode({
          'version': version,
          'fps': fps,
          'frames': seconds * fps,
          'renderer': 'lib/story/vampire.dart',
          'views': ['left', 'right', 'hand close-up'],
          'poses': ['idle', 'walk', 'chase', 'reach', 'shield', 'crouch'],
        }),
      );
    });
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
