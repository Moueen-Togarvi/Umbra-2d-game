import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapters.dart';
import 'package:umbra/input/player_intent.dart';
import 'package:umbra/render/chapter_backgrounds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every chapter has four usable, distinct background areas', () async {
    expect(ChapterBackgrounds.all.length, Chapters.all.length);
    for (var i = 0; i < Chapters.all.length; i++) {
      final chapter = Chapters.all[i].build(PlayerIntent());
      final plan = chapter.backgroundPlan;
      expect(plan.number, i + 1);
      expect(plan.areas.length, 4);
      expect(plan.areas.map((a) => a.name).toSet().length, 4);
      expect(plan.areas.first.start, 0);
      for (var j = 1; j < 4; j++) {
        expect(plan.areas[j].start - plan.areas[j - 1].start, greaterThan(8));
        expect(plan.areas[j].start + 4, lessThan(chapter.width));
      }
      final codec = await ui.instantiateImageCodec(
        await File(plan.asset).readAsBytes(),
      );
      final image = (await codec.getNextFrame()).image;
      expect(image.width, greaterThanOrEqualTo(1600));
      expect(image.height, greaterThanOrEqualTo(900));
      image.dispose();
      codec.dispose();
    }
  });

  test(
    'crossfades are continuous, reversible, bounded, and reach each scene',
    () {
      for (final plan in ChapterBackgrounds.all) {
        expect(plan.blendAt(-10).from, 0);
        expect(plan.blendAt(10000).from, 3);
        for (var i = 1; i < 4; i++) {
          final x = plan.areas[i].start;
          expect(plan.blendAt(x - 4).mix, 0);
          expect(plan.blendAt(x).mix, .5);
          expect(plan.blendAt(x + 4).from, i);
          expect(plan.blendAt(x + 3.999).mix, closeTo(1, .000001));
          final forward = [for (var k = -4; k < 4; k++) plan.blendAt(x + k)];
          final reverse = [for (var k = 3; k >= -4; k--) plan.blendAt(x + k)];
          expect(forward, reverse.reversed.toList());
          for (var k = 1; k < forward.length; k++) {
            expect(forward[k].mix, greaterThan(forward[k - 1].mix));
          }
        }
      }
    },
  );

  test('background replacement keeps surface dressing', () {
    final plan = ChapterBackgrounds.forChapter(2);
    expect(plan.replacesProp('part1/ch2_giant_tree_a.png', .92), isTrue);
    expect(plan.replacesProp('distant_arch.png', .5), isTrue);
    expect(plan.replacesProp('part4/ch10_clock_face.png', .97), isTrue);
    expect(plan.replacesProp('part4/ch14_dead_tree_wind.png', .92), isTrue);
    expect(plan.replacesProp('surface_rock.png', 1), isFalse);
    expect(plan.replacesProp('well.png', .95), isFalse);
    expect(plan.replacesProp('part1/ch2_giant_tree_a.png', 1), isFalse);
  });
}
