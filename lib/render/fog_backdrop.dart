import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/game_config.dart';
import 'fog_layer.dart';

/// Everything behind the play layer: grey fog with a hazy light in it and a
/// forest standing in the fog at four depths, each further one paler, more
/// blurred and slower to scroll.
///
/// Lives in `camera.backdrop`, which Flame draws in screen space before the
/// world. Back to front:
///
///  1. the sky: dark at the top, pale fog low down;
///  2. the two far forest layers, almost dissolved into the fog;
///  3. the light: a big soft glow that washes out what is behind it;
///  4. a band of ground mist, then the mid layer, then faint light shafts;
///  5. the near layer, nearly black, with more mist at its feet;
///  6. dust drifting in the light.
///
/// All four layers are baked at load (see [FogLayer]), so a frame costs a
/// handful of image draws and gradients.
class FogBackdrop extends Component {
  FogBackdrop({required this.camera});

  final CameraComponent camera;
  final List<FogLayer> _layers = [];
  double _time = 0;

  /// The world y the far ground lines sit at: roughly the level's ground.
  static const double groundY = 7.0;

  static const List<FogLayerSpec> specs = [
    FogLayerSpec(
      depth: 0.15,
      tone: Color(0xFFA6A6A6),
      blur: 4.5,
      density: 6,
      tileWidth: 180,
      seed: 7,
      trunkSpacing: 13,
      trunkWidth: (1.4, 4.2),
    ),
    FogLayerSpec(
      depth: 0.3,
      tone: Color(0xFF7E7E7E),
      blur: 3.6,
      density: 11,
      tileWidth: 112,
      seed: 19,
      trunkSpacing: 8,
      trunkWidth: (0.8, 2.6),
    ),
    FogLayerSpec(
      depth: 0.55,
      tone: Color(0xFF4A4A4A),
      blur: 2.6,
      density: 20,
      tileWidth: 74,
      seed: 31,
      trunkSpacing: 7,
      trunkWidth: (0.5, 1.7),
      vines: true,
    ),
    FogLayerSpec(
      depth: 0.8,
      tone: Color(0xFF202020),
      blur: 1.5,
      density: 32,
      tileWidth: 52,
      seed: 43,
      trunkSpacing: 9,
      trunkWidth: (0.35, 1.2),
      vines: true,
    ),
  ];

  // Light is laid over the fog with ordinary alpha blending. BlendMode.screen
  // looks much the same, but Impeller emulates it on OpenGL ES and drew
  // dashed arcs across the picture on the Android emulator.
  final Paint _paint = Paint();
  final Paint _light = Paint()..filterQuality = FilterQuality.low;
  final Paint _shaftPaint = Paint()..filterQuality = FilterQuality.low;
  final List<_Mote> _motes = [];
  late final Image _shaft;
  late final Image _glow;

