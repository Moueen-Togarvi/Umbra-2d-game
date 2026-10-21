import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart' show FlameGame;

import '../world/stage.dart';
import 'mood.dart';

/// Something far enough off to be drawn among the fog layers: the
/// backdrop calls [paint] with a canvas in world metres.
abstract interface class BackdropDrawable {
  /// 1 is the play plane; less is further off.
  double get depth;
  void paint(Canvas canvas, Vector2 cam, Mood mood);
}

/// A baked silhouette standing in the world, or behind it in the fog.
///
/// The art (see `tools/bake_silhouettes.py`) is black with the shape in
/// alpha. At [depth] 1 the prop stands on the play plane and scrolls with
/// the ground; below 1 it is further off, drawn smaller and scrolling
/// slower about the camera, exactly like the fog layers behind it, so it
/// sits on their ground. From [nearDepth] up it stands on the path, placed
/// exactly and pure black. [fog] is how much of the air lies between it and
/// the camera: 0 is pure black, 1 would be the fog itself. It defaults to
/// what the depth implies.
///
/// Pure scenery: no body, nothing to touch.
class SceneryProp extends Component implements BackdropDrawable {
  SceneryProp(
    this.image, {
    required this.x,
    required this.baseY,
    required this.height,
    this.depth = 1,
    double? fog,
    this.flip = false,
    double? sourceBottom,
    super.priority,
  }) : assert(sourceBottom == null || (sourceBottom > 0 && sourceBottom <= 1)),
       sourceBottom =
           sourceBottom ??
           (image.startsWith('part1/ch2_giant_tree_a') ? 0.84 : 1),
       fog = fog ?? defaultFog(depth);

  /// The image's name under `assets/images/`, e.g. `part1/ch1_cottage.png`.
  final String image;

  /// Where the bottom middle of the art stands, world metres at depth 1.
  /// Mutable so a chapter can settle it on a clear piece of ground (see
  /// `arrangeSurfaceDecor`).
  double x, baseY;

  /// The art's height, metres at depth 1.
  final double height;
  @override
  final double depth;
  final double fog;

  /// Drawn mirrored left to right.
  final bool flip;

  /// Fraction of the existing asset retained from its top. The root-heavy
  /// giant tree gets one shared crop wherever it appears in the campaign.
  final double sourceBottom;

  /// How much fog a thing at [depth] stands behind.
  static double defaultFog(double depth) {
    // Standing on the path, among the things he touches: pure black.
    if (depth >= nearDepth) return 0;
    final double t = (1 - depth).clamp(0.0, 1.0);
    // Like the fog layers: dark for a while, then quickly paler.
    return (0.18 + 0.68 * t).clamp(0.0, 0.92);
  }

  Image? _art;
  CameraComponent? _camera;
  Stage? _stage;
  // Bilinear, not mipmapped: shrunk mipmaps smeared the art's edge into a
  // faint frame round it under Impeller.
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  /// The area the art covers now, world metres; empty until drawn once.
  Rect drawnRect = Rect.zero;

  /// From this depth up, a prop stands on the path with the boy.
  static const double nearDepth = 0.85;

  /// Far enough off to be drawn among the fog layers, by the backdrop.
  bool get inBackdrop => depth < nearDepth;

