import 'dart:async';

import '../chapters/chapter.dart';
import '../chapters/chapters.dart';
import '../game/umbra_game.dart';
import 'progress_store.dart';

/// Runs the story: the title over the first scene, the card before each
/// chapter, the fades between them and the end of the part.
///
/// Every transition is a queue of small steps — fade this, wait that long,
/// load the next chapter — played in game time from [update], so it runs
/// the same at any frame rate and in tests.
class ChapterDirector {
  ChapterDirector({required this.game, required this.progress});

  final UmbraGame game;
  final ProgressStore progress;

  /// The overlay the title screen is drawn in.
  static const String titleOverlay = 'title';

  /// The chapter being played (from 0).
  int index = 0;

  /// Black over everything, for the fades between chapters.
  double blackness = 1;

  /// The card on screen: its two lines and how visible it is. [cardOnBlack]
  /// puts a black ground under it; otherwise it is laid over the scene.
  String cardSmall = '', cardTitle = '';
  double cardAlpha = 0;
  bool cardOnBlack = true;

  bool _playing = false;
  bool _showingTitle = false;

  /// Whether the title screen is up.
  bool get showingTitle => _showingTitle;

  /// Whether the boy is the player's to move.
  bool get isPlaying => _playing;

  /// The play buttons stay hidden until a chapter is under way.
  bool get hidesControls => !_playing;

  /// Whether a transition is under way.
  bool get isBusy => _queue.isNotEmpty;

  Chapter? get chapter => switch (game.stage) {
    final Chapter c => c,
    _ => null,
  };

  final List<_Op> _queue = [];

  /// Opens on the title: the first chapter's opening shot, waiting.
  Future<void> start() async {
    _queue.clear();
    cardAlpha = 0;
    blackness = 1;
    index = 0;
    _playing = false;
    await game.setStage(Chapters.all[0].build(game.intent, atTitle: true));
    _showTitle(true);
    _then(_Fade((v) => blackness = v, 1, 0, 2.4));
  }

  /// "Begin": the story from the start, straight out of the title scene.
  void begin() {
    if (isBusy) return;
    final Chapter? first = chapter;
    if (first == null || first.number != 1 || !_showingTitle) {
      playChapter(0);
      return;
    }
    _showTitle(false);
    index = 0;
    // The title is already the first scene: the card is laid over it
    // while the opening plays.
    _setCard(0, onBlack: false);
    first.startStory();
    _playing = true;
    _then(_Wait(1.2));
    _then(_Fade((v) => cardAlpha = v, 0, 1, 1.4));
    _then(_Wait(2.6));
    _then(_Fade((v) => cardAlpha = v, 1, 0, 1.6));
  }

  /// "Continue", or a chapter picked from the list.
  void playChapter(int i) {
    if (isBusy) return;
    _showTitle(false);
    _playing = false;
    _then(_Fade((v) => blackness = v, blackness, 1, 0.9));
    _enter(i);
  }

  void _enter(int i) {
    _then(
      _Call(() {
        index = i;
        _setCard(i, onBlack: true);
      }),
    );
    _then(_Fade((v) => cardAlpha = v, 0, 1, 0.9));
    _then(
      _Await(() async {
        await game.setStage(Chapters.all[i].build(game.intent));
        await progress.reach(i);
        chapter?.startStory();
      }),
    );
    _then(_Wait(1.8));
    _then(_Fade((v) => cardAlpha = v, 1, 0, 0.9));
    _then(_Call(() => _playing = true));
    _then(_Fade((v) => blackness = v, 1, 0, 1.3));
  }

  void _next() {
    _playing = false;
    _then(_Fade((v) => blackness = v, blackness, 1, 1.2));
    if (index + 1 < Chapters.all.length) {
      _enter(index + 1);
      return;
    }
    // The end of what exists so far, then back to the title.
    _then(
      _Call(() {
        // Three chapters to a part.
        cardSmall =
            'END OF PART ${Chapters.numberWord((Chapters.all.length + 2) ~/ 3)}';
        cardTitle = 'To be continued';
        cardOnBlack = true;
      }),
    );
    _then(_Fade((v) => cardAlpha = v, 0, 1, 1.2));
    _then(_Wait(3.5));
    _then(_Fade((v) => cardAlpha = v, 1, 0, 1.2));
    _then(_Await(start));
  }

  void update(double dt) {
    // Several instant steps can run in one frame.
    for (var guard = 0; guard < 16 && _queue.isNotEmpty; guard++) {
      final _Op op = _queue.first;
      if (!op.started) {
        op.started = true;
        op.start();
      }
      if (!op.tick(dt)) break;
      _queue.removeAt(0);
      dt = 0;
    }
    final Chapter? c = chapter;
    if (_playing && !isBusy && c != null && c.isComplete) _next();
  }

  void _then(_Op op) => _queue.add(op);

  void _showTitle(bool show) {
    _showingTitle = show;
    if (!game.overlays.registeredOverlays.contains(titleOverlay)) return;
    if (show) {
      game.overlays.add(titleOverlay);
    } else {
      game.overlays.remove(titleOverlay);
    }
  }

  void _setCard(int i, {required bool onBlack}) {
    cardSmall = 'CHAPTER ${Chapters.numberWord(i + 1)}';
    cardTitle = Chapters.all[i].title;
    cardOnBlack = onBlack;
  }
}

abstract class _Op {
  bool started = false;
  void start() {}

  /// Advances by [dt]; true when done.
  bool tick(double dt);
}

class _Wait extends _Op {
  _Wait(this.seconds);
  final double seconds;
  double _t = 0;
  @override
  bool tick(double dt) => (_t += dt) >= seconds;
}

class _Call extends _Op {
  _Call(this.action);
  final void Function() action;
  @override
  bool tick(double dt) {
    action();
    return true;
  }
}

/// Eases a value from [a] to [b] over [seconds].
class _Fade extends _Op {
  _Fade(this.set, this.a, this.b, this.seconds);
  final void Function(double) set;
  final double a, b, seconds;
  double _t = 0;
  @override
  bool tick(double dt) {
    _t += dt;
    final double p = seconds <= 0 ? 1 : (_t / seconds).clamp(0.0, 1.0);
    set(a + (b - a) * p * p * (3 - 2 * p));
    return p >= 1;
  }
}

/// Waits for something asynchronous, like loading a chapter.
class _Await extends _Op {
  _Await(this.work);
  final Future<void> Function() work;
  bool _done = false;
  @override
  void start() => unawaited(work().whenComplete(() => _done = true));
  @override
  bool tick(double dt) => _done;
}
