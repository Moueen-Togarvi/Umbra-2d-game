import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../config/game_config.dart';
import 'fog_layer.dart';
import 'mood.dart';
import 'scenery.dart';

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
///
/// What the air looks like comes from the stage's [Mood], read afresh each
/// frame from [moods] at the camera's x, so a chapter can fall from dusk
/// into night as the boy walks. A cave mood stands rock in the fog instead
/// of trees.
class FogBackdrop extends Component {
  FogBackdrop({
    required this.camera,
    this.moods = const MoodTrack(Mood.fog),
    this.layerSpecs,
    this.groundFor,
    List<BackdropDrawable> Function()? props,
  }) : _props = props ?? (() => const []);

  final CameraComponent camera;
  final MoodTrack moods;

  /// The four layers, if not the usual forest or cave.
  final List<FogLayerSpec>? layerSpecs;

  /// Far scenery to stand among the layers.
  final List<BackdropDrawable> Function() _props;
  final List<FogLayer> _layers = [];
  double _time = 0;

  /// The world y the far ground lines sit at: roughly the level's ground.
  static const double groundY = 7.0;

  /// The far ground lines' height for the camera at x, if the stage's
  /// ground rises and falls; followed slowly so the hills drift, not jump.
  final double Function(double cameraX)? groundFor;
  double _ground = groundY;
  bool _groundSet = false;

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

  /// The same four depths with the trees far apart: the edge of the
  /// forest, open country with a few trees standing in it.
  static final List<FogLayerSpec> sparse = [
    for (final spec in specs)
      FogLayerSpec(
        depth: spec.depth,
        tone: spec.tone,
        blur: spec.blur,
        density: spec.density,
        tileWidth: spec.tileWidth,
        seed: spec.seed + 3,
        trunkSpacing: spec.trunkSpacing * (spec.depth < 0.5 ? 2.2 : 3.4),
        trunkWidth: spec.trunkWidth,
        vines: spec.vines,
      ),
  ];