  /// Whether it is drawn on the path with the boy: near, not replaced by
  /// a painted background, and with its art loaded.
  bool get standsOnPath =>
      !inBackdrop &&
      _art != null &&
      !(_stage?.backgroundPlan?.replacesProp(image, depth) ?? false);

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
    _stage = ancestors().whereType<Stage>().firstOrNull;
    if (_stage?.backgroundPlan?.replacesProp(image, depth) ?? false) return;
    if (inBackdrop) _stage?.backdropProps.add(this);
    // Blurred art reads better far off, and is cheaper to scale down.
    final String far = image.endsWith('_far.png')
        ? image
        : image.replaceFirst('.png', '_far.png');
    final String name = inBackdrop ? far : image;
    try {
      _art = await Flame.images.load(name);
    } catch (_) {
      try {
        _art = await Flame.images.load(image);
      } catch (_) {
        // Missing art (a bare test binding): nothing to draw.
      }
    }
  }

  /// The rectangle the art would cover for a camera at [camera].
  Rect rectFor(Vector2 camera) {
    final Image? art = _art;
    final double aspect = art == null
        ? 1
        : art.width / (art.height * sourceBottom);
    // Something on the path is placed exactly where it stands: scaling it
    // about the camera would lift it off the ground it is meant to be on.
    final double k = inBackdrop ? depth : 1;
    final double cx = camera.x + (x - camera.x) * k;
    final double base = camera.y + (baseY - camera.y) * k;
    final double h = height * k;
    final double w = h * aspect;
    return Rect.fromLTRB(cx - w / 2, base - h, cx + w / 2, base);
  }

  /// The tone the art is drawn in under [mood].
  Color toneFor(Mood mood) =>
      Color.lerp(const Color(0xFF000000), mood.sky[2], fog)!;

  @override
  void onRemove() {
    _stage?.backdropProps.remove(this);
    super.onRemove();
  }

  @override
  void render(Canvas canvas) {
    if (_stage?.backgroundPlan?.replacesProp(image, depth) ?? false) return;
    // Far scenery is drawn by the backdrop, among the fog layers.
    if (inBackdrop && _stage != null) return;
    final Vector2 cam = _camera?.viewfinder.position ?? Vector2(x, baseY);
    paint(canvas, cam, _stage?.moods.at(cam.x) ?? Mood.fog);
  }

  /// Draws the art for a camera at [cam] on a canvas in world metres.
  @override
  void paint(Canvas canvas, Vector2 cam, Mood mood) {
    final Image? art = _art;
    if (art == null) return;
    final Rect rect = drawnRect = rectFor(cam);
    final Rect? view = _camera?.visibleWorldRect;
    if (view != null && !view.inflate(0.5).overlaps(rect)) return;
    _paint.colorFilter = fog <= 0.001
        ? null
        : ColorFilter.mode(toneFor(mood), BlendMode.srcIn);
    final Rect source = Rect.fromLTWH(
      0,
      0,
      art.width.toDouble(),
      art.height * sourceBottom,
    );
    if (flip) {
      canvas.save();
      canvas.translate(rect.center.dx, 0);
      canvas.scale(-1, 1);
      canvas.translate(-rect.center.dx, 0);
      canvas.drawImageRect(art, source, rect, _paint);
      canvas.restore();
    } else {
      canvas.drawImageRect(art, source, rect, _paint);
    }
  }
}

/// A small warm light far away in the fog: a lit window seen from a
/// distance. Placed like a [SceneryProp] at [depth], so it drifts with the
/// far hills.
class DistantLight extends Component {
  DistantLight({
    required this.x,
    required this.y,
    this.depth = 0.2,
    this.color = const Color(0xFFE8A84A),
    this.showFrom = double.negativeInfinity,
    this.showTo = double.negativeInfinity,
    super.priority = -50,
  });

  final double x, y, depth;

  /// It fades in as the camera goes from [showFrom] to [showTo] in x.
  final double showFrom, showTo;
  final Color color;
  double brightness = 1;
  double _time = 0;
  CameraComponent? _camera;
  final Paint _paint = Paint();

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
  }

  @override
  void update(double dt) => _time += dt;

  /// Where it is drawn for a camera at [camera].
  Offset drawnAt(Vector2 camera) => Offset(
    camera.x + (x - camera.x) * depth,
    camera.y + (y - camera.y) * depth,
  );

  @override
  void render(Canvas canvas) {
    final CameraComponent? camera = _camera;
    if (camera == null || brightness <= 0.01) return;
    final Vector2 cam = camera.viewfinder.position;
    final double shown = showTo <= showFrom
        ? 1
        : ((cam.x - showFrom) / (showTo - showFrom)).clamp(0.0, 1.0);
    if (shown <= 0.01) return;
    final Offset at = drawnAt(cam);
    if (!camera.visibleWorldRect.inflate(1).contains(at)) return;
    final double flicker =
        0.9 + 0.1 * math.sin(_time * 5.3) * math.sin(_time * 1.7);
    final double a = brightness * flicker * shown;
    // Opaque: a shader paints at the paint colour's opacity.
    _paint.color = const Color(0xFFFFFFFF);
    _paint.shader = Gradient.radial(
      at,
      0.9,
      [
        color.withValues(alpha: 0.32 * a),
        color.withValues(alpha: 0.08 * a),
        color.withValues(alpha: 0),
      ],
      const [0, 0.3, 1],
    );
    canvas.drawCircle(at, 0.9, _paint);
    _paint.shader = null;
    _paint.color = Color.lerp(
      color,
      const Color(0xFFFFF1D6),
      0.4,
    )!.withValues(alpha: a);
    canvas.drawRect(
      Rect.fromCenter(center: at, width: 0.07, height: 0.06),
      _paint,
    );
  }
}
