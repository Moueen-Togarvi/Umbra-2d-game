import '../input/player_intent.dart';
import 'cage.dart';
import 'chapter.dart';
import 'forest.dart';
import 'home.dart';

/// One chapter in the story's running order: its name for the card and
/// the list, and how to build it.
class ChapterEntry {
  const ChapterEntry(this.title, this._build);
  final String title;
  final Chapter Function(PlayerIntent intent, bool atTitle) _build;

  Chapter build(PlayerIntent intent, {bool atTitle = false}) =>
      _build(intent, atTitle);
}

/// The chapters that exist, in order.
abstract final class Chapters {
  static final List<ChapterEntry> all = [
    ChapterEntry(
      'Home',
      (intent, atTitle) => HomeChapter(intent: intent, atTitle: atTitle),
    ),
    ChapterEntry(
      'The Night Forest',
      (intent, atTitle) => ForestChapter(intent: intent),
    ),
    ChapterEntry('The Cage', (intent, atTitle) => CageChapter(intent: intent)),
  ];

  static const List<String> _words = [
    'ZERO', 'ONE', 'TWO', 'THREE', 'FOUR', 'FIVE', 'SIX', 'SEVEN', 'EIGHT', //
    'NINE', 'TEN', 'ELEVEN', 'TWELVE', 'THIRTEEN', 'FOURTEEN', 'FIFTEEN',
  ];

  /// "ONE" for 1, up to the fifteen chapters of the story.
  static String numberWord(int n) =>
      n >= 0 && n < _words.length ? _words[n] : '$n';
}
