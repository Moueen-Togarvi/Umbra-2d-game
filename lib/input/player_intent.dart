/// Held controls and one-shot actions, independent of keys and physics bodies.
/// Sources stay separate so releasing a key cannot cancel a held touch button.
///
/// The vocabulary is deliberately the one LIMBO has: move, jump and a single
/// action. The boy always runs; there is no run button and no crouch. "Up"
/// and "down" climb a rope; down also lets go of a ledge.
///
/// A cutscene takes the controls with [beginScript]: from then until
/// [endScript] the player reads only what the script sets, and presses on
/// the keyboard or screen change nothing.
class PlayerIntent {
  double _keyboardAxis = 0, _touchAxis = 0;
  bool _keyboardJump = false, _touchJump = false;
  bool _keyboardInteract = false, _touchInteract = false;
  bool _keyboardDown = false, _touchDown = false;
  bool _keyboardUp = false, _touchUp = false;
  bool _scripted = false;
  double _scriptAxis = 0;
  bool _scriptJump = false, _scriptInteract = false;
  bool _scriptDown = false, _scriptUp = false;

  /// Whether a cutscene has the controls.
  bool get isScripted => _scripted;

  double get horizontalAxis =>
      _scripted ? _scriptAxis : (_keyboardAxis + _touchAxis).clamp(-1.0, 1.0);
  bool get isJumpHeld => _scripted ? _scriptJump : _keyboardJump || _touchJump;
  bool get isInteractHeld =>
      _scripted ? _scriptInteract : _keyboardInteract || _touchInteract;
  bool get isDownHeld => _scripted ? _scriptDown : _keyboardDown || _touchDown;
  bool get isUpHeld => _scripted ? _scriptUp : _keyboardUp || _touchUp;
  bool _jumpRequested = false;
  bool _jumpFromUp = false;

  /// Whether the last jump request came from an up key (W or ↑), which on
  /// a rope climbs instead of jumping off.
  bool get lastJumpFromUp => _jumpFromUp;
  bool _interactRequested = false, _interactReleaseRequested = false;
  bool _resetRequested = false, _debugRequested = false;
  bool _knockdownRequested = false;
  bool _audioRequested = false;

  void setKeyboardState({
    double? axis,
    bool? jump,
    bool? interact,
    bool? down,
    bool? up,
  }) {
    final wasInteracting = isInteractHeld;
    if (axis != null) _keyboardAxis = axis;
    if (jump != null) _keyboardJump = jump;
    if (interact != null) _keyboardInteract = interact;
    if (down != null) _keyboardDown = down;
    if (up != null) _keyboardUp = up;
    if (!_scripted) _interactionEdge(wasInteracting);
  }

  void setTouchState({
    double? axis,
    bool? jump,
    bool? interact,
    bool? down,
    bool? up,
  }) {
    final wasInteracting = isInteractHeld;
    if (axis != null) _touchAxis = axis;
    if (jump != null) _touchJump = jump;
    if (interact != null) _touchInteract = interact;
    if (down != null) _touchDown = down;
    if (up != null) _touchUp = up;
    if (!_scripted) _interactionEdge(wasInteracting);
  }

  /// Hands the controls to a script, letting go of anything held.
  void beginScript() {
    if (_scripted) return;
    final wasInteracting = isInteractHeld;
    _scripted = true;
    _scriptAxis = 0;
    _scriptJump = _scriptInteract = _scriptDown = _scriptUp = false;
    _jumpRequested = _interactRequested = false;
    _interactionEdge(wasInteracting);
  }

  /// Gives the controls back. Keys and buttons still held take effect at
  /// once, as if just pressed.
  void endScript() {
    if (!_scripted) return;
    final wasInteracting = isInteractHeld;
    _scripted = false;
    _jumpRequested = false;
    _interactionEdge(wasInteracting);
  }

  /// What the script is holding.
  void setScriptState({
    double? axis,
    bool? jump,
    bool? interact,
    bool? down,
    bool? up,
  }) {
    if (!_scripted) return;
    final wasInteracting = isInteractHeld;
    if (axis != null) _scriptAxis = axis;
    if (jump != null) _scriptJump = jump;
    if (interact != null) _scriptInteract = interact;
    if (down != null) _scriptDown = down;
    if (up != null) _scriptUp = up;
    _interactionEdge(wasInteracting);
  }

  void _interactionEdge(bool wasHeld) {
    if (!wasHeld && isInteractHeld) requestInteract();
    if (wasHeld && !isInteractHeld) requestInteractRelease();
  }

  void requestInteract() => _interactRequested = true;
  void requestInteractRelease() => _interactReleaseRequested = true;
  void requestReset() {
    if (!_scripted) _resetRequested = true;
  }

  void requestDebugToggle() => _debugRequested = true;
  void requestKnockdown() {
    if (!_scripted) _knockdownRequested = true;
  }

  void requestAudioToggle() => _audioRequested = true;

  void requestJump({bool fromUp = false}) {
    if (_scripted) return;
    _jumpRequested = true;
    _jumpFromUp = fromUp;
  }

  bool consumeJumpRequest() {
    final value = _jumpRequested;
    _jumpRequested = false;
    return value;
  }

  bool consumeInteractRequest() {
    final value = _interactRequested;
    _interactRequested = false;
    return value;
  }

  bool consumeInteractRelease() {
    final value = _interactReleaseRequested;
    _interactReleaseRequested = false;
    return value;
  }

  bool consumeResetRequest() {
    final value = _resetRequested;
    _resetRequested = false;
    return value;
  }

  bool consumeDebugToggleRequest() {
    final value = _debugRequested;
    _debugRequested = false;
    return value;
  }

  bool consumeKnockdownRequest() {
    final value = _knockdownRequested;
    _knockdownRequested = false;
    return value;
  }

  bool consumeAudioToggleRequest() {
    final value = _audioRequested;
    _audioRequested = false;
    return value;
  }

  /// Focus loss clears held controls; an active grab still receives a release.
  void clear() {
    final release = isInteractHeld || _interactReleaseRequested;
    _keyboardAxis = _touchAxis = 0;
    _keyboardJump = _touchJump = false;
    _keyboardInteract = _touchInteract = false;
    _keyboardDown = _touchDown = false;
    _keyboardUp = _touchUp = false;
    _jumpRequested = _interactRequested = false;
    _jumpFromUp = false;
    _resetRequested = _debugRequested = _knockdownRequested = false;
    _audioRequested = false;
    _interactReleaseRequested = release;
  }
}
