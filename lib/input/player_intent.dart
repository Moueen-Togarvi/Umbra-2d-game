/// Held controls and one-shot actions, independent of keys and physics bodies.
/// Sources stay separate so releasing a key cannot cancel a held touch button.
class PlayerIntent {
  double _keyboardAxis = 0, _touchAxis = 0;
  bool _keyboardJump = false, _touchJump = false;
  bool _keyboardRun = false, _touchRun = false;
  bool _keyboardInteract = false, _touchInteract = false;
  bool _keyboardCrouch = false, _touchCrouch = false;
  double get horizontalAxis => (_keyboardAxis + _touchAxis).clamp(-1.0, 1.0);
  set horizontalAxis(double value) => _keyboardAxis = value.clamp(-1.0, 1.0);
  bool get isJumpHeld => _keyboardJump || _touchJump;
  set isJumpHeld(bool value) => _keyboardJump = value;
  bool get isRunHeld => _keyboardRun || _touchRun;
  set isRunHeld(bool value) => _keyboardRun = value;
  bool get isInteractHeld => _keyboardInteract || _touchInteract;
  set isInteractHeld(bool value) => setKeyboardState(interact: value);
  bool get isCrouchHeld => _keyboardCrouch || _touchCrouch;
  set isCrouchHeld(bool value) => _keyboardCrouch = value;
  bool _jumpRequested = false;
  bool _interactRequested = false, _interactReleaseRequested = false;
  bool _resetRequested = false, _debugRequested = false;
  bool _knockdownRequested = false;
  bool _audioRequested = false;
  int? _presetRequested;

  void setKeyboardState({
    double? axis,
    bool? jump,
    bool? run,
    bool? interact,
    bool? crouch,
  }) {
    final wasInteracting = isInteractHeld;
    if (axis != null) _keyboardAxis = axis;
    if (jump != null) _keyboardJump = jump;
    if (run != null) _keyboardRun = run;
    if (interact != null) _keyboardInteract = interact;
    if (crouch != null) _keyboardCrouch = crouch;
    _interactionEdge(wasInteracting);
  }

  void setTouchState({
    double? axis,
    bool? jump,
    bool? run,
    bool? interact,
    bool? crouch,
  }) {
    final wasInteracting = isInteractHeld;
    if (axis != null) _touchAxis = axis;
    if (jump != null) _touchJump = jump;
    if (run != null) _touchRun = run;
    if (interact != null) _touchInteract = interact;
    if (crouch != null) _touchCrouch = crouch;
    _interactionEdge(wasInteracting);
  }

  void _interactionEdge(bool wasHeld) {
    if (!wasHeld && isInteractHeld) requestInteract();
    if (wasHeld && !isInteractHeld) requestInteractRelease();
  }

  void requestInteract() => _interactRequested = true;
  void requestInteractRelease() => _interactReleaseRequested = true;
  void requestReset() => _resetRequested = true;
  void requestDebugToggle() => _debugRequested = true;
  void requestKnockdown() => _knockdownRequested = true;
  void requestAudioToggle() => _audioRequested = true;
  void requestPreset(int index) => _presetRequested = index;

  void requestJump() => _jumpRequested = true;

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

  int? consumePresetRequest() {
    final value = _presetRequested;
    _presetRequested = null;
    return value;
  }

  /// Focus loss clears held controls; an active grab still receives a release.
  void clear() {
    final release = isInteractHeld || _interactReleaseRequested;
    _keyboardAxis = _touchAxis = 0;
    _keyboardJump = _touchJump = false;
    _keyboardRun = _touchRun = false;
    _keyboardInteract = _touchInteract = false;
    _keyboardCrouch = _touchCrouch = false;
    _jumpRequested = _interactRequested = false;
    _resetRequested = _debugRequested = _knockdownRequested = false;
    _audioRequested = false;
    _presetRequested = null;
    _interactReleaseRequested = release;
  }
}
