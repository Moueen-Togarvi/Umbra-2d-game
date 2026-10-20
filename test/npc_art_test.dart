import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:flame/flame.dart';
import 'package:umbra/render/npc_atlas.dart';
import 'package:umbra/story/figures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('mother reference cutout is transparent and loads', () async {
    final mother = Mother();
    await mother.load();
    expect(mother.hasArtwork, isTrue);
    final art = await Flame.images.load('characters/mother_reference.png');
    final data = (await art.toByteData(format: ImageByteFormat.rawRgba))!;
    var transparent = 0;
    for (var i = 3; i < data.lengthInBytes; i += 4) {
      if (data.getUint8(i) == 0) transparent++;
    }
    expect(transparent / (art.width * art.height), greaterThan(.4));
  });

  test('mother reaches once and ignores later reach requests', () {
    final mother = Mother()..reach = 1;
    var peak = 0.0;
    for (var i = 0; i < 240; i++) {
      mother.update(1 / 60);
      if (mother.reachProgress > peak) peak = mother.reachProgress;
    }
    expect(peak, 1);
    expect(mother.gestureComplete, isTrue);
    expect(mother.reachProgress, 0);
    mother.reach = 0;
    mother.update(1);
    mother.reach = 1;
    mother.update(1);
    expect(mother.reachProgress, 0);
  });

  test('sprite sockets stay on their joints when rotated or cropped', () async {
    final art = await NpcAtlas.load('vampire');
    for (final segment in [
      (
        part: 3,
        start: const Offset(.57, .12),
        end: const Offset(.44, .94),
        crop: null,
      ),
      (
        part: 4,
        start: const Offset(.27, .08),
        end: const Offset(.52, .86),
        crop: null,
      ),
      (
        part: 5,
        start: const Offset(.31, .065),
        end: const Offset(.68, .80),
        crop: null,
      ),
      (
        part: 7,
        start: const Offset(.32 / .56, .065 / .70),
        end: const Offset(.27 / .56, .69 / .70),
        crop: const Rect.fromLTWH(0, 0, .56, .70),
      ),
    ]) {
      for (final end in [
        const Offset(155, 110),
        const Offset(70, 165),
        const Offset(150, 40),
      ]) {
        const start = Offset(60, 60);
        final recorder = PictureRecorder();
        art.bone(
          Canvas(recorder),
          segment.part,
          start,
          end,
          28,
          Paint(),
          startAnchor: segment.start,
          endAnchor: segment.end,
          sourceUV: segment.crop,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(220, 220);
        final pixels = (await image.toByteData(
          format: ImageByteFormat.rawRgba,
        ))!;
        for (final joint in [start, end]) {
          var covered = false;
          for (var y = joint.dy.toInt() - 2; y <= joint.dy + 2; y++) {
            for (var x = joint.dx.toInt() - 2; x <= joint.dx + 2; x++) {
              covered |= pixels.getUint8((y * 220 + x) * 4 + 3) > 200;
            }
          }
          expect(covered, isTrue, reason: 'part ${segment.part}, joint $joint');
        }
        image.dispose();
        picture.dispose();
      }
    }
  });

  for (final name in ['vampire']) {
    test(
      '$name puppet has eight isolated parts with real transparency',
      () async {
        final art = await NpcAtlas.load(name);
        expect(identical(art, await NpcAtlas.load(name)), isTrue);
        expect(art.parts.length, 8);
        final data = (await art.image.toByteData(
          format: ImageByteFormat.rawRgba,
        ))!;
        var transparent = 0;
        for (var i = 3; i < data.lengthInBytes; i += 4) {
          if (data.getUint8(i) == 0) transparent++;
        }
        expect(
          transparent / (art.image.width * art.image.height),
          greaterThan(.4),
        );
        for (final part in art.parts) {
          expect(part.width, greaterThan(20));
          expect(part.height, greaterThan(20));
          expect(part.width, lessThan(art.image.width / 4));
          expect(part.height, lessThan(art.image.height / 2));
        }
      },
    );
  }
}
