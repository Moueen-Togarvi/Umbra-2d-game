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

  /// After the end: two red eyes opening in the dark, how far open
  /// (0–1), and the small line under them.
  double eyes = 0, eyesOpen = 1, eyesCaption = 0;

  /// The credits, after "The End": each a small line and a large one.
  static const List<(String, String)> credits = [
    ('A GAME BY', 'Moueen Togarvi'),
    ('MADE WITH', 'Flutter · Flame · Box2D'),
    ('SILHOUETTES', 'Generated with Wan, baked by hand'),
    ('SOUND', 'Kenney · rubberduck · and the OpenGameArt community, CC0'),
    ('FOOTSTEPS', 'Generated with ElevenLabs'),
    ('BACKGROUND PAINTINGS', 'Generated with OpenAI'),
    ('MUSIC BY SCOTT BUCKLEY · CC-BY 4.0', 'Eyes In The Void · Decoherence'),
    ('MUSIC BY SCOTT BUCKLEY · CC-BY 4.0', 'Descent · In Search Of Solitude'),
    ('MUSIC BY SCOTT BUCKLEY · CC-BY 4.0', 'The Distant Sun'),
    (
      'MUSIC, CC0',
      'HaelDB · cynicmusic · Juhani Junkala · kindland · cinameng',
    ),
    ('IN THE SHADOW OF', 'LIMBO'),
    ('THANK YOU', 'for playing'),
  ];

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
    unawaited(progress.enter(0));
    first.onCheckpoint = (id) => progress.saveCheckpoint(first.id, id);
    first.startStory();
    _playing = true;
    _then(_Wait(1.2));
    _then(_Fade((v) => cardAlpha = v, 0, 1, 1.4));
    _then(_Wait(2.6));
    _then(_Fade((v) => cardAlpha = v, 1, 0, 1.6));
  }

  /// "Continue", or a chapter picked from the list.
  void playChapter(int i, {bool resume = false}) {
    if (isBusy) return;
    _showTitle(false);
    _playing = false;
    _then(_Fade((v) => blackness = v, blackness, 1, 0.9));
    _enter(i, resume: resume);
  }

  void _enter(int i, {bool resume = false}) {
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
        await progress.enter(i, resume: resume);
        final active = chapter;
        if (active != null) {
          active.onCheckpoint = (id) => progress.saveCheckpoint(active.id, id);
          if (resume && progress.checkpoint != null) {
            active.resumeAt(progress.checkpoint!);
          } else {
            active.startStory();
          }
        }
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
        if (Chapters.all.length >= Chapters.story) {
          // The whole story told.
          cardSmall = 'UMBRA';
          cardTitle = 'The End';
          game.music('ending');
        } else {
          // Three chapters to a part.
          cardSmall =
              'END OF PART ${Chapters.numberWord((Chapters.all.length + 2) ~/ 3)}';
          cardTitle = 'To be continued';
        }
        cardOnBlack = true;
      }),
    );
    _then(_Fade((v) => cardAlpha = v, 0, 1, 1.2));
    _then(_Wait(3.5));
    _then(_Fade((v) => cardAlpha = v, 1, 0, 1.2));
    if (Chapters.all.length >= Chapters.story) {
      _creditsAndAfter();
    }
    _then(_Await(start));
  }

  /// The credits under the music; then, in the dark, a pair of eyes.
  static const endingSeconds = 60.0;
  static const endCardSeconds = 5.9;
  void _creditsAndAfter() {
    for (final (small, title) in credits) {
      _then(
        _Call(() {
          cardSmall = small;
          cardTitle = title;
          cardOnBlack = true;
        }),
      );
      _then(_Fade((v) => cardAlpha = v, 0, 1, 1.0));
      _then(_Wait((endingSeconds - endCardSeconds) / credits.length - 2));
      _then(_Fade((v) => cardAlpha = v, 1, 0, 1.0));
    }
    _then(_Call(() => game.music(null)));
    _then(_Wait(1.6));
    _then(_Call(() => game.sound('heartbeat')));
    _then(_Fade((v) => eyes = v, 0, 1, 2.2));
    _then(_Call(() => game.sound('heartbeat', 0.8)));
    _then(_Wait(1.0));
    // One slow blink.
    _then(_Fade((v) => eyesOpen = v, 1, 0, 0.12));
    _then(_Fade((v) => eyesOpen = v, 0, 1, 0.2));
    _then(_Fade((v) => eyesCaption = v, 0, 1, 1.4));
    _then(_Wait(2.6));
    _then(
      _Fade(
        (v) {
          eyes = v;
          eyesCaption = v;
        },
        1,
        0,
        1.6,
      ),
    );
    _then(_Wait(0.8));
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
      dt = op.unusedTime;
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
  double unusedTime = 0;
  void start() {}

  /// Advances by [dt]; true when done.
  bool tick(double dt);
}

class _Wait extends _Op {
  _Wait(this.seconds);
  final double seconds;
  double _t = 0;
  @override
  bool tick(double dt) {
    _t += dt;
    unusedTime = (_t - seconds).clamp(0.0, dt);
    return _t >= seconds;
  }
}

class _Call extends _Op {
  _Call(this.action);
  final void Function() action;
  @override
  bool tick(double dt) {
    action();
    unusedTime = dt;
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
    unusedTime = (_t - seconds).clamp(0.0, dt);
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
