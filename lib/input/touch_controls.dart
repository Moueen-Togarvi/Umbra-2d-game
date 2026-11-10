import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/services.dart';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/input.dart';
import 'package:flutter/widgets.dart'
    show TextPainter, TextSpan, TextStyle, VoidCallback;

import '../config/game_config.dart';
import '../config/palette.dart';
import '../config/game_settings.dart';
import 'player_intent.dart';

/// On-screen controls for phones: walk left and right under the left thumb;
/// jump and sit under the right.
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
  static const layoutIds = [
    'left',
    'right',
    'jump',
    'sit',
    'attack',
    'weaponSlot',
    'climbUp',
    'climbDown',
    'pause',
  ];

  static Map<String, Offset> defaultLayout({
    required Size viewport,
    required double scale,
    required bool leftHanded,
  }) {
    const edge = GameConfig.controlEdgeMarginPx;
    const gap = GameConfig.controlGapPx;
    final diameter = GameConfig.controlButtonDiameterPx * scale;
    const small = 46.0;
    final climb = diameter * .78;
    final attack = diameter * 1.12;
    final positions = <String, Offset>{
      'left': Offset(
        edge + diameter / 2,
        viewport.height - edge - diameter / 2,
      ),
      'right': Offset(
        edge + diameter + gap + diameter / 2,
        viewport.height - edge - diameter / 2,
      ),
      'jump': Offset(
        viewport.width - edge - diameter / 2,
        viewport.height - edge - attack - gap - diameter / 2,
      ),
      'sit': Offset(
        viewport.width - edge - attack - gap - diameter / 2,
        viewport.height - edge - attack / 2,
      ),
      'attack': Offset(
        viewport.width - edge - attack / 2,
        viewport.height - edge - attack / 2,
      ),
      'weaponSlot': Offset(edge + 29, edge + 29),
      'climbUp': Offset(
        edge + diameter / 2,
        viewport.height - edge - diameter - gap - climb / 2,
      ),
      'climbDown': Offset(
        edge + diameter + gap + diameter / 2,
        viewport.height - edge - diameter - gap - climb / 2,
      ),
      'pause': Offset(viewport.width - edge - small / 2, edge + small / 2),
    };
    if (leftHanded) {
      for (final id in layoutIds.where((id) => id != 'pause')) {
        final p = positions[id]!;
        positions[id] = Offset(viewport.width - p.dx, p.dy);
      }
    }
    return {
      for (final entry in positions.entries)
        entry.key: Offset(
          entry.value.dx / viewport.width,
          entry.value.dy / viewport.height,
        ),
    };
  }

  TouchControls(
    this._intent, {
    bool Function()? debugVisible,
    bool Function()? onRope,
    bool Function()? hidden,
    this.onPause,
    this.onWeaponMenu,
    this.attackReadiness,
    this.debugTools = false,
    GameSettings? settings,
  }) : _debugVisible = debugVisible ?? (() => false),
       settings = settings ?? GameSettings(),
       _onRope = onRope ?? (() => false),
       _hidden = hidden ?? (() => false);

  /// The icons the buttons draw, under `assets/images/`, to load before
  /// they are built.
  static List<String> get icons => _ControlFace._art.values.toSet().toList();

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
  final VoidCallback? onWeaponMenu;
  final double Function()? attackReadiness;

  // Which walk buttons are currently held. Tracked as two booleans rather than
  // writing the axis directly on each press, for the same reason
  // KeyboardInput reads the whole set of held keys: if you are holding left,
  // then tap and release right, you should still be walking left. Writing
  // `horizontalAxis = 0` on release would strand you standing still with your
  // thumb still on the left button.
  bool _isHoldingLeft = false;
  bool _isHoldingRight = false;
  List<HudButtonComponent> _buttons = [];

  /// The HUD components to add to `camera.viewport`: left, right, jump,
  /// sit first, then climb up and down, then pause, then the
  /// development buttons when [debugTools] is set.
  List<HudButtonComponent> buildButtons(Vector2 viewportSize) {
    final double diameter =
        GameConfig.controlButtonDiameterPx * settings.controlsScale;
    const double small = 46;
    final double climb = diameter * 0.78;
    final double attack = diameter * 1.12;
    final viewport = Size(viewportSize.x, viewportSize.y);
    final positions = {
      ...defaultLayout(
        viewport: viewport,
        scale: settings.controlsScale,
        leftHanded: settings.leftHanded,
      ),
      ...settings.controlPositions,
    };
    Vector2 at(String id) => Vector2(
      positions[id]!.dx * viewport.width,
      positions[id]!.dy * viewport.height,
    );
    Vector2 debugAt(int index) => Vector2(
      viewport.width -
          GameConfig.controlEdgeMarginPx -
          small / 2 -
          (small + 8) * index,
      GameConfig.controlEdgeMarginPx + small / 2,
    );

    _buttons = [
      // Walk left — bottom-left corner.
      _controlButton(
        glyph: _Glyph.left,
        position: at('left'),
        onPress: () => _setHoldingLeft(true),
        onRelease: () => _setHoldingLeft(false),
      ),

      // Walk right — immediately to the right of the left button.
      _controlButton(
        glyph: _Glyph.right,
        position: at('right'),
        onPress: () => _setHoldingRight(true),
        onRelease: () => _setHoldingRight(false),
      ),

      // Jump — bottom-right, under the other thumb.
      //
      // Position is stored relative to the viewport so custom layouts scale.
      _controlButton(
        glyph: _Glyph.jump,
        position: at('jump'),
        onPress: () {
          _intent.setTouchState(jump: true);
          _intent.requestJump();
        },
        onRelease: () => _intent.setTouchState(jump: false),
      ),

      // Sit. Held still he sits down; held with a walk button he crouches
      // and creeps. It moves into the former action button's inner position,
      // keeping the two useful right-thumb actions grouped together.
      _controlButton(
        glyph: _Glyph.sit,
        position: at('sit'),
        onPress: () => _intent.setTouchState(sit: true),
        onRelease: () => _intent.setTouchState(sit: false),
      ),

      _controlButton(
        glyph: _Glyph.attack,
        diameter: attack,
        position: at('attack'),
        progress: attackReadiness,
        onPress: () {
          _intent.setTouchState(attack: true);
          _intent.requestAttack();
        },
        onRelease: () => _intent.setTouchState(attack: false),
      ),

      _controlButton(
        glyph: _Glyph.weapon,
        diameter: 58,
        position: at('weaponSlot'),
        onPress: () => onWeaponMenu?.call(),
        onRelease: () {},
      ),

      // Climb up and down a rope: only there while he holds one, above the
      // walk buttons.
      _controlButton(
        glyph: _Glyph.up,
        diameter: climb,
        visible: _onRope,
        position: at('climbUp'),
        onPress: () => _intent.setTouchState(up: true),
        onRelease: () => _intent.setTouchState(up: false),
      ),
      _controlButton(
        glyph: _Glyph.down,
        diameter: climb,
        visible: _onRope,
        position: at('climbDown'),
        onPress: () => _intent.setTouchState(down: true),
        onRelease: () => _intent.setTouchState(down: false),
      ),

      _controlButton(
        glyph: _Glyph.pause,
        diameter: small,
        position: at('pause'),
        onPress: () => onPause?.call(),
        onRelease: () {},
      ),

      if (debugTools) ...[
        _controlButton(
          label: 'DBG',
          diameter: small,
          position: debugAt(1),
          onPress: _intent.requestDebugToggle,
          onRelease: () {},
        ),
        _controlButton(
          label: 'RESET',
          diameter: small,
          visible: _debugVisible,
          position: debugAt(2),
          onPress: _intent.requestReset,
          onRelease: () {},
        ),
        _controlButton(
          label: 'FALL',
          diameter: small,
          visible: _debugVisible,
          position: debugAt(3),
          onPress: _intent.requestKnockdown,
          onRelease: () {},
        ),
        _controlButton(
          label: 'SOUND',
          diameter: small,
          position: debugAt(4),
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
    double Function()? progress,
    required Vector2 position,
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
      position: position,
      anchor: Anchor.center,
      button: _ControlFace(
        glyph: glyph,
        label: label,
        isPressed: false,
        opacity: () => settings.controlsOpacity,
        size: size,
        progress: progress,
      ),
      buttonDown: _ControlFace(
        glyph: glyph,
        label: label,
        isPressed: true,
        opacity: () => settings.controlsOpacity,
        size: size,
        progress: progress,
      ),
      onPressed: () {
        if (settings.vibration) {
          unawaited(HapticFeedback.lightImpact().catchError((Object _) {}));
        }
        onPress();
      },
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
      sit: false,
      attack: false,
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

enum _Glyph { left, right, jump, sit, attack, weapon, up, down, pause }

/// A hidden development action neither draws nor receives a stray tap.
class _VisibilityButton extends HudButtonComponent {
  _VisibilityButton({
    required this.visible,
    required super.size,
    required super.button,
    required super.buttonDown,
    required super.position,
    required super.anchor,
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

/// White cut-paper icons (see `assets/images/ui`) with a soft shadow. Jump
/// and Sit add a faint circle and a small action label; other play controls
/// remain icon-only. Development buttons use a small labelled disc.
///
/// Until the icons are loaded (and in a bare test binding) the glyphs are
/// drawn by hand instead.
class _ControlFace extends PositionComponent {
  _ControlFace({
    this.glyph,
    this.label,
    required this.isPressed,
    required this.opacity,
    required Vector2 size,
    this.progress,
  }) : super(size: size);

  final _Glyph? glyph;
  final String? label;
  TextPainter? _labelPainter;
  TextPainter? _actionPainter;
  double? _actionAlpha;

  /// Whether to draw the held-down state.
  final bool isPressed;
  final double Function() opacity;
  final double Function()? progress;

  /// The icon drawn for each glyph that has one, under `assets/images/`.
  static const Map<_Glyph, String> _art = {
    _Glyph.left: 'ui/ui_arrow.png',
    _Glyph.right: 'ui/ui_arrow.png',
    _Glyph.jump: 'ui/ui_jump.png',
    _Glyph.sit: 'ui/ui_sit.png',
    _Glyph.up: 'ui/ui_arrow.png',
    _Glyph.down: 'ui/ui_arrow.png',
    _Glyph.pause: 'ui/ui_pause.png',
  };

  /// How much of the button the icon fills.
  static const double _iconFill = 0.86;

  static final Paint _fill = Paint();
  static final Paint _ring = Paint()
    ..color = Palette.controlRing
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.2;
  final Paint _icon = Paint()..filterQuality = FilterQuality.medium;
  final Paint _shade = Paint()
    ..filterQuality = FilterQuality.medium
    ..imageFilter = ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5);
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
    final alpha = isPressed ? 1.0 : opacity();
    if (label != null) {
      _fill.color = isPressed ? Palette.controlPressed : Palette.control;
      _fill.color = _fill.color.withValues(alpha: _fill.color.a * alpha);
      _ring.color = Palette.controlRing.withValues(
        alpha: Palette.controlRing.a * alpha,
      );
      canvas.drawCircle(center, radius, _fill);
      canvas.drawCircle(center, radius - 1, _ring);
      final painter = _labelPainter ??= TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontFamily: 'Roboto',
            color: Palette.controlGlyph,
            fontSize: 11,
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
    final labeled =
        glyph == _Glyph.jump ||
        glyph == _Glyph.sit ||
        glyph == _Glyph.attack ||
        glyph == _Glyph.weapon;
    if (labeled) {
      final fill = isPressed ? Palette.controlPressed : Palette.control;
      _fill.color = fill.withValues(alpha: fill.a * alpha);
      _ring.color = Palette.controlRing.withValues(
        alpha: Palette.controlRing.a * alpha,
      );
      canvas
        ..drawCircle(center, radius - 1, _fill)
        ..drawCircle(center, radius - 1, _ring);
      if (glyph == _Glyph.attack && progress != null) {
        final ready = progress!().clamp(0.0, 1.0);
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius - 3),
          -math.pi / 2,
          math.pi * 2 * ready,
          false,
          _ring
            ..strokeWidth = 3
            ..color = Palette.controlGlyph.withValues(alpha: alpha),
        );
        _ring.strokeWidth = 1.2;
      }
    }
    // Held, the icon sinks a little under the thumb.
    canvas.save();
    if (isPressed) {
      canvas
        ..translate(center.dx, center.dy)
        ..scale(0.9)
        ..translate(-center.dx, -center.dy);
    }
    final String? name = _art[glyph];
    if (name != null && Flame.images.containsKey(name)) {
      _drawIcon(
        canvas,
        Flame.images.fromCache(name),
        labeled ? center.translate(0, -radius * .13) : center,
        radius,
        alpha,
        fill: labeled ? .59 : _iconFill,
      );
    } else {
      // The shadow first: the same shape, dark and a little below.
      _glyphPaint
        ..color = Palette.controlShadow.withValues(alpha: 0.5 * alpha)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5);
      _strokeGlyph
        ..color = _glyphPaint.color
        ..maskFilter = _glyphPaint.maskFilter;
      _drawGlyph(canvas, center + const Offset(1.5, 2.5), radius);
      _glyphPaint
        ..color = Palette.controlGlyph.withValues(alpha: alpha)
        ..maskFilter = null;
      _strokeGlyph
        ..color = _glyphPaint.color
        ..maskFilter = null;
      _drawGlyph(canvas, center, radius);
    }
    if (labeled) {
      final double actionAlpha = Palette.controlGlyph.a * alpha;
      if (_actionPainter == null || _actionAlpha != actionAlpha) {
        _actionAlpha = actionAlpha;
        _actionPainter = TextPainter(
          text: TextSpan(
            text: switch (glyph) {
              _Glyph.jump => 'JUMP',
              _Glyph.sit => 'SIT',
              _Glyph.attack => 'ATTACK',
              _Glyph.weapon => 'WEAPON',
              _ => '',
            },
            style: TextStyle(
              fontFamily: 'Roboto',
              fontWeight: FontWeight.w700,
              color: Palette.controlGlyph.withValues(alpha: actionAlpha),
              fontSize: 10,
              letterSpacing: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
      }
      final painter = _actionPainter!;
      painter.paint(
        canvas,
        Offset(center.dx - painter.width / 2, center.dy + radius * .58),
      );
    }
    canvas.restore();
  }

  /// [image], fitted into the button, white, with its shadow under it;
  /// mirrored for the left arrow.
  void _drawIcon(
    Canvas canvas,
    Image image,
    Offset center,
    double radius,
    double alpha, {
    double fill = _iconFill,
  }) {
    final double box = radius * 2 * fill;
    final double scale = math.min(box / image.width, box / image.height);
    final Rect source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    final Rect target = Rect.fromCenter(
      center: center,
      width: image.width * scale,
      height: image.height * scale,
    );
    canvas.save();
    if (glyph == _Glyph.up || glyph == _Glyph.down) {
      canvas.translate(center.dx, center.dy);
      canvas.rotate(glyph == _Glyph.up ? -math.pi / 2 : math.pi / 2);
      canvas.translate(-center.dx, -center.dy);
    }
    if (glyph == _Glyph.left) {
      canvas
        ..translate(center.dx, 0)
        ..scale(-1, 1)
        ..translate(-center.dx, 0);
    }
    _shade.colorFilter = ColorFilter.mode(
      Palette.controlShadow.withValues(alpha: 0.5 * alpha),
      BlendMode.srcIn,
    );
    canvas.drawImageRect(
      image,
      source,
      target.shift(const Offset(1.5, 2.5)),
      _shade,
    );
    _icon.colorFilter = ColorFilter.mode(
      Palette.controlGlyph.withValues(alpha: alpha),
      BlendMode.srcIn,
    );
    canvas.drawImageRect(image, source, target, _icon);
    canvas.restore();
  }

  /// The hand-drawn glyphs: the climb chevrons and pause always, and the
  /// rest until their icons are loaded.
  void _drawGlyph(Canvas canvas, Offset center, double radius) {
    final double r = radius * GameConfig.controlGlyphScale;
    switch (glyph!) {
      case _Glyph.left:
        _triangle(canvas, center, r, math.pi);
      case _Glyph.right:
        _triangle(canvas, center, r, 0);
      case _Glyph.jump:
        _triangle(canvas, center, r, -math.pi / 2);
      case _Glyph.sit:
        _triangle(canvas, center, r, math.pi / 2);
      case _Glyph.attack:
        canvas.drawLine(
          center + Offset(-r * .7, r * .65),
          center + Offset(r * .72, -r * .7),
          _strokeGlyph..strokeWidth = r * .32,
        );
        _triangle(canvas, center + Offset(r * .62, -r * .62), r * .32, -.8);
      case _Glyph.weapon:
        canvas.drawPath(
          Path()
            ..moveTo(center.dx, center.dy - r)
            ..lineTo(center.dx + r, center.dy)
            ..lineTo(center.dx, center.dy + r)
            ..lineTo(center.dx - r, center.dy)
            ..close(),
          _strokeGlyph..strokeWidth = r * .2,
        );
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
}
