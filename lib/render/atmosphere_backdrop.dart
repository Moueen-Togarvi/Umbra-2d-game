import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import 'raincoat_silhouette.dart';

/// Everything behind the world: the fog, the light in it, and the few
/// silhouettes standing in it.
///
/// Lives in `camera.backdrop`, which Flame draws in screen space before the
/// world, so nothing here moves with the camera unless it is told to.
///
/// ## The look
///
/// The reference art is *mostly empty*: a pale fog with a light somewhere
/// behind it, a dark ground, and one or two black shapes per screen. Depth
/// comes from how faint a shape is, not from how many there are. So, back to
/// front, this draws:
///
///  1. the fog: a soft glow, brightest around the middle of the screen,
///     darkening gently towards the top and the bottom;
///  2. the placed scenery from [GameConfig.scenery], each prop scrolling and
///     fading by its own depth, so things arrive one at a time as the player
///     walks — deep ones drawn from blurred art whose base has already
///     dissolved into mist;
///  3. the fog *itself*: a band of mist lying along the ground and a few
///     large, slow wisps drifting across, drawn in front of the scenery so
///     that things really are seen through it;
///  4. a couple of faint shafts of light.
class AtmosphereBackdrop extends Component {
  AtmosphereBackdrop({required this.camera});

  final CameraComponent camera;

  late final List<_PlacedProp> _props;

  double _time = 0;

  final Paint _fogPaint = Paint();
  final Paint _shaftPaint = Paint()..blendMode = BlendMode.plus;

  @override
  Future<void> onLoad() async {
    final images = Flame.images;

    _props = [
      for (final prop in GameConfig.scenery)
        _PlacedProp(prop, images.fromCache('props/${prop.imageFile}')),
    ];

    final random = math.Random(11);
    for (var i = 0; i < 7; i++) {
      _wisps.add(_Wisp.random(random, i));
    }
  }

  final List<_Wisp> _wisps = [];

  @override
  void update(double dt) {
    _time += dt;
  }

  @override
  void render(Canvas canvas) {
    final Vector2 viewport = camera.viewport.size;
    if (viewport.x <= 0 || viewport.y <= 0) {
      return;
    }

    // Screen pixels per metre. Derived from what the camera actually shows so
    // it stays right whatever the phone's aspect ratio does to the zoom.
    final Rect visible = camera.visibleWorldRect;
    final double pixelsPerMetre = viewport.y / visible.height;
    final Vector2 cameraWorld = camera.viewfinder.position;

    _renderFog(canvas, viewport);
    _renderCurtains(canvas, viewport, cameraWorld, pixelsPerMetre);
    _renderFarHill(canvas, viewport, cameraWorld, pixelsPerMetre);

    // Far props first, so a near one can stand in front of a far one.
    for (final placed in _props) {
      placed.render(canvas, viewport, cameraWorld, pixelsPerMetre);
    }
    _renderHanged(canvas, viewport, cameraWorld, pixelsPerMetre);

    _renderMist(canvas, viewport, cameraWorld, pixelsPerMetre);
    _renderLightShafts(canvas, viewport);
  }

  /// The screen y of the ground line, from the camera's resting offset
  /// above the player. Fog and far hills are laid out against it.
  double _groundLine(Vector2 viewport, double pixelsPerMetre) =>
      viewport.y / 2 +
      (GameConfig.cameraLookUp + GameConfig.playerHeight / 2) * pixelsPerMetre;

  /// Tall, faint, soft-edged columns of lighter fog — the far trunks of the
  /// reference frame, so deep in the mist that only a paler streak is left
  /// of each. Almost pinned to the horizon, drifting a little.
  void _renderCurtains(
    Canvas canvas,
    Vector2 viewport,
    Vector2 cameraWorld,
    double pixelsPerMetre,
  ) {
    const int count = 5;
    const double speed = 0.05;
    for (var i = 0; i < count; i++) {
      final double seed = i * 2.13;
      // Spread across a repeating span, scrolled very slowly.
      final double spanPx = viewport.x * 1.6;
      double x =
          (i * spanPx / count +
              math.sin(_time * 0.05 + seed) * viewport.x * 0.02 -
              cameraWorld.x * speed * pixelsPerMetre) %
          spanPx;
      if (x > viewport.x + spanPx * 0.2) x -= spanPx;
      final double halfW = viewport.x * (0.035 + 0.02 * math.sin(seed * 1.7));
      final double alpha = 0.06 + 0.04 * (0.5 + 0.5 * math.sin(seed * 3.1));
      _fogPaint.shader = Gradient.linear(
        Offset(x - halfW, 0),
        Offset(x + halfW, 0),
        [
          Palette.fogGlow.withValues(alpha: 0),
          Palette.fogGlow.withValues(alpha: alpha),
          Palette.fogGlow.withValues(alpha: 0),
        ],
        const [0.0, 0.5, 1.0],
      );
      canvas.drawRect(
        Rect.fromLTWH(x - halfW, 0, halfW * 2, viewport.y),
        _fogPaint,
      );
    }
  }

