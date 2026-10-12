import 'package:flame/components.dart';
import 'package:flutter/services.dart';

import 'player_intent.dart';

/// Translates raw keyboard events into a [PlayerIntent].
///
/// This is the only file in the project that knows a keyboard exists. It never
/// touches a physics body; it only writes intentions, which the [Player] entity
/// reads on its own schedule during the update loop.
///
/// It is a [Component] with no visual presence, added directly to the game so
/// that `HasKeyboardHandlerComponents` can route events to it.
class KeyboardInput extends Component with KeyboardHandler {
  KeyboardInput(this._intent);

  final PlayerIntent _intent;

  /// Both WASD and the arrow keys, so the game feels right to either habit.
  static final Set<LogicalKeyboardKey> _leftKeys = {
    LogicalKeyboardKey.arrowLeft,
    LogicalKeyboardKey.keyA,
  };

  static final Set<LogicalKeyboardKey> _rightKeys = {
    LogicalKeyboardKey.arrowRight,
    LogicalKeyboardKey.keyD,
  };

  static final Set<LogicalKeyboardKey> _jumpKeys = {
    LogicalKeyboardKey.space,
    LogicalKeyboardKey.arrowUp,
    LogicalKeyboardKey.keyW,
  };

  @override
  bool onKeyEvent(KeyEvent event, Set<LogicalKeyboardKey> keysPressed) {
    // Horizontal movement is read from the full set of currently-held keys
    // rather than from this single event. That way, holding left and then
    // pressing and releasing right leaves the player still walking left, which
    // is what a player expects.
    final bool isMovingLeft = keysPressed.any(_leftKeys.contains);
    final bool isMovingRight = keysPressed.any(_rightKeys.contains);
    _intent.setKeyboardState(
      axis: (isMovingRight ? 1.0 : 0.0) - (isMovingLeft ? 1.0 : 0.0),
      jump: keysPressed.any(_jumpKeys.contains),
      run:
          keysPressed.contains(LogicalKeyboardKey.shiftLeft) ||
          keysPressed.contains(LogicalKeyboardKey.shiftRight),
      interact: keysPressed.contains(LogicalKeyboardKey.keyE),
      crouch:
          keysPressed.contains(LogicalKeyboardKey.keyS) ||
          keysPressed.contains(LogicalKeyboardKey.arrowDown),
    );

    // Jump is edge-triggered, so only a genuine key-down counts. Checking for
    // KeyDownEvent specifically also excludes KeyRepeatEvent, which the OS
    // fires while a key is held and which would otherwise machine-gun jumps.
    if (event is KeyDownEvent && _jumpKeys.contains(event.logicalKey)) {
      _intent.requestJump();
    }
    if (event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.keyR:
          _intent.requestReset();
        case LogicalKeyboardKey.f1:
          _intent.requestDebugToggle();
        case LogicalKeyboardKey.keyK:
          _intent.requestKnockdown();
        case LogicalKeyboardKey.keyM:
          _intent.requestAudioToggle();
        case LogicalKeyboardKey.digit1:
          _intent.requestPreset(0);
        case LogicalKeyboardKey.digit2:
          _intent.requestPreset(1);
        case LogicalKeyboardKey.digit3:
          _intent.requestPreset(2);
      }
    }

    // Returning true lets the event continue to other handlers. Nothing else
    // consumes keys yet, but blocking propagation here would be a confusing
    // thing to debug later.
    return true;
  }
}
