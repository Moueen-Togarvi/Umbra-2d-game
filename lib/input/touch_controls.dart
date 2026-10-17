import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/input.dart';
import 'package:flutter/widgets.dart'
    show EdgeInsets, TextPainter, TextSpan, TextStyle, VoidCallback;

import '../config/game_config.dart';
import '../config/palette.dart';
import '../config/game_settings.dart';
import 'player_intent.dart';

/// On-screen controls for phones, LIMBO's whole vocabulary: walk left and
/// right under the left thumb, jump and the action hand under the right.
///
/// This is the second input source in the game, and it was added without
/// touching a single line of physics, entity or checkpoint code. That is
/// entirely down to [PlayerIntent] sitting between input and simulation: the
/// player entity reads *intentions*, and has no idea whether they came from a
/// keyboard or a thumb.
///
/// Note this is a plain class, not a [Component]. The buttons have to be added
/// **directly** to `camera.viewport`, because Flame's margin logic asserts that
/// a button's immediate parent provides a size. Wrapping them in a container
/// component would break that, so instead this class just owns the shared state
/// the two walk buttons need and hands back the components to mount.
///
/// Two smaller climb buttons, ˄ and ˅, appear above the walk buttons only
/// while he holds a rope.
///
/// Development builds (`UMBRA_DEBUG`) add four small labelled buttons along
/// the top: physics overlay, checkpoint reset, ragdoll knockdown and sound.
/// Release builds have no text on screen at all.
class TouchControls {
  TouchControls(
    this._intent, {
    bool Function()? debugVisible,
    bool Function()? onRope,
    bool Function()? hidden,
    this.onPause,
    this.debugTools = false,
    GameSettings? settings,
  }) : _debugVisible = debugVisible ?? (() => false),
       settings = settings ?? GameSettings(),
       _onRope = onRope ?? (() => false),
       _hidden = hidden ?? (() => false);

  final PlayerIntent _intent;
  final bool Function() _debugVisible;
  final bool Function() _onRope;

  /// While true (a title screen, a cutscene, a chapter card) the play
  /// buttons neither draw nor take touches.
  final bool Function() _hidden;

  /// Whether the development buttons exist at all.
  final bool debugTools;
  final GameSettings settings;
  final VoidCallback? onPause;

  // Which walk buttons are currently held. Tracked as two booleans rather than
  // writing the axis directly on each press, for the same reason
  // KeyboardInput reads the whole set of held keys: if you are holding left,
  // then tap and release right, you should still be walking left. Writing
  // `horizontalAxis = 0` on release would strand you standing still with your
  // thumb still on the left button.
  bool _isHoldingLeft = false;
  bool _isHoldingRight = false;
  List<HudButtonComponent> _buttons = [];