  /// A second, further hill behind the one the boy walks on: a dark grey
  /// mass with a soft top edge, rolling on its own slower curve. It gives
  /// the ground a horizon of its own instead of ending at a black line.
  void _renderFarHill(
    Canvas canvas,
    Vector2 viewport,
    Vector2 cameraWorld,
    double pixelsPerMetre,
  ) {
    const double depth = 0.62;
    final double speed = 1 - 0.85 * depth;
    final double groundY = _groundLine(viewport, pixelsPerMetre);
    final Path hill = Path()..moveTo(0, viewport.y);
    const double stepPx = 12;
    double topMost = viewport.y;
    for (double sx = 0; sx <= viewport.x + stepPx; sx += stepPx) {
      // The world x this column looks at, at this layer's scroll rate.
      final double wx =
          cameraWorld.x + (sx - viewport.x / 2) / (speed * pixelsPerMetre);
      final double rise =
          1.1 * math.sin(wx * 0.11 + 0.8) +
          0.5 * math.sin(wx * 0.27 + 2.1) +
          0.2 * math.sin(wx * 0.71);
      final double y = groundY - (1.4 + rise) * pixelsPerMetre;
      if (y < topMost) topMost = y;
      hill.lineTo(sx, y);
    }
    hill
      ..lineTo(viewport.x + stepPx, viewport.y)
      ..close();
    // Fades in from its crest downward, so the edge is mist, not a line.
    final double opacity = Palette.depthOpacity(depth) * 0.85;
    _fogPaint.shader = Gradient.linear(
      Offset(0, topMost),
      Offset(0, topMost + 1.6 * pixelsPerMetre),
      [
        Color.fromRGBO(0, 0, 0, opacity * 0.25),
        Color.fromRGBO(0, 0, 0, opacity),
      ],
    );
    canvas.drawPath(hill, _fogPaint);
  }

  final RaincoatSilhouette _hangedFigure = RaincoatSilhouette(
    height: GameConfig.playerHeight,
  );
  final Paint _ropePaint = Paint()
    ..color = Palette.silhouette
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  /// The boy on the gallows, hung from the noose of the gallows prop and
  /// swinging very slightly. Drawn with the player's own silhouette, so the
  /// one on the rope is unmistakably the one on the ground.
  void _renderHanged(
    Canvas canvas,
    Vector2 viewport,
    Vector2 cameraWorld,
    double pixelsPerMetre,
  ) {
    const double depth = GameConfig.hangedDepth;
    final double speed = 1 - 0.85 * depth;
    final double sx =
        viewport.x / 2 +
        (GameConfig.hangedX - cameraWorld.x) * speed * pixelsPerMetre;
    final double sy =
        viewport.y / 2 + (GameConfig.hangedY - cameraWorld.y) * pixelsPerMetre;
    final double reach = GameConfig.playerHeight * 1.3 * pixelsPerMetre;
    if (sx + reach < 0 || sx - reach > viewport.x) return;

    final double sway =
        math.sin(_time * 0.9) * 0.035 + math.sin(_time * 0.37) * 0.02;
    canvas.save();
    canvas.translate(sx, sy);
    canvas.rotate(sway);
    canvas.scale(pixelsPerMetre, pixelsPerMetre);
    // A short length of rope from the noose down to the back of the head.
    _ropePaint.strokeWidth = 0.035;
    canvas.drawLine(Offset.zero, const Offset(0.0, 0.18), _ropePaint);
    // The figure hangs by the head: its crown sits just below the noose.
    canvas.translate(0.02, 0.12 + GameConfig.playerHeight / 2);
    _hangedFigure.draw(canvas, const RaincoatPose(facing: -1, limp: 1));
    canvas.restore();
  }

  /// The fog that things are seen *through*: a band of mist along the
  /// ground, thickest just above the surface and thinning upward, and a
  /// handful of big soft wisps that drift slowly across and scroll at a
  /// middle depth. Both are pale, not dark: fog is lit, and it hides a shape
  /// by washing it out towards the light, never by darkening it.
  void _renderMist(
    Canvas canvas,
    Vector2 viewport,
    Vector2 cameraWorld,
    double pixelsPerMetre,
  ) {
    // The ground line on screen, from the camera's resting offset above the
    // player. Mist sits on it.
    final double groundY = _groundLine(viewport, pixelsPerMetre);
    final double bandTop = groundY - viewport.y * 0.38;
    _fogPaint.shader = Gradient.linear(
      Offset(0, bandTop),
      Offset(0, groundY + viewport.y * 0.04),
      [
        Palette.fogGlow.withValues(alpha: 0),
        Palette.fogGlow.withValues(alpha: 0.26),
        Palette.fogGlow.withValues(alpha: 0.48),
      ],
      const [0.0, 0.7, 1.0],
    );
    canvas.drawRect(Rect.fromLTWH(0, 0, viewport.x, viewport.y), _fogPaint);

    for (final wisp in _wisps) {
      wisp.render(canvas, viewport, cameraWorld, pixelsPerMetre, _time);
    }
  }

