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

  test('walk, run, crouch and grab edges follow full keyboard held state', () {
    final intent = PlayerIntent();
    final input = KeyboardInput(intent);
    final held = <LogicalKeyboardKey>{
      LogicalKeyboardKey.keyD,
      LogicalKeyboardKey.shiftLeft,
    };
    input.onKeyEvent(down(LogicalKeyboardKey.shiftLeft), held);
    expect(intent.horizontalAxis, 1);
    expect(intent.isRunHeld, isTrue);
    held.remove(LogicalKeyboardKey.shiftLeft);
    input.onKeyEvent(up(LogicalKeyboardKey.shiftLeft), held);
    expect(intent.horizontalAxis, 1);
    expect(intent.isRunHeld, isFalse);
    held.addAll({LogicalKeyboardKey.keyE, LogicalKeyboardKey.arrowDown});
    input.onKeyEvent(down(LogicalKeyboardKey.keyE), held);
    expect(intent.isCrouchHeld && intent.isInteractHeld, isTrue);
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

  test('reset, debug, preset and knockdown are consumed once', () {
    final intent = PlayerIntent();
    final input = KeyboardInput(intent);
    for (final key in [
      LogicalKeyboardKey.keyR,
      LogicalKeyboardKey.f1,
      LogicalKeyboardKey.keyK,
      LogicalKeyboardKey.keyM,
      LogicalKeyboardKey.digit2,
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
    expect(intent.consumePresetRequest(), 1);
    expect(intent.consumePresetRequest(), isNull);
  });

  test('focus clear drops held actions and emits one grab release', () {
    final intent = PlayerIntent()
      ..setTouchState(
        axis: 1,
        jump: true,
        run: true,
        interact: true,
        crouch: true,
      )
      ..requestJump();
    intent.clear();
    expect(intent.horizontalAxis, 0);
    expect(
      intent.isJumpHeld ||
          intent.isRunHeld ||
          intent.isInteractHeld ||
          intent.isCrouchHeld,
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
    buttons[1].onPressed!();
    buttons[3].onPressed!();
    buttons[4].onPressed!();
    buttons[5].onPressed!();
    expect(intent.horizontalAxis, 1);
    expect(
      intent.isRunHeld && intent.isInteractHeld && intent.isCrouchHeld,
      isTrue,
    );
    expect(intent.consumeInteractRequest(), isTrue);
    buttons[3].onCancelled!();
    expect(intent.isInteractHeld, isFalse);
    expect(intent.consumeInteractRelease(), isTrue);
    expect(intent.horizontalAxis, 1);
    controls.clear();
    expect(intent.horizontalAxis, 0);
    expect(intent.isRunHeld || intent.isCrouchHeld, isFalse);
  });
}
