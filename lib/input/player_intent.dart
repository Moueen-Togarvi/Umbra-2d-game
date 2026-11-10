/// Held controls and one-shot actions, independent of keys and physics bodies.
/// Sources stay separate so releasing a key cannot cancel a held touch button.
///
/// The vocabulary is close to LIMBO's: move, jump and a single action, and
/// one more: sit. The boy always runs; held still, sit sits him down on the
/// ground, and held while moving he crouches and creeps. "Up" and "down"
/// climb a rope; down also lets go of a ledge.
///
/// A cutscene takes the controls with [beginScript]: from then until
/// [endScript] the player reads only what the script sets, and presses on
/// the keyboard or screen change nothing.
class PlayerIntent {
  /// True after this run has received a real touch control. Timed puzzles use
  /// it to leave a little room for a thumb covering part of the screen.
  bool touchUsed = false;
  int actionAttempts = 0;
  double _keyboardAxis = 0, _touchAxis = 0;
  bool _keyboardJump = false, _touchJump = false;
  bool _keyboardInteract = false, _touchInteract = false;
  bool _keyboardDown = false, _touchDown = false;
  bool _keyboardUp = false, _touchUp = false;
  bool _keyboardSit = false, _touchSit = false;
  bool _keyboardAttack = false, _touchAttack = false;
  bool _scripted = false;
  double _scriptAxis = 0;
  bool _scriptJump = false, _scriptInteract = false;
  bool _scriptDown = false, _scriptUp = false, _scriptSit = false;

  /// Whether a cutscene has the controls.
  bool get isScripted => _scripted;

  double get horizontalAxis =>
      _scripted ? _scriptAxis : (_keyboardAxis + _touchAxis).clamp(-1.0, 1.0);
  bool get isJumpHeld => _scripted ? _scriptJump : _keyboardJump || _touchJump;
  bool get isInteractHeld =>
      _scripted ? _scriptInteract : _keyboardInteract || _touchInteract;
  bool get isDownHeld => _scripted ? _scriptDown : _keyboardDown || _touchDown;
  bool get isUpHeld => _scripted ? _scriptUp : _keyboardUp || _touchUp;
  bool get isSitHeld => _scripted ? _scriptSit : _keyboardSit || _touchSit;
  bool get isAttackHeld => !_scripted && (_keyboardAttack || _touchAttack);
  bool _jumpRequested = false;
  bool _jumpFromUp = false;

  /// Whether the last jump request came from an up key (W or ↑), which on
  /// a rope climbs instead of jumping off.
  bool get lastJumpFromUp => _jumpFromUp;
  bool _interactRequested = false, _interactReleaseRequested = false;
  bool _resetRequested = false, _debugRequested = false;
  bool _knockdownRequested = false;
  bool _audioRequested = false;
  bool _attackRequested = false, _cycleWeaponRequested = false;
  int? _weaponSlotRequested;

  void setKeyboardState({
    double? axis,
    bool? jump,
    bool? interact,
    bool? down,
    bool? up,
    bool? sit,
    bool? attack,
  }) {
    final wasInteracting = isInteractHeld;
    if (axis != null) _keyboardAxis = axis;
    if (jump != null) _keyboardJump = jump;
    if (interact != null) _keyboardInteract = interact;
    if (down != null) _keyboardDown = down;
    if (up != null) _keyboardUp = up;
    if (sit != null) _keyboardSit = sit;
    if (attack != null) _keyboardAttack = attack;
    if (!_scripted) _interactionEdge(wasInteracting);
  }

  void setTouchState({
    double? axis,
    bool? jump,
    bool? interact,
    bool? down,
    bool? up,
    bool? sit,
    bool? attack,
  }) {
    if ((axis?.abs() ?? 0) > 0 ||
        jump == true ||
        interact == true ||
        down == true ||
        up == true ||
        sit == true ||
        attack == true) {
      touchUsed = true;
    }
    final wasInteracting = isInteractHeld;
    if (axis != null) _touchAxis = axis;
    if (jump != null) _touchJump = jump;
    if (interact != null) _touchInteract = interact;
    if (down != null) _touchDown = down;
    if (up != null) _touchUp = up;
    if (sit != null) _touchSit = sit;
    if (attack != null) _touchAttack = attack;
    if (!_scripted) _interactionEdge(wasInteracting);
  }

  /// Hands the controls to a script, letting go of anything held.
  void beginScript() {
    if (_scripted) return;
    final wasInteracting = isInteractHeld;
    _scripted = true;
    _scriptAxis = 0;
    _scriptJump = _scriptInteract = _scriptDown = _scriptUp = false;
    _scriptSit = false;
    _jumpRequested = _interactRequested = false;
    _attackRequested = _cycleWeaponRequested = false;
    _weaponSlotRequested = null;
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
    bool? sit,
  }) {
    if (!_scripted) return;
    final wasInteracting = isInteractHeld;
    if (axis != null) _scriptAxis = axis;
    if (jump != null) _scriptJump = jump;
    if (interact != null) _scriptInteract = interact;
    if (down != null) _scriptDown = down;
    if (up != null) _scriptUp = up;
    if (sit != null) _scriptSit = sit;
    _interactionEdge(wasInteracting);
  }

  void _interactionEdge(bool wasHeld) {
    if (!wasHeld && isInteractHeld) requestInteract();
    if (wasHeld && !isInteractHeld) requestInteractRelease();
  }

  void requestInteract() {
    _interactRequested = true;
    actionAttempts++;
  }

  void requestInteractRelease() => _interactReleaseRequested = true;
  void requestReset() {
    if (!_scripted) _resetRequested = true;
  }

  void requestDebugToggle() => _debugRequested = true;
  void requestKnockdown() {
    if (!_scripted) _knockdownRequested = true;
  }

  void requestAudioToggle() => _audioRequested = true;

  void requestAttack() {
    if (_scripted) return;
    _attackRequested = true;
    actionAttempts++;
  }

  void requestCycleWeapon() {
    if (!_scripted) _cycleWeaponRequested = true;
  }

  void requestWeaponSlot(int slot) {
    if (!_scripted && slot >= 0 && slot < 3) _weaponSlotRequested = slot;
  }

  void requestJump({bool fromUp = false}) {
    if (_scripted) return;
    _jumpRequested = true;
    _jumpFromUp = fromUp;
    actionAttempts++;
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

  bool consumeAttackRequest() {
    final value = _attackRequested;
    _attackRequested = false;
    return value;
  }

  bool consumeCycleWeaponRequest() {
    final value = _cycleWeaponRequested;
    _cycleWeaponRequested = false;
    return value;
  }

  int? consumeWeaponSlotRequest() {
    final value = _weaponSlotRequested;
    _weaponSlotRequested = null;
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
    _keyboardSit = _touchSit = false;
    _keyboardAttack = _touchAttack = false;
    _jumpRequested = _interactRequested = false;
    _jumpFromUp = false;
    _resetRequested = _debugRequested = _knockdownRequested = false;
    _audioRequested = false;
    _attackRequested = _cycleWeaponRequested = false;
    _weaponSlotRequested = null;
    _interactReleaseRequested = release;
  }
}