  /// The hazy light, a soft radial falloff baked once. Drawn live, the
  /// gradient's stops showed as dotted rings under Impeller on the emulator.
  static Image _bakeGlow() {
    const double size = 256;
    final recorder = PictureRecorder();
    Canvas(recorder).drawRect(
      const Rect.fromLTWH(0, 0, size, size),
      Paint()
        ..shader = Gradient.radial(
          const Offset(size / 2, size / 2),
          size / 2,
          // A smooth bell-shaped falloff, with no kink for banding to
          // gather along.
          const [
            Color(0x9EFFFFFF),
            Color(0x7AFDFDFD),
            Color(0x4CF7F7F7),
            Color(0x26F2F2F2),
            Color(0x0CF0F0F0),
            Color(0x00F0F0F0),
          ],
          const [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        ),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size.toInt(), size.toInt());
    picture.dispose();
    return image;
  }

  /// A soft wedge of light, narrow at the top and fading as it widens,
  /// blurred once so that drawing it costs one scaled image.
  static Image _bakeShaft() {
    const int width = 64, height = 256;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.saveLayer(
      const Rect.fromLTWH(0, 0, 64, 256),
      Paint()..imageFilter = ImageFilter.blur(sigmaX: 7, sigmaY: 7),
    );
    canvas.drawPath(
      Path()
        ..moveTo(28, 0)
        ..lineTo(36, 0)
        ..lineTo(54, 256)
        ..lineTo(10, 256)
        ..close(),
      Paint()
        ..shader = Gradient.linear(
          Offset.zero,
          const Offset(0, 256),
          const [Color(0xFFFFFFFF), Color(0x66FFFFFF), Color(0x00FFFFFF)],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width, height);
    picture.dispose();
    return image;
  }

  @override
  Future<void> onLoad() async {
    for (final spec in specs) {
      _layers.add(
        FogLayer.bake(
          spec,
          visibleHeight: GameConfig.cameraVisibleHeight,
          maxCameraRise: 3.5,
        ),
      );
    }
    _shaft = _bakeShaft();
    _glow = _bakeGlow();
    final random = math.Random(5);
    for (var i = 0; i < 36; i++) {
      _motes.add(_Mote(random));
    }
  }

  @override
  void update(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    final Vector2 viewport = camera.viewport.size;
    if (viewport.x <= 0 || viewport.y <= 0) return;
    final Size size = Size(viewport.x, viewport.y);
    final double ppm = size.height / camera.visibleWorldRect.height;
    final Vector2 cam = camera.viewfinder.position;
    final Rect full = Offset.zero & size;

    // 1. Sky.
    _paint.shader = Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      const [
        Color(0xFF3E3E3E),
        Color(0xFF9C9C9C),
        Color(0xFFB8B8B8),
        Color(0xFF8E8E8E),
      ],
      const [0.0, 0.32, 0.6, 1.0],
    );
    canvas.drawRect(full, _paint);

    // 2. Far forest.
    for (var i = 0; i < 2; i++) {
      _layers[i].render(canvas, size, cam.x, cam.y, ppm, groundY: groundY);
    }

    // 3. The light, drifting very slowly with the camera.
    final Offset light = Offset(
      size.width * (0.56 - 0.12 * math.sin(cam.x * 0.021)),
      size.height * 0.24,
    );
    canvas.drawImageRect(
      _glow,
      Rect.fromLTWH(0, 0, _glow.width.toDouble(), _glow.height.toDouble()),
      Rect.fromCircle(center: light, radius: size.width * 0.62),
      _light,
    );

    // 4. Mist, the mid layer, then shafts of light through it.
    _mist(canvas, size, _layers[1], cam.y, ppm, 0.55);
    _layers[2].render(canvas, size, cam.x, cam.y, ppm, groundY: groundY);
    _mist(canvas, size, _layers[2], cam.y, ppm, 0.45);
    _shafts(canvas, size, light);

    // 5. Near layer.
    _layers[3].render(canvas, size, cam.x, cam.y, ppm, groundY: groundY);
    _mist(canvas, size, _layers[3], cam.y, ppm, 0.30);

    // 6. Dust.
    _dust(canvas, size, cam, ppm, light);
    _paint.shader = null;
  }

  /// Fog lying along a layer's ground line, thickest where it touches.
  void _mist(
    Canvas canvas,
    Size size,
    FogLayer layer,
    double cameraY,
    double ppm,
    double strength,
  ) {
    final double y = layer.groundLine(size, cameraY, ppm, groundY: groundY);
    final double reach = math.max(40, 2.4 * layer.spec.depth * ppm);
    final int alpha = (strength * 255).round();
    _paint.shader = Gradient.linear(
      Offset(0, y - reach),
      Offset(0, y + reach * 0.5),
      [
        const Color(0x00B4B4B4),
        Color.fromARGB(alpha, 0xB4, 0xB4, 0xB4),
        Color.fromARGB(alpha ~/ 2, 0xA0, 0xA0, 0xA0),
      ],
      const [0.0, 0.7, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(0, y - reach, size.width, y + reach * 0.5),
      _paint,
    );
  }

  /// Two or three faint beams from the light, slowly breathing.
  void _shafts(Canvas canvas, Size size, Offset light) {
    final Rect source = Rect.fromLTWH(
      0,
      0,
      _shaft.width.toDouble(),
      _shaft.height.toDouble(),
    );
    for (var i = 0; i < 3; i++) {
      final double flicker =
          0.7 +
          0.3 *
              math.sin(_time * (0.5 + i * 0.21) + i * 1.7) *
              math.sin(_time * 0.13 + i);
      final double angle = 0.38 - i * 0.34 + math.sin(_time * 0.04 + i) * 0.03;
      final double length = size.height * (1.15 + i * 0.1);
      final double spread = size.width * (0.22 + i * 0.06);
      _shaftPaint.color = Color.fromRGBO(255, 255, 255, 0.075 * flicker);
      canvas.save();
      canvas.translate(light.dx, light.dy);
      canvas.rotate(angle);
      canvas.drawImageRect(
        _shaft,
        source,
        Rect.fromLTWH(-spread / 2, 0, spread, length),
        _shaftPaint,
      );
      canvas.restore();
    }
  }

  /// Specks drifting in the air, brighter in the light.
  void _dust(Canvas canvas, Size size, Vector2 cam, double ppm, Offset light) {
    _paint.shader = null;
    for (final mote in _motes) {
      final double scroll = cam.x * ppm * mote.depth;
      final double x =
          (mote.x * size.width * 1.4 -
                  scroll +
                  math.sin(_time * mote.speed + mote.phase) * 30) %
              (size.width * 1.4) -
          size.width * 0.2;
      final double y =
          (mote.y * size.height + _time * 6 * mote.speed) % size.height;
      final double distance = (Offset(x, y) - light).distance / size.width;
      final double brightness = (0.45 - distance).clamp(0.0, 0.45) * 0.6;
      if (brightness <= 0.01) continue;
      _paint.color = Color.fromRGBO(255, 255, 255, brightness);
      canvas.drawCircle(Offset(x, y), mote.size, _paint);
    }
  }

  @override
  void onRemove() {
    for (final layer in _layers) {
      layer.dispose();
    }
    _layers.clear();
    _shaft.dispose();
    _glow.dispose();
    super.onRemove();
  }
}

class _Mote {
  _Mote(math.Random random)
    : x = random.nextDouble(),
      y = random.nextDouble(),
      depth = 0.4 + random.nextDouble() * 0.6,
      speed = 0.3 + random.nextDouble() * 0.8,
      phase = random.nextDouble() * 6,
      size = 0.8 + random.nextDouble() * 1.3;
  final double x, y, depth, speed, phase, size;
}

/// Out-of-focus shapes between the camera and the boy: the odd huge trunk
/// passing across the frame and blurred grass along its bottom edge. Drawn
/// in the viewport, over the world but under the lens effects.
class ForegroundFog extends Component {
  ForegroundFog({required this.camera}) : super(priority: -20);

  final CameraComponent camera;
  late final FogLayer _layer;

  static const spec = FogLayerSpec(
    depth: 1.45,
    tone: Color(0xFF030303),
    blur: 2.4,
    density: 12,
    tileWidth: 90,
    seed: 61,
    trunkSpacing: 42,
    trunkWidth: (0.5, 1.3),
    foreground: true,
  );

  @override
  Future<void> onLoad() async {
    _layer = FogLayer.bake(
      spec,
      visibleHeight: GameConfig.cameraVisibleHeight,
      maxCameraRise: 3.5,
    );
  }

  @override
  void render(Canvas canvas) {
    final Vector2 viewport = camera.viewport.size;
    if (viewport.x <= 0 || viewport.y <= 0) return;
    final double ppm = viewport.y / camera.visibleWorldRect.height;
    final Vector2 cam = camera.viewfinder.position;
    _layer.render(
      canvas,
      Size(viewport.x, viewport.y),
      cam.x,
      cam.y,
      ppm,
      groundY: FogBackdrop.groundY,
      opacity: 0.94,
    );
  }

  @override
  void onRemove() {
    _layer.dispose();
    super.onRemove();
  }
}
