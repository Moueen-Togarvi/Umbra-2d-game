import 'package:flame/components.dart';

import '../chapters/chapter.dart';

/// A scripted moment: the boy and the camera do what the story needs while
/// the player watches.
///
/// A scene is a list of [Beat]s played one after another. While it runs it
/// holds the controls (the touch buttons hide and keys do nothing) unless
/// [lockControls] is off, which suits a moment that happens around him
/// while he plays on, like a bat swarm passing.
class Cutscene {
  Cutscene(this.beats, {this.lockControls = true, this.onEnd});

  final List<Beat> beats;
  final bool lockControls;
  final void Function()? onEnd;

  late Chapter _chapter;
  int _index = -1;
  bool _done = false;
  double _time = 0;

  /// Seconds since the scene started.
  double get time => _time;

  void start(Chapter chapter) {
    _chapter = chapter;
    if (lockControls) chapter.intent.beginScript();
    _advance();
  }

  /// Plays the scene on by [dt]; true once it has finished.
  bool update(double dt) {
    if (_done) return true;
    _time += dt;
    // Several instant beats can run in one frame.
    for (var guard = 0; guard < 32 && !_done; guard++) {
      if (!beats[_index].tick(_chapter, dt)) return false;
      beats[_index].end(_chapter);
      dt = 0;
      _advance();
    }
    return _done;
  }

  void _advance() {
    _index++;
    if (_index >= beats.length) {
      _finish();
      return;
    }
    beats[_index].begin(_chapter);
  }

  /// Ends the scene where it is.
  void stop() {
    if (_done) return;
    if (_index >= 0 && _index < beats.length) beats[_index].end(_chapter);
    _finish();
  }

  void _finish() {
    _done = true;
    if (lockControls) {
      _chapter.intent.setScriptState(
        axis: 0,
        jump: false,
        interact: false,
        up: false,
        down: false,
      );
      _chapter.intent.endScript();
    }
    onEnd?.call();
  }
}

/// One step of a [Cutscene].
abstract class Beat {
  void begin(Chapter chapter) {}

  /// Advances by [dt]; true when the beat is over.
  bool tick(Chapter chapter, double dt);
  void end(Chapter chapter) {}
}

/// Nothing, for a while.
class Wait extends Beat {
  Wait(this.seconds);
  final double seconds;
  double _t = 0;
  @override
  void begin(Chapter chapter) => _t = 0;
  @override
  bool tick(Chapter chapter, double dt) => (_t += dt) >= seconds;
}

/// Something done at once.
class Do extends Beat {
  Do(this.action);
  final void Function(Chapter chapter) action;
  @override
  bool tick(Chapter chapter, double dt) {
    action(chapter);
    return true;
  }
}

/// Waits for [condition], or at most [timeout] seconds.
class WaitUntil extends Beat {
  WaitUntil(this.condition, {this.timeout = 20});
  final bool Function(Chapter chapter) condition;
  final double timeout;
  double _t = 0;
  @override
  void begin(Chapter chapter) => _t = 0;
  @override
  bool tick(Chapter chapter, double dt) =>
      condition(chapter) || (_t += dt) >= timeout;
}

/// The boy runs one way ([axis] −1 or 1) until he passes [toX], or for
/// [seconds] when no x is given; then lets go.
class Run extends Beat {
  Run(this.axis, {this.toX, this.seconds = 30});
  final double axis;
  final double? toX;
  final double seconds;
  double _t = 0;
  @override
  void begin(Chapter chapter) {
    _t = 0;
    chapter.intent.setScriptState(axis: axis);
  }

  @override
  bool tick(Chapter chapter, double dt) {
    _t += dt;
    final double? x = toX;
    final double at = chapter.player.body.position.x;
    if (x != null && (axis > 0 ? at >= x : at <= x)) return true;
    return _t >= seconds;
  }

  @override
  void end(Chapter chapter) => chapter.intent.setScriptState(axis: 0);
}

/// The camera looks at [focus] (null: back to following the boy).
class Look extends Beat {
  Look(this.focus);
  final Vector2? focus;
  @override
  bool tick(Chapter chapter, double dt) {
    chapter.cameraFocus = focus?.clone();
    return true;
  }
}

/// The picture fades to [target] blackness over [seconds].
class Fade extends Beat {
  Fade(this.target, this.seconds);
  final double target, seconds;
  late double _from;
  double _t = 0;
  @override
  void begin(Chapter chapter) {
    _from = chapter.blackness;
    _t = 0;
  }

  @override
  bool tick(Chapter chapter, double dt) {
    _t += dt;
    final double p = seconds <= 0 ? 1 : (_t / seconds).clamp(0.0, 1.0);
    final double s = p * p * (3 - 2 * p);
    chapter.blackness = _from + (target - _from) * s;
    return p >= 1;
  }
}

/// Several beats at once; over when all are.
class Together extends Beat {
  Together(this.beats);
  final List<Beat> beats;
  final Set<Beat> _done = {};
  @override
  void begin(Chapter chapter) {
    _done.clear();
    for (final beat in beats) {
      beat.begin(chapter);
    }
  }

  @override
  bool tick(Chapter chapter, double dt) {
    for (final beat in beats) {
      if (_done.contains(beat)) continue;
      if (beat.tick(chapter, dt)) {
        beat.end(chapter);
        _done.add(beat);
      }
    }
    return _done.length == beats.length;
  }
}

/// Beats one after another, as one beat (for use inside [Together]).
class Sequence extends Beat {
  Sequence(this.beats);
  final List<Beat> beats;
  int _i = 0;
  @override
  void begin(Chapter chapter) {
    _i = 0;
    if (beats.isNotEmpty) beats[0].begin(chapter);
  }

  @override
  bool tick(Chapter chapter, double dt) {
    while (_i < beats.length) {
      if (!beats[_i].tick(chapter, dt)) return false;
      beats[_i].end(chapter);
      dt = 0;
      if (++_i < beats.length) beats[_i].begin(chapter);
    }
    return true;
  }
}
