import '../config/game_config.dart';
import '../entities/player.dart';
import 'checkpoint_service.dart';

/// LIMBO's death beat, start to finish.
///
/// The limp body lies where it fell for a moment, the picture fades to
/// black, the boy is put back at the last checkpoint while the screen is
/// dark, and the picture fades back in. There is no game-over screen and no
/// counter: dying is how you learn the trap, and it costs a few seconds.
///
/// Plain Dart so the timing is easy to test; the game feeds it frame time
/// and reads [blackness] for the [ScreenFade].
class DeathSequence {
  DeathSequence({required this.checkpoints});

  final CheckpointService checkpoints;

  /// 0 for a clear picture, 1 for black.
  double blackness = 0;

  double _clock = -1;
  bool _respawned = false;

  static const double _linger = GameConfig.deathLingerSeconds;
  static const double _fadeOut = GameConfig.deathFadeOutSeconds;
  static const double _black = GameConfig.deathBlackSeconds;
  static const double _fadeIn = GameConfig.deathFadeInSeconds;

  void update(double dt, Player player) {
    if (_clock < 0) {
      if (!player.isDead) {
        blackness = 0;
        return;
      }
      _clock = 0;
      _respawned = false;
    }
    // Brought back some other way (a reset) before the fade finished.
    if (!_respawned && !player.isDead) {
      cancel();
      return;
    }
    _clock += dt;
    final double t = _clock;
    if (t < _linger) {
      blackness = 0;
    } else if (t < _linger + _fadeOut) {
      blackness = _smooth((t - _linger) / _fadeOut);
    } else if (!_respawned) {
      checkpoints.respawn(player);
      _respawned = true;
      blackness = 1;
    } else if (t < _linger + _fadeOut + _black) {
      blackness = 1;
    } else if (t < _linger + _fadeOut + _black + _fadeIn) {
      blackness = 1 - _smooth((t - _linger - _fadeOut - _black) / _fadeIn);
    } else {
      blackness = 0;
      _clock = -1;
    }
  }

  /// Abandons a sequence in progress, e.g. on a manual reset.
  void cancel() {
    _clock = -1;
    blackness = 0;
  }

  static double _smooth(double x) {
    final double t = x.clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }
}
