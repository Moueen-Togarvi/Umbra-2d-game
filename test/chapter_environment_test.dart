import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/caves.dart';
import 'package:umbra/chapters/great_gate.dart';
import 'package:umbra/chapters/home.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/input/player_intent.dart';

void main() {
  test('chapter surface material identifies open, cave, and castle spaces', () {
    final intent = PlayerIntent();

    expect(HomeChapter(intent: intent).grassy, isTrue);
    expect(CavesChapter(intent: intent).grassy, isFalse);
    expect(GreatGateChapter(intent: intent).footing, 'stone');
    expect(JourneyChapter(intent: intent, number: 2).grassy, isTrue);
    expect(JourneyChapter(intent: intent, number: 12).grassy, isFalse);
    expect(JourneyChapter(intent: intent, number: 36).grassy, isTrue);
  });
}
