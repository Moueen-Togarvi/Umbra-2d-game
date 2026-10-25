import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/input/player_intent.dart';
import 'package:umbra/render/death_feedback.dart';

void main() {
  test('each readable death cause has a distinct short message', () {
    final messages = {
      for (final cause in DeathCause.values) DeathFeedback.message(cause),
    };
    expect(messages, hasLength(DeathCause.values.length));
    expect(DeathFeedback.message(DeathCause.drowning), contains('AIR'));
    expect(DeathFeedback.message(DeathCause.vampire), contains('SEEN'));
    expect(DeathFeedback.message(DeathCause.spikes), contains('SPIKES'));
  });

  test('touch input is remembered for fair timed-puzzle windows', () {
    final intent = PlayerIntent();
    expect(intent.touchUsed, isFalse);
    intent.setKeyboardState(axis: 1);
    expect(intent.touchUsed, isFalse);
    intent.setTouchState(jump: true);
    expect(intent.touchUsed, isTrue);
  });

  test('journey rooms vary elevation and repeated staging safely', () {
    final chapter = JourneyChapter(intent: PlayerIntent(), number: 31);
    expect(chapter.rooms.first.floor, 7);
    expect(
      chapter.rooms.map((room) => room.floor).toSet().length,
      greaterThan(2),
    );
    expect(
      chapter.rooms.map((room) => room.variant).toSet().length,
      greaterThan(1),
    );

    final returnChapter = JourneyChapter(intent: PlayerIntent(), number: 36);
    final loop = returnChapter.rooms.firstWhere(
      (room) => room.kind == PuzzleKind.returnLoop,
    );
    expect(
      loop.floor,
      7,
      reason: 'connected upper/lower route keeps authored clearance',
    );
  });
}
