// The boy's rig drawn large in a few postures, black on white, to judge a
// pose by eye:
//   flutter test tool/capture/pose_sheet_test.dart
// Writes build/chapters-preview/poses.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/render/character_silhouette.dart';

void main() {
  testWidgets('poses', (tester) async {
    const double h = GameConfig.playerHeight;
    final figure = CharacterSilhouette(height: h);
    // As the controller passes them: feet planted on the ground (y 0.5),
    // out in front when sitting.
    CharacterPose planted({
      double crouch = 0,
      double sit = 0,
      double gait = 0,
    }) => CharacterPose(
      crouch: crouch,
      sit: sit,
      gait: gait,
      gaitPhase: 1.1,
      frontFoot: gait > 0 ? null : ui.Offset(0.07 + 0.15 * sit, 0.5),
      backFoot: gait > 0 ? null : ui.Offset(-0.06 + 0.11 * sit, 0.5),
    );
    final poses = [
      ('standing', planted()),
      ('half sit', planted(sit: 0.5)),
      ('sitting', planted(sit: 1)),
      ('crouched', planted(crouch: 1)),
      ('creeping', planted(crouch: 1, gait: 0.27)),
    ];
    const double cell = 360, scale = 220; // px per metre
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..drawColor(const ui.Color(0xFFF2F0EA), ui.BlendMode.src);
    final ground = ui.Paint()..color = const ui.Color(0xFF999999);
    final capsule = ui.Paint()
      ..color = const ui.Color(0xFFCC4444)
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale;
    for (var i = 0; i < poses.length; i++) {
      final (name, pose) = poses[i];
      canvas.save();
      canvas.translate(cell * i + cell / 2, cell * 0.55);
      canvas.scale(scale);
      canvas.drawRect(ui.Rect.fromLTWH(-0.8, h / 2, 1.6, 0.01), ground);
      // The capsule he has in that posture.
      final double ch =
          h * (pose.sit > 0 || pose.crouch > 0 ? GameConfig.lowHeightRatio : 1);
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
          ui.Rect.fromLTWH(-0.21, h / 2 - ch, 0.42, ch),
          const ui.Radius.circular(0.21),
        ),
        capsule,
      );
      figure.drawRig(canvas, figure.solve(pose));
      final head = figure.solve(pose).joints[RigJoint.head]!;
      // ignore: avoid_print
      print(
        '$name: drawn top ${(h / 2 - head.y + CharacterRig.headRadius * h * 1.15).toStringAsFixed(3)} m',
      );
      canvas.restore();
      final label = ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 14))
        ..pushStyle(ui.TextStyle(color: const ui.Color(0xFF333333)))
        ..addText(name);
      canvas.drawParagraph(
        label.build()..layout(const ui.ParagraphConstraints(width: 200)),
        ui.Offset(cell * i + 12, 12),
      );
    }
    final picture = recorder.endRecording();
    final bytes = await tester.runAsync(() async {
      final image = await picture.toImage(
        (cell * poses.length).toInt(),
        cell.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });
    Directory('build/chapters-preview').createSync(recursive: true);
    File('build/chapters-preview/poses.png').writeAsBytesSync(bytes!);
  });
}