  /// The HUD components to add to `camera.viewport`: left, right, jump and
  /// action first, then climb up and down, then the development buttons
  /// when [debugTools] is set.
  List<HudButtonComponent> buildButtons() {
    final double diameter =
        GameConfig.controlButtonDiameterPx * settings.controlsScale;
    const double edge = GameConfig.controlEdgeMarginPx;
    const double gap = GameConfig.controlGapPx;
    const double small = 46;
    final double climb = diameter * 0.78;

    _buttons = [
      // Walk left — bottom-left corner.
      _controlButton(
        glyph: _Glyph.left,
        margin: const EdgeInsets.only(left: edge, bottom: edge),
        onPress: () => _setHoldingLeft(true),
        onRelease: () => _setHoldingLeft(false),
      ),

      // Walk right — immediately to the right of the left button.
      _controlButton(
        glyph: _Glyph.right,
        margin: EdgeInsets.only(left: edge + diameter + gap, bottom: edge),
        onPress: () => _setHoldingRight(true),
        onRelease: () => _setHoldingRight(false),
      ),

      // Jump — bottom-right, under the other thumb.
      //
      // Leaving `left` and `top` at zero is what tells Flame to anchor this to
      // the right and bottom edges instead of the left and top.
      _controlButton(
        glyph: _Glyph.jump,
        margin: const EdgeInsets.only(right: edge, bottom: edge),
        onPress: () {
          _intent.setTouchState(jump: true);
          _intent.requestJump();
        },
        onRelease: () => _intent.setTouchState(jump: false),
      ),

      // The action hand — grab and pull. Held, like the key.
      _controlButton(
        glyph: _Glyph.hand,
        margin: EdgeInsets.only(right: edge + diameter + gap, bottom: edge),
        onPress: () => _intent.setTouchState(interact: true),
        onRelease: () => _intent.setTouchState(interact: false),
      ),

      // Climb up and down a rope: only there while he holds one, above the
      // walk buttons.
      _controlButton(
        glyph: _Glyph.up,
        diameter: climb,
        visible: _onRope,
        margin: EdgeInsets.only(
          left: edge + (diameter - climb) / 2,
          bottom: edge + diameter + gap,
        ),
        onPress: () => _intent.setTouchState(up: true),
        onRelease: () => _intent.setTouchState(up: false),
      ),
      _controlButton(
        glyph: _Glyph.down,
        diameter: climb,
        visible: _onRope,
        margin: EdgeInsets.only(
          left: edge + diameter + gap + (diameter - climb) / 2,
          bottom: edge + diameter + gap,
        ),
        onPress: () => _intent.setTouchState(down: true),
        onRelease: () => _intent.setTouchState(down: false),
      ),

      _controlButton(
        glyph: _Glyph.pause,
        diameter: small,
        margin: const EdgeInsets.only(right: edge, top: edge),
        onPress: () => onPause?.call(),
        onRelease: () {},
      ),

      if (debugTools) ...[
        _controlButton(
          label: 'DBG',
          diameter: small,
          margin: const EdgeInsets.only(right: edge + small + 8, top: edge),
          onPress: _intent.requestDebugToggle,
          onRelease: () {},
        ),
        _controlButton(
          label: 'RESET',
          diameter: small,
          visible: _debugVisible,
          margin: const EdgeInsets.only(
            right: edge + (small + 8) * 2,
            top: edge,
          ),
          onPress: _intent.requestReset,
          onRelease: () {},
        ),
        _controlButton(
          label: 'FALL',
          diameter: small,
          visible: _debugVisible,
          margin: const EdgeInsets.only(
            right: edge + (small + 8) * 3,
            top: edge,
          ),
          onPress: _intent.requestKnockdown,
          onRelease: () {},
        ),
        _controlButton(
          label: 'SOUND',
          diameter: small,
          margin: const EdgeInsets.only(
            right: edge + (small + 8) * 4,
            top: edge,
          ),
          onPress: _intent.requestAudioToggle,
          onRelease: () {},
        ),
      ],
    ];
    return _buttons;
  }

