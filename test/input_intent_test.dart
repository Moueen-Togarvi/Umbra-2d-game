import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/input/keyboard_input.dart';
import 'package:umbra/input/player_intent.dart';
import 'package:umbra/input/touch_controls.dart';

void main() {
  KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );
  KeyUpEvent up(LogicalKeyboardKey key) => KeyUpEvent(
    physicalKey: PhysicalKeyboardKey.keyA,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  test('move, action and down follow the full keyboard held state', () {
    final intent = PlayerIntent();
    final input = KeyboardInput(intent);
    final held = <LogicalKeyboardKey>{LogicalKeyboardKey.keyD};
    input.onKeyEvent(down(LogicalKeyboardKey.keyD), held);
    expect(intent.horizontalAxis, 1);
    held.addAll({LogicalKeyboardKey.keyE, LogicalKeyboardKey.arrowDown});
    input.onKeyEvent(down(LogicalKeyboardKey.keyE), held);
    expect(intent.isDownHeld && intent.isInteractHeld, isTrue);
    expect(intent.consumeInteractRequest(), isTrue);
    input.onKeyEvent(
      KeyRepeatEvent(
        physicalKey: PhysicalKeyboardKey.keyE,
        logicalKey: LogicalKeyboardKey.keyE,
        timeStamp: Duration.zero,
      ),
      held,
    );
    expect(intent.consumeInteractRequest(), isFalse);
    held.remove(LogicalKeyboardKey.keyE);
    input.onKeyEvent(up(LogicalKeyboardKey.keyE), held);
    expect(intent.consumeInteractRelease(), isTrue);
    expect(intent.consumeInteractRelease(), isFalse);

    // Ctrl is LIMBO's action key too; shift does nothing (he always runs).
    held
      ..remove(LogicalKeyboardKey.arrowDown)
      ..addAll({LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.shiftLeft});
    input.onKeyEvent(down(LogicalKeyboardKey.controlLeft), held);
    expect(intent.isInteractHeld, isTrue);
    expect(intent.isDownHeld, isFalse);
    expect(intent.horizontalAxis, 1);
  });

  test(
    'keyboard release preserves touch holds and grab waits for final source',
    () {
      final intent = PlayerIntent();
      intent.setTouchState(axis: 1, jump: true, interact: true);
      expect(intent.consumeInteractRequest(), isTrue);
      intent.setKeyboardState(axis: -1, interact: true);
      expect(intent.horizontalAxis, 0);
      expect(intent.consumeInteractRequest(), isFalse);
      intent.setKeyboardState(axis: 0, jump: false);
      expect(intent.horizontalAxis, 1);
      expect(intent.isJumpHeld, isTrue);
      intent.setTouchState(interact: false);
      expect(intent.isInteractHeld, isTrue);
      expect(intent.consumeInteractRelease(), isFalse);
      intent.setKeyboardState(interact: false);
      expect(intent.consumeInteractRelease(), isTrue);
    },
  );

  test('reset, debug, knockdown and sound are consumed once', () {
    final intent = PlayerIntent();
    final input = KeyboardInput(intent);
    for (final key in [
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.f1,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyM,
    ]) {
      input.onKeyEvent(down(key), {key});
    }
    expect(intent.consumeResetRequest(), isTrue);
    expect(intent.consumeResetRequest(), isFalse);
    expect(intent.consumeDebugToggleRequest(), isTrue);
    expect(intent.consumeDebugToggleRequest(), isFalse);
    expect(intent.consumeKnockdownRequest(), isTrue);
    expect(intent.consumeKnockdownRequest(), isFalse);
    expect(intent.consumeAudioToggleRequest(), isTrue);
    expect(intent.consumeAudioToggleRequest(), isFalse);
  });

  test('focus clear drops held actions and emits one grab release', () {
    final intent = PlayerIntent()
      ..setTouchState(axis: 1, jump: true, interact: true)
      ..setKeyboardState(down: true)
      ..requestJump();
    intent.clear();
    expect(intent.horizontalAxis, 0);
    expect(
      intent.isJumpHeld || intent.isInteractHeld || intent.isDownHeld,
      isFalse,
    );
    expect(intent.consumeJumpRequest(), isFalse);
    expect(intent.consumeInteractRequest(), isFalse);
    expect(intent.consumeInteractRelease(), isTrue);
    expect(intent.consumeInteractRelease(), isFalse);
  });

  test('touch actions can combine and cancellation releases the grab', () {
    final intent = PlayerIntent();
    final controls = TouchControls(intent);
    final buttons = controls.buildButtons();
    expect(buttons, hasLength(4), reason: 'left, right, jump and action');
    buttons[1].onPressed!();
    buttons[2].onPressed!();
    buttons[3].onPressed!();
    expect(intent.horizontalAxis, 1);
    expect(intent.isJumpHeld && intent.isInteractHeld, isTrue);
    expect(intent.consumeJumpRequest(), isTrue);
    expect(intent.consumeInteractRequest(), isTrue);
    buttons[3].onCancelled!();
    expect(intent.isInteractHeld, isFalse);
    expect(intent.consumeInteractRelease(), isTrue);
    expect(intent.horizontalAxis, 1);
    controls.clear();
    expect(intent.horizontalAxis, 0);
    expect(intent.isJumpHeld, isFalse);
  });
}
