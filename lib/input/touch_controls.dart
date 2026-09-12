import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/input.dart';
import 'package:flutter/widgets.dart' show EdgeInsets;

import '../config/game_config.dart';
import '../config/palette.dart';
import 'player_intent.dart';

/// On-screen controls for phones: two walk buttons on the left, jump on the
/// right.
///
/// This is the second input source in the game, and it was added without
/// touching a single line of physics, entity or checkpoint code. That is
/// entirely down to [PlayerIntent] sitting between input and simulation: the
/// player entity reads *intentions*, and has no idea whether they came from a
/// keyboard or a thumb. Adding a gamepad later would be the same shape of
/// change again.
///
/// Note this is a plain class, not a [Component]. The buttons have to be added
/// **directly** to `camera.viewport`, because Flame's margin logic asserts that
/// a button's immediate parent provides a size. Wrapping them in a container
/// component would break that, so instead this class just owns the shared state
/// the two walk buttons need and hands back the components to mount.
class TouchControls {
  TouchControls(this._intent);

  final PlayerIntent _intent;

  // Which walk buttons are currently held. Tracked as two booleans rather than
  // writing the axis directly on each press, for the same reason
  // KeyboardInput reads the whole set of held keys: if you are holding left,
  // then tap and release right, you should still be walking left. Writing
  // `horizontalAxis = 0` on release would strand you standing still with your
  // thumb still on the left button.
  bool _isHoldingLeft = false;
  bool _isHoldingRight = false;

  /// The HUD components to add to `camera.viewport`.
  List<Component> buildButtons() {
    const double diameter = GameConfig.controlButtonDiameterPx;
    const double edge = GameConfig.controlEdgeMarginPx;

    return [
      // Walk left — bottom-left corner.
      _controlButton(
        glyphAngle: math.pi,
        margin: const EdgeInsets.only(left: edge, bottom: edge),
        onPress: () => _setHoldingLeft(true),
        onRelease: () => _setHoldingLeft(false),
      ),

      // Walk right — immediately to the right of the left button.
      _controlButton(
        glyphAngle: 0,
        margin: const EdgeInsets.only(
          left: edge + diameter + GameConfig.controlGapPx,
          bottom: edge,
        ),
        onPress: () => _setHoldingRight(true),
        onRelease: () => _setHoldingRight(false),
      ),

      // Jump — bottom-right, under the other thumb.
      //
      // Leaving `left` and `top` at zero is what tells Flame to anchor this to
      // the right and bottom edges instead of the left and top.
      _controlButton(
        glyphAngle: -math.pi / 2,
        margin: const EdgeInsets.only(right: edge, bottom: edge),
        // Jump is edge-triggered, exactly like the keyboard's key-down: the
        // request is recorded once and there is nothing to undo on release.
        onPress: _intent.requestJump,
        onRelease: () {},
      ),
    ];
  }

  HudButtonComponent _controlButton({
    required double glyphAngle,
    required EdgeInsets margin,
    required void Function() onPress,
    required void Function() onRelease,
  }) {
    final size = Vector2.all(GameConfig.controlButtonDiameterPx);
    return HudButtonComponent(
      size: size,
      button: _ControlFace(
        glyphAngle: glyphAngle,
        isPressed: false,
        size: size,
      ),
      buttonDown: _ControlFace(
        glyphAngle: glyphAngle,
        isPressed: true,
        size: size,
      ),
      margin: margin,
      onPressed: onPress,
      onReleased: onRelease,
      // A thumb that drifts off the edge of a button fires *cancel*, not
      // release. Without this the player would keep walking forever with
      // nothing held down.
      onCancelled: onRelease,
    );
  }

  void _setHoldingLeft(bool isHeld) {
    _isHoldingLeft = isHeld;
    _applyHorizontalIntent();
  }

  void _setHoldingRight(bool isHeld) {
    _isHoldingRight = isHeld;
    _applyHorizontalIntent();
  }

  /// Collapses the two held flags into the single -1 / 0 / +1 axis the player
  /// reads. Holding both cancels out, which is the same thing the keyboard does
  /// when you hold left and right together.
  void _applyHorizontalIntent() {
    _intent.horizontalAxis =
        (_isHoldingRight ? 1.0 : 0.0) - (_isHoldingLeft ? 1.0 : 0.0);
  }
}

/// The visual of a single control button: a translucent disc with an arrow.
///
/// Drawn directly rather than assembled from Flame's shape components, because
/// it is a circle and a triangle and doing it by hand is both shorter and
/// easier to restyle than wiring two nested components together.
class _ControlFace extends PositionComponent {
  _ControlFace({
    required this.glyphAngle,
    required this.isPressed,
    required Vector2 size,
  }) : super(size: size);

  /// Direction the arrow points, in radians. 0 is right, pi is left,
  /// -pi/2 is up.
  final double glyphAngle;

  /// Whether to draw the held-down state.
  final bool isPressed;

  @override
  void render(Canvas canvas) {
    final radius = size.x / 2;
    final center = Offset(radius, radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()..color = isPressed ? Palette.controlPressed : Palette.control,
    );
    // A thin ring, so the button is findable by feel against a black floor
    // without becoming a bright disc that competes with the scene.
    canvas.drawCircle(
      center,
      radius - 1,
      Paint()
        ..color = Palette.controlRing
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    // An equilateral triangle: three points spaced a third of a turn apart on a
    // circle, with [glyphAngle] deciding which way the first point faces.
    final glyphRadius = radius * GameConfig.controlGlyphScale;
    final path = Path();
    for (var corner = 0; corner < 3; corner++) {
      final angle = glyphAngle + corner * 2 * math.pi / 3;
      final point = Offset(
        center.dx + glyphRadius * math.cos(angle),
        center.dy + glyphRadius * math.sin(angle),
      );
      if (corner == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas.drawPath(path, Paint()..color = Palette.controlGlyph);
  }
}
