import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import 'parallax_layer.dart';

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
///  2. a very faint, very sparse row of far trees, barely there;
///  3. the placed scenery from [GameConfig.scenery], each prop scrolling and
///     fading by its own depth, so things arrive one at a time as the player
///     walks;
///  4. a couple of faint shafts of light.
class AtmosphereBackdrop extends Component {
  AtmosphereBackdrop({required this.camera});

  final CameraComponent camera;

  late final ParallaxLayer _mistTrees;
  late final List<_PlacedProp> _props;

  double _time = 0;

  final Paint _fogPaint = Paint();
  final Paint _shaftPaint = Paint()..blendMode = BlendMode.plus;

  @override
  Future<void> onLoad() async {
    final images = Flame.images;

    _mistTrees = ParallaxLayer(
      image: images.fromCache('props/mist_trees.png'),
      speed: 0.10,
      opacity: 0.20,
      heightFraction: 0.95,
      bottomFraction: 0.80,
      verticalSpeed: 0.05,
    );

    _props = [
      for (final prop in GameConfig.scenery)
        _PlacedProp(
          prop,
          images.fromCache(
            'props/${prop.image}${prop.depth > 0.4 ? '_soft' : ''}.png',
          ),
        ),
    ];
  }

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
    final Vector2 cameraPxRel = Vector2(
      cameraWorld.x * pixelsPerMetre,
      (cameraWorld.y - GameConfig.cameraVisibleHeight / 2) * pixelsPerMetre,
    );

    _renderFog(canvas, viewport);
    _mistTrees.render(canvas, viewport, cameraPxRel);
    _renderLightShafts(canvas, viewport);

    // Far props first, so a near one can stand in front of a far one.
    for (final placed in _props) {
      placed.render(canvas, viewport, cameraWorld, pixelsPerMetre);
    }
  }

  void _renderFog(Canvas canvas, Vector2 viewport) {
    final Rect full = Rect.fromLTWH(0, 0, viewport.x, viewport.y);

    // The light breathes very slowly: its centre wanders a little and its
    // reach swells and shrinks, so a still scene is never a dead one.
    final double wander = math.sin(_time * 0.11) * 0.04;
    final double swell = 1 + math.sin(_time * 0.07) * 0.05;
    final Offset centre = Offset(
      viewport.x * (0.48 + wander),
      viewport.y * 0.42,
    );
    _fogPaint.shader = Gradient.radial(
      centre,
      viewport.x * 0.80 * swell,
      const [Palette.fogGlow, Palette.fogMid, Palette.fogEdge],
      const [0.0, 0.62, 1.0],
    );
    canvas.drawRect(full, _fogPaint);

    // The top of the world sinks into shadow — the underside of a canopy that
    // is never actually drawn — and the bottom into the ground's darkness.
    // Both are gentle: the scene stays light in the middle.
    _fogPaint.shader = Gradient.linear(
      Offset.zero,
      Offset(0, viewport.y * 0.30),
      const [Color(0x8C000000), Color(0x00000000)],
    );
    canvas.drawRect(full, _fogPaint);
    _fogPaint.shader = Gradient.linear(
      Offset(0, viewport.y * 0.70),
      Offset(0, viewport.y),
      const [Color(0x00000000), Color(0x7A000000)],
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
      final double strength = 0.025 + 0.025 * pulse;

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
