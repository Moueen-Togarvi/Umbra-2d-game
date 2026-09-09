/// What the player is currently asking the character to do.
///
/// This class is the seam between input and physics, and it is deliberately
/// dumb: it knows nothing about keyboards, and nothing about bodies, forces or
/// Box2D. It is a small bag of *intentions*.
///
/// Keeping this in the middle buys us three things:
///
/// 1. The [Player] entity has no idea which key was pressed, so adding a
///    gamepad or on-screen touch controls later means writing one new input
///    component and changing nothing else.
/// 2. The input layer cannot accidentally reach into the physics world and
///    move a body directly, which is the usual way these two concerns end up
///    tangled together.
/// 3. It can be constructed in a test to drive the player without a keyboard.
class PlayerIntent {
  /// Desired horizontal movement: -1 for left, +1 for right, 0 for neither.
  ///
  /// A continuous *state* rather than an event: it stays set for as long as the
  /// key is held.
  double horizontalAxis = 0;

  /// Whether a jump has been requested since the last time it was read.
  ///
  /// Unlike [horizontalAxis], a jump is an *event*, not a state. It is set once
  /// on the key press and cleared the moment the player entity reads it, so
  /// holding the jump key down cannot produce a second jump.
  bool _jumpRequested = false;

  /// Records a jump request. Called by the input layer on key-down.
  void requestJump() => _jumpRequested = true;

  /// Reads and clears the pending jump request.
  ///
  /// Returns true at most once per press. The caller must act on it
  /// immediately, because the request is gone afterwards — that is what stops a
  /// press made in mid-air from being saved up and spent on landing.
  bool consumeJumpRequest() {
    if (!_jumpRequested) {
      return false;
    }
    _jumpRequested = false;
    return true;
  }
}