  void _renderFog(Canvas canvas, Vector2 viewport) {
    final Rect full = Rect.fromLTWH(0, 0, viewport.x, viewport.y);

    // The light breathes very slowly: its centre wanders a little and its
    // reach swells and shrinks, so a still scene is never a dead one.
    final double wander = math.sin(_time * 0.11) * 0.04;
    final double swell = 1 + math.sin(_time * 0.07) * 0.05;
    // The light sits left of centre and a little below the middle, the way
    // it does in the reference frames, so the right-hand side of the screen
    // is always the darker, more uncertain one.
    final Offset centre = Offset(
      viewport.x * (0.40 + wander),
      viewport.y * 0.48,
    );
    _fogPaint.shader = Gradient.radial(
      centre,
      viewport.x * 0.70 * swell,
      const [Palette.fogGlow, Palette.fogMid, Palette.fogEdge],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(full, _fogPaint);

    // The top of the world sinks into shadow — the underside of a canopy that
    // is never actually drawn — and the bottom into the ground's darkness.
    // Eased with a middle stop: a straight ramp ends in a visible line where
    // it stops (the eye picks up the kink), an eased one does not.
    _fogPaint.shader = Gradient.linear(
      Offset.zero,
      Offset(0, viewport.y * 0.45),
      const [Color(0xF2000000), Color(0x6E000000), Color(0x00000000)],
      const [0.0, 0.42, 1.0],
    );
    canvas.drawRect(full, _fogPaint);
    _fogPaint.shader = Gradient.linear(
      Offset(0, viewport.y * 0.60),
      Offset(0, viewport.y),
      const [Color(0x00000000), Color(0x59000000), Color(0xCC000000)],
      const [0.0, 0.5, 1.0],
    );
    canvas.drawRect(full, _fogPaint);
  }

  /// Three tall, faint wedges of light falling from above. Additive blending
  /// so they brighten whatever they cross, the way light does.
  void _renderLightShafts(Canvas canvas, Vector2 viewport) {
    const int count = 3;
    for (var i = 0; i < count; i++) {
      final double seed = i * 2.3;
      final double sway = math.sin(_time * 0.13 + seed) * viewport.x * 0.02;
      final double xTop = viewport.x * (0.30 + i * 0.20) + sway;
      final double lean = viewport.x * (0.08 + 0.03 * math.sin(seed));
      final double widthTop = viewport.x * 0.02;
      final double widthBottom = viewport.x * (0.09 + 0.02 * math.cos(seed));
      final double bottom = viewport.y * 0.90;
      final double pulse = 0.5 + 0.5 * math.sin(_time * 0.19 + seed * 2.1);
      final double strength = 0.035 + 0.03 * pulse;

      _shaftPaint.shader = Gradient.linear(
        Offset(xTop, 0),
        Offset(xTop + lean, bottom),
        [
          Palette.lightShaft.withValues(alpha: strength),
          Palette.lightShaft.withValues(alpha: strength * 0.5),
          Palette.lightShaft.withValues(alpha: 0),
        ],
        const [0.0, 0.45, 1.0],
      );
      final Path shaft = Path()
        ..moveTo(xTop - widthTop, 0)
        ..lineTo(xTop + widthTop, 0)
        ..lineTo(xTop + lean + widthBottom, bottom)
        ..lineTo(xTop + lean - widthBottom, bottom)
        ..close();
      canvas.drawPath(shaft, _shaftPaint);
    }
  }
}

/// A [SceneryProp] with its art loaded, ready to draw.
///
/// A prop at depth 0 sits exactly where its world coordinates say, moving
/// with the ground. Deeper props scroll more slowly against the camera and
/// are drawn fainter, which is all it takes for the eye to put them further
/// away. The projection is the ordinary parallax one: a prop appears at its
/// true position when the camera is centred on it, and drifts away from that
/// position by less than the camera moves.
class _PlacedProp {
  _PlacedProp(this.prop, this.image)
    : speed = 1 - 0.85 * prop.depth,
      opacity = Palette.depthOpacity(prop.depth);

  final SceneryProp prop;
  final Image image;
  final double speed;
  final double opacity;