  HudButtonComponent _controlButton({
    _Glyph? glyph,
    String? label,
    bool Function()? visible,
    double? diameter,
    required EdgeInsets margin,
    required void Function() onPress,
    required void Function() onRelease,
  }) {
    final size = Vector2.all(
      diameter ?? GameConfig.controlButtonDiameterPx * settings.controlsScale,
    );
    final bool Function() shown = visible ?? (() => true);
    return _VisibilityButton(
      // The development buttons stay usable in a cutscene.
      visible: label != null ? shown : () => !_hidden() && shown(),
      size: size,
      button: _ControlFace(
        glyph: glyph,
        label: label,
        isPressed: false,
        opacity: () => settings.controlsOpacity,
        size: size,
      ),
      buttonDown: _ControlFace(
        glyph: glyph,
        label: label,
        isPressed: true,
        opacity: () => settings.controlsOpacity,
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
    _intent.setTouchState(
      axis: (_isHoldingRight ? 1.0 : 0.0) - (_isHoldingLeft ? 1.0 : 0.0),
    );
  }

  void clear() {
    _isHoldingLeft = _isHoldingRight = false;
    _intent.setTouchState(
      axis: 0,
      jump: false,
      interact: false,
      up: false,
      down: false,
    );
    for (final button in _buttons) {
      if (button.buttonDown?.parent == button) {
        button.buttonDown!.removeFromParent();
        button.button!.parent = button;
      }
    }
  }

  void removeButtons() {
    clear();
    for (final button in _buttons) {
      button.removeFromParent();
    }
    _buttons = [];
  }
}

enum _Glyph { left, right, jump, hand, up, down, pause }

/// A hidden development action neither draws nor receives a stray tap.
class _VisibilityButton extends HudButtonComponent {
  _VisibilityButton({
    required this.visible,
    required super.size,
    required super.button,
    required super.buttonDown,
    required super.margin,
    required super.onPressed,
    required super.onReleased,
    required super.onCancelled,
  });
  final bool Function() visible;
  @override
  bool containsLocalPoint(Vector2 point) =>
      visible() && super.containsLocalPoint(point);
  @override
  void renderTree(Canvas canvas) {
    if (visible()) super.renderTree(canvas);
  }
}

/// The visual of a single control button: a faint ring with a glyph.
///
/// Drawn directly rather than assembled from Flame's shape components, because
/// it is a circle and a small shape, and doing it by hand is both shorter and
/// easier to restyle than wiring nested components together.
class _ControlFace extends PositionComponent {
  _ControlFace({
    this.glyph,
    this.label,
    required this.isPressed,
    required this.opacity,
    required Vector2 size,
  }) : super(size: size);

  final _Glyph? glyph;
  final String? label;
  TextPainter? _labelPainter;

  /// Whether to draw the held-down state.
  final bool isPressed;
  final double Function() opacity;

  static final Paint _fill = Paint();
  static final Paint _ring = Paint()
    ..color = Palette.controlRing
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  static final Paint _glyphPaint = Paint()..color = Palette.controlGlyph;
  static final Paint _strokeGlyph = Paint()
    ..color = Palette.controlGlyph
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void render(Canvas canvas) {
    final radius = size.x / 2;
    final center = Offset(radius, radius);
    _fill.color = isPressed ? Palette.controlPressed : Palette.control;
    final alpha = isPressed ? 1.0 : opacity();
    _fill.color = _fill.color.withValues(alpha: _fill.color.a * alpha);
    _ring.color = Palette.controlRing.withValues(
      alpha: Palette.controlRing.a * alpha,
    );
    _glyphPaint.color = Palette.controlGlyph.withValues(
      alpha: Palette.controlGlyph.a * alpha,
    );
    _strokeGlyph.color = _glyphPaint.color;
    canvas.drawCircle(center, radius, _fill);
    // A thin ring, so the button is findable against a black floor without
    // becoming a bright disc that competes with the scene.
    canvas.drawCircle(center, radius - 1, _ring);

    if (label != null) {
      final painter = _labelPainter ??= TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontFamily: 'Roboto',
            color: Palette.controlGlyph,
            fontSize: 9,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        center - Offset(painter.width / 2, painter.height / 2),
      );
      return;
    }
    final double r = radius * GameConfig.controlGlyphScale;
    switch (glyph!) {
      case _Glyph.left:
        _triangle(canvas, center, r, math.pi);
      case _Glyph.right:
        _triangle(canvas, center, r, 0);
      case _Glyph.jump:
        _triangle(canvas, center, r, -math.pi / 2);
      case _Glyph.hand:
        _hand(canvas, center, r);
      case _Glyph.up:
        _chevron(canvas, center, r, -1);
      case _Glyph.down:
        _chevron(canvas, center, r, 1);
      case _Glyph.pause:
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(center.dx - r * 0.65, center.dy - r, r * 0.42, r * 2),
            Radius.circular(r * 0.08),
          ),
          _glyphPaint,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(center.dx + r * 0.23, center.dy - r, r * 0.42, r * 2),
            Radius.circular(r * 0.08),
          ),
          _glyphPaint,
        );
    }
  }

  /// An equilateral triangle: three points a third of a turn apart on a
  /// circle, with [angle] deciding which way the first point faces.
  void _triangle(Canvas canvas, Offset center, double r, double angle) {
    final path = Path();
    for (var corner = 0; corner < 3; corner++) {
      final a = angle + corner * 2 * math.pi / 3;
      final point = center + Offset(r * math.cos(a), r * math.sin(a));
      corner == 0
          ? path.moveTo(point.dx, point.dy)
          : path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(path..close(), _glyphPaint);
  }

  /// A climbing chevron, ˄ or ˅: open, so it reads differently from the
  /// solid jump triangle.
  void _chevron(Canvas canvas, Offset center, double r, double direction) {
    final path = Path()
      ..moveTo(center.dx - r * 0.75, center.dy - direction * r * 0.35)
      ..lineTo(center.dx, center.dy + direction * r * 0.45)
      ..lineTo(center.dx + r * 0.75, center.dy - direction * r * 0.35);
    canvas.drawPath(path, _strokeGlyph..strokeWidth = r * 0.28);
  }

  /// An open hand: a rounded palm and four fingers, with the thumb out.
  void _hand(Canvas canvas, Offset center, double r) {
    final palm = Rect.fromCenter(
      center: center + Offset(0, r * 0.28),
      width: r * 1.05,
      height: r * 0.85,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(palm, Radius.circular(r * 0.3)),
      _glyphPaint,
    );
    for (var i = 0; i < 4; i++) {
      final x = palm.left + r * (0.16 + i * 0.245);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x - r * 0.09,
            palm.top - r * (0.62 - (i - 1.5).abs() * 0.1),
            r * 0.18,
            r * 0.8,
          ),
          Radius.circular(r * 0.09),
        ),
        _glyphPaint,
      );
    }
    canvas.save();
    canvas.translate(palm.left + r * 0.05, palm.center.dy);
    canvas.rotate(-0.7);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-r * 0.09, -r * 0.55, r * 0.18, r * 0.6),
        Radius.circular(r * 0.09),
      ),
      _glyphPaint,
    );
    canvas.restore();
  }
}
