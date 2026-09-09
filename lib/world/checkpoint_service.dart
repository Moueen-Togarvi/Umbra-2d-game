import 'package:flame_forge2d/flame_forge2d.dart';

import '../entities/player.dart';

/// Owns the "where does the player come back to life" question.
///
/// This is deliberately a plain class rather than a component. It holds no
/// physics state of its own, it just remembers a position and knows how to send
/// the player there. Keeping it separate means the respawn rule stays in one
/// readable place while hazards, water and anything else that can kill the
/// player accumulate around it.
///
/// Every later step in the roadmap must leave this working: if the player can
/// still die and come back cleanly, the step did not break anything important.
class CheckpointService {
  CheckpointService({required Vector2 initialCheckpoint})
    : _activeCheckpoint = initialCheckpoint.clone();

  Vector2 _activeCheckpoint;

  /// The position the player will respawn at.
  ///
  /// Returns a copy: [Vector2] is mutable, and handing out the internal
  /// instance would let a caller move the checkpoint by accident.
  Vector2 get activeCheckpoint => _activeCheckpoint.clone();

  /// Records a new respawn point, e.g. when the player reaches a checkpoint.
  void setCheckpoint(Vector2 position) {
    _activeCheckpoint = position.clone();
  }

  /// Sends the player back to the active checkpoint, at rest.
  void respawn(Player player) {
    player.teleportTo(_activeCheckpoint);
  }
}