  /// How far a standing prop's base is buried below the ground surface, in
  /// metres. Deeper than the hill's tallest swell (0.14 m).
  static const double _baseSink = 0.2;

  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  void render(
    Canvas canvas,
    Vector2 viewport,
    Vector2 cameraWorld,
    double pixelsPerMetre,
  ) {
    final double drawH = prop.height * pixelsPerMetre;
    final double drawW = drawH * image.width / image.height;

    // Deep props also shrink a little with distance, the way the same tree
    // does when it stands further off.
    final double scale = 1 - 0.25 * prop.depth;
    final double w = drawW * scale;
    final double h = drawH * scale;

    final double centreX =
        viewport.x / 2 + (prop.x - cameraWorld.x) * speed * pixelsPerMetre;
    // Only the *horizontal* motion is parallaxed. A prop stands on the same
    // ground the player walks on, so vertically it must move exactly with
    // the world: scaling its height offset by [speed] would lift it off the
    // ground line by a fraction of its distance from the screen centre. Its
    // base is also sunk a little below the surface, so the hill's swells and
    // the grass fringe hide the seam instead of showing a gap under it.
    final double anchorY =
        viewport.y / 2 + (prop.y - cameraWorld.y) * pixelsPerMetre;
    final double sink = prop.hangs ? 0 : _baseSink * pixelsPerMetre;
    final double top = prop.hangs ? anchorY : anchorY + sink - h;
    final double left = centreX - w / 2;

    // Off screen: skip. Most props are, most of the time.
    if (left > viewport.x || left + w < 0 || top > viewport.y || top + h < 0) {
      return;
    }

    _paint.color = Color.fromRGBO(0, 0, 0, opacity);
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(left, top, w, h),
      _paint,
    );
  }
}

/// One drifting patch of fog: a large, very soft, pale ellipse.
///
/// Wisps live in world space at a middle depth, so they scroll against the
/// scenery like something between it and the camera, and they drift on their
/// own so the fog is never still. They repeat every [_span] metres, which is
/// why a level of any length has fog all the way along it.
class _Wisp {
  _Wisp({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.alpha,
    required this.drift,
    required this.depth,
    required this.phase,
  });

  factory _Wisp.random(math.Random r, int index) {
    return _Wisp(
      // Spread evenly along the span, then jittered.
      x: index * (_span / 7) + r.nextDouble() * 6,
      // In metres above the ground line: the fog lies low.
      y: 0.4 + r.nextDouble() * 2.6,
      width: 9 + r.nextDouble() * 9,
      height: 2.2 + r.nextDouble() * 2.4,
      alpha: 0.16 + r.nextDouble() * 0.16,
      drift: 0.12 + r.nextDouble() * 0.16,
      depth: 0.25 + r.nextDouble() * 0.35,
      phase: r.nextDouble() * math.pi * 2,
    );
  }

  static const double _span = 48.0;

  final double x, y, width, height, alpha, drift, depth, phase;
  final Paint _paint = Paint();

  void render(
    Canvas canvas,
    Vector2 viewport,
    Vector2 cameraWorld,
    double pixelsPerMetre,
    double time,
  ) {
    final double speed = 1 - 0.85 * depth;
    final double groundY =
        viewport.y / 2 +
        (GameConfig.cameraLookUp + GameConfig.playerHeight / 2) *
            pixelsPerMetre;
    final double breathe = 1 + 0.08 * math.sin(time * 0.21 + phase);
    final double w = width * pixelsPerMetre * breathe;
    final double h = height * pixelsPerMetre;
    final double cy =
        groundY -
        y * pixelsPerMetre +
        math.sin(time * 0.17 + phase) * 0.3 * pixelsPerMetre;

    // World x, drifting, wrapped into the repeating span and then placed
    // relative to the camera like any other parallax prop.
    final double worldX = (x + time * drift) % _span;
    final double camWrapped = cameraWorld.x % _span;
    // Nearest repeat of this wisp to the camera.
    double dx = worldX - camWrapped;
    if (dx > _span / 2) dx -= _span;
    if (dx < -_span / 2) dx += _span;
    final double cx = viewport.x / 2 + dx * speed * pixelsPerMetre;

    if (cx + w < 0 || cx - w > viewport.x) return;

    _paint.shader = Gradient.radial(
      Offset(cx, cy),
      w / 2,
      [
        Palette.fogGlow.withValues(alpha: alpha),
        Palette.fogGlow.withValues(alpha: alpha * 0.55),
        Palette.fogGlow.withValues(alpha: 0),
      ],
      const [0.0, 0.5, 1.0],
      TileMode.clamp,
      // Squash the circle into a low, wide ellipse.
      Float64List.fromList(
        (Matrix4.identity()
              ..translateByDouble(cx, cy, 0, 1)
              ..scaleByDouble(1, h / w, 1, 1)
              ..translateByDouble(-cx, -cy, 0, 1))
            .storage,
      ),
    );
    canvas.drawRect(
      Rect.fromCenter(center: Offset(cx, cy), width: w, height: h),
      _paint,
    );
  }
}