  /// The same four depths as a cave.
  static const List<FogLayerSpec> caveSpecs = [
    FogLayerSpec(
      depth: 0.15,
      tone: Color(0xFF34363A),
      blur: 4.5,
      density: 6,
      tileWidth: 180,
      seed: 11,
      trunkSpacing: 9,
      trunkWidth: (6, 11),
      rock: true,
    ),
    FogLayerSpec(
      depth: 0.3,
      tone: Color(0xFF232427),
      blur: 3.6,
      density: 11,
      tileWidth: 112,
      seed: 23,
      trunkSpacing: 6,
      trunkWidth: (3, 6),
      rock: true,
    ),
    FogLayerSpec(
      depth: 0.55,
      tone: Color(0xFF141416),
      blur: 2.6,
      density: 20,
      tileWidth: 74,
      seed: 37,
      trunkSpacing: 5,
      trunkWidth: (1.6, 3.4),
      rock: true,
    ),
    FogLayerSpec(
      depth: 0.8,
      tone: Color(0xFF070707),
      blur: 1.5,
      density: 32,
      tileWidth: 52,
      seed: 47,
      trunkSpacing: 6,
      trunkWidth: (1.0, 2.2),
      rock: true,
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
  late final Image _moon;

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

  /// The moon as the fog lets it through: a pale disc with a soft rim.
  static Image _bakeMoon() {
    const int size = 96;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.saveLayer(
      Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      Paint()..imageFilter = ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
    );
    canvas.drawCircle(
      const Offset(size / 2, size / 2),
      size * 0.36,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.restore();
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
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
    for (final spec in layerSpecs ?? (moods.from.trees ? specs : caveSpecs)) {
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
    _moon = _bakeMoon();
    final random = math.Random(5);
    for (var i = 0; i < 36; i++) {
      _motes.add(_Mote(random));
    }
  }

  @override
  void update(double dt) {
    _time += dt;
    final double Function(double)? ground = groundFor;
    if (ground == null) return;
    final double target = ground(camera.viewfinder.position.x);
    if (!_groundSet) {
      _ground = target;
      _groundSet = true;
    } else {
      _ground += (target - _ground) * math.min(1, dt * 0.8);
    }
  }

  @override
  void render(Canvas canvas) {
    final Vector2 viewport = camera.viewport.size;
    if (viewport.x <= 0 || viewport.y <= 0) return;
    final Size size = Size(viewport.x, viewport.y);
    final double ppm = size.height / camera.visibleWorldRect.height;
    final Vector2 cam = camera.viewfinder.position;
    final Rect full = Offset.zero & size;

    final Mood mood = moods.at(cam.x);

    // 1. Sky. A shader paints with the paint colour's opacity, and the dust
    // below leaves that faint: make it opaque again, or last frame's mote
    // shows the background through the sky.
    _paint.color = const Color(0xFFFFFFFF);
    _paint.shader = Gradient.linear(
      Offset.zero,
      Offset(0, size.height),
      mood.sky,
      Mood.skyStops,
    );
    canvas.drawRect(full, _paint);

    // 2. Far layers, and any scenery standing among them.
    final List<BackdropDrawable> props = _props();
    for (var i = 0; i < 2; i++) {
      _layers[i].render(
        canvas,
        size,
        cam.x,
        cam.y,
        ppm,
        groundY: _ground,
        tint: mood.layerTones[i],
      );
      _scenery(canvas, size, cam, ppm, mood, props, i);
    }

    // 3. The light, drifting very slowly with the camera.
    final Offset light = Offset(
      size.width *
          (mood.lightAt.dx - mood.lightDrift * math.sin(cam.x * 0.021)),
      size.height * mood.lightAt.dy,
    );
    _light.color = Color.fromRGBO(0, 0, 0, mood.lightStrength.clamp(0.0, 1.0));
    _light.colorFilter = mood.light == const Color(0xFFFFFFFF)
        ? null
        : ColorFilter.mode(mood.light, BlendMode.modulate);
    final Rect glowSource = Rect.fromLTWH(
      0,
      0,
      _glow.width.toDouble(),
      _glow.height.toDouble(),
    );
    canvas.drawImageRect(
      _glow,
      glowSource,
      Rect.fromCircle(center: light, radius: size.width * mood.lightSize),
      _light,
    );
    if (mood.lightStrength > 1) {
      // A stronger light burns a smaller, brighter core into the fog.
      _light.color = Color.fromRGBO(0, 0, 0, mood.lightStrength - 1);
      canvas.drawImageRect(
        _glow,
        glowSource,
        Rect.fromCircle(
          center: light,
          radius: size.width * mood.lightSize * 0.45,
        ),
        _light,
      );
    }
    if (mood.moon) {
      _light.color = const Color.fromRGBO(0, 0, 0, 0.62);
      canvas.drawImageRect(
        _moon,
        Rect.fromLTWH(0, 0, _moon.width.toDouble(), _moon.height.toDouble()),
        Rect.fromCircle(center: light, radius: size.height * 0.075),
        _light,
      );
    }

    // 4. Mist, the mid layer, then shafts of light through it.
    _mist(canvas, size, _layers[1], cam.y, ppm, 0.55 * mood.mist, mood);
    _layers[2].render(
      canvas,
      size,
      cam.x,
      cam.y,
      ppm,
      groundY: _ground,
      tint: mood.layerTones[2],
    );
    _scenery(canvas, size, cam, ppm, mood, props, 2);
    _mist(canvas, size, _layers[2], cam.y, ppm, 0.45 * mood.mist, mood);
    _shafts(canvas, size, light, mood);

    // 5. Near layer.
    _layers[3].render(
      canvas,
      size,
      cam.x,
      cam.y,
      ppm,
      groundY: _ground,
      tint: mood.layerTones[3],
    );
    _scenery(canvas, size, cam, ppm, mood, props, 3);
    _mist(canvas, size, _layers[3], cam.y, ppm, 0.30 * mood.mist, mood);

    // 6. Dust, or drips.
    _dust(canvas, size, cam, ppm, light, mood);
    _paint.shader = null;
  }

  /// The scenery between layer [i] and the next nearer one, drawn in world
  /// metres.
  void _scenery(
    Canvas canvas,
    Size size,
    Vector2 cam,
    double ppm,
    Mood mood,
    List<BackdropDrawable> props,
    int i,
  ) {
    if (props.isEmpty) return;
    final double from = _layers[i].spec.depth;
    final double to = i + 1 < _layers.length ? _layers[i + 1].spec.depth : 2;
    var any = false;
    for (final prop in props) {
      if (prop.depth < from || prop.depth >= to) continue;
      if (!any) {
        canvas.save();
        canvas.translate(size.width / 2, size.height / 2);
        canvas.scale(ppm);
        canvas.translate(-cam.x, -cam.y);
        any = true;
      }
      // It stands on the far ground, which rises and falls with the land.
      final double lift = (_ground - groundY) * prop.depth;
      if (lift != 0) canvas.translate(0, lift);
      prop.paint(canvas, cam, mood);
      if (lift != 0) canvas.translate(0, -lift);
    }
    if (any) canvas.restore();
  }

  /// Fog lying along a layer's ground line, thickest where it touches.
  void _mist(
    Canvas canvas,
    Size size,
    FogLayer layer,
    double cameraY,
    double ppm,
    double strength,
    Mood mood,
  ) {
    if (strength <= 0.005) return;
    final double y = layer.groundLine(size, cameraY, ppm, groundY: _ground);
    final double reach = math.max(40, 2.4 * layer.spec.depth * ppm);
    final double alpha = strength.clamp(0.0, 1.0);
    final Color tone = mood.mistTone;
    // The mist's lower edge is a shade darker than its body.
    final Color under = Color.lerp(tone, const Color(0xFF000000), 0.11)!;
    _paint.color = const Color(0xFFFFFFFF);
    _paint.shader = Gradient.linear(
      Offset(0, y - reach),
      Offset(0, y + reach * 0.5),
      [
        tone.withValues(alpha: 0),
        tone.withValues(alpha: alpha),
        under.withValues(alpha: alpha / 2),
      ],
      const [0.0, 0.7, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(0, y - reach, size.width, y + reach * 0.5),
      _paint,
    );
  }

  /// Two or three faint beams from the light, slowly breathing.
  void _shafts(Canvas canvas, Size size, Offset light, Mood mood) {
    if (mood.shafts <= 0.01) return;
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
      final double angle =
          mood.shaftTilt +
          (1 - i) * mood.shaftFan +
          math.sin(_time * 0.04 + i) * 0.03;
      final double length = size.height * (1.15 + i * 0.1);
      final double spread = size.width * (0.22 + i * 0.06);
      _shaftPaint.color = mood.light.withValues(
        alpha: (0.075 * flicker * mood.shafts).clamp(0.0, 1.0),
      );
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

  /// Specks drifting in the air, brighter in the light. In a cave they are
  /// drops of water falling through the shaft instead.
  void _dust(
    Canvas canvas,
    Size size,
    Vector2 cam,
    double ppm,
    Offset light,
    Mood mood,
  ) {
    _paint.shader = null;
    if (mood.drips) {
      _drips(canvas, size, cam, ppm, light, mood);
      return;
    }
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
      final double brightness =
          (0.45 - distance).clamp(0.0, 0.45) * 0.6 * mood.dust;
      if (brightness <= 0.01) continue;
      _paint.color = Color.fromRGBO(255, 255, 255, brightness.clamp(0, 1));
      canvas.drawCircle(Offset(x, y), mote.size, _paint);
    }
  }

  /// Water falling from the roof: short streaks, lit only near the shaft.
  void _drips(
    Canvas canvas,
    Size size,
    Vector2 cam,
    double ppm,
    Offset light,
    Mood mood,
  ) {
    _paint
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final mote in _motes) {
      final double scroll = cam.x * ppm * mote.depth;
      final double x =
          (mote.x * size.width * 1.4 - scroll) % (size.width * 1.4) -
          size.width * 0.2;
      // Each drop falls, then waits a while before the next one.
      final double period = 2.2 + mote.phase * 0.5;
      final double t = (_time * (0.6 + mote.speed * 0.4) + mote.phase) % period;
      if (t > 1) continue;
      final double y = size.height * (mote.y * 0.3 + t * t * 1.4);
      if (y > size.height) continue;
      final double lit = 1 - ((x - light.dx).abs() / (size.width * 0.3));
      final double brightness = lit.clamp(0.08, 1.0) * 0.32 * mood.dust;
      _paint
        ..strokeWidth = mote.size * 0.7
        ..color = mood.light.withValues(alpha: brightness.clamp(0, 1));
      final double streak = 4 + t * 16;
      canvas.drawLine(Offset(x, y - streak), Offset(x, y), _paint);
    }
    _paint.style = PaintingStyle.fill;
  }

  @override
  void onRemove() {
    for (final layer in _layers) {
      layer.dispose();
    }
    _layers.clear();
    _shaft.dispose();
    _glow.dispose();
    _moon.dispose();
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
