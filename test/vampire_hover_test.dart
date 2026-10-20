import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/render/mood.dart';
import 'package:umbra/story/vampire.dart';

Future<ByteData> pixels(Vampire vampire, {double scale = 100}) async {
  final recorder = PictureRecorder();
  final canvas = Canvas(recorder)
    ..translate(160, 300)
    ..scale(scale);
  vampire.paint(canvas, Vector2.zero(), Mood.night);
  final picture = recorder.endRecording();
  final image = await picture.toImage(320, 320);
  final data = (await image.toByteData(format: ImageByteFormat.rawRgba))!;
  image.dispose();
  picture.dispose();
  return data;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final facing in [-1.0, 1.0]) {
    test('red eye stays visible at gameplay scale: $facing', () async {
      final vampire = Vampire(x: 0, groundY: 0, facing: facing, fog: .25);
      await vampire.onLoad();
      for (var i = 0; i < 120; i++) {
        vampire.update(1 / 60);
      }
      int redPixels(ByteData data) {
        var count = 0;
        for (var i = 0; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) > 150 &&
              data.getUint8(i + 1) < 85 &&
              data.getUint8(i + 2) < 85 &&
              data.getUint8(i + 3) > 100) {
            count++;
          }
        }
        return count;
      }

      expect(
        redPixels(await pixels(vampire, scale: 64)),
        greaterThanOrEqualTo(3),
      );
      vampire.eyes = 0;
      expect(redPixels(await pixels(vampire, scale: 64)), 0);
      vampire.onRemove();
    });

    test(
      'hovering vampire has only translucent mist near the floor: $facing',
      () async {
        final vampire = Vampire(x: 0, groundY: 0, facing: facing);
        await vampire.onLoad();
        for (var i = 0; i < 120; i++) {
          vampire.update(1 / 60);
        }
        final data = await pixels(vampire);
        var bodyPixels = 0, mistPixels = 0;
        for (var y = 20; y < 240; y++) {
          for (var x = 50; x < 270; x++) {
            if (data.getUint8((y * 320 + x) * 4 + 3) > 200) bodyPixels++;
          }
        }
        for (var y = 277; y < 300; y++) {
          for (var x = 20; x < 300; x++) {
            final alpha = data.getUint8((y * 320 + x) * 4 + 3);
            expect(
              alpha,
              lessThan(180),
              reason: 'Opaque legs/boots at ($x,$y)',
            );
            if (alpha > 3) mistPixels++;
          }
        }
        expect(bodyPixels, greaterThan(400));
        expect(mistPixels, greaterThan(50));
        expect(
          data.getUint8((290 * 320 + 2) * 4 + 3),
          0,
          reason: 'Mist must stay local to the enemy',
        );

        vampire.lift = 1.4;
        final airborne = await pixels(vampire);
        for (var y = 277; y < 300; y++) {
          for (var x = 20; x < 300; x++) {
            expect(
              airborne.getUint8((y * 320 + x) * 4 + 3),
              0,
              reason: 'A distant airborne vampire must not fog the floor',
            );
          }
        }
        vampire.onRemove();
      },
    );
  }
}
