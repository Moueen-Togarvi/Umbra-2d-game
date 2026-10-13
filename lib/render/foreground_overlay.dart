import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

/// The lens: LIMBO's heavy rounded vignette, a darker sky edge, film grain
/// that changes every frame, and a faint projector flicker.
class ForegroundOverlay extends Component {
  ForegroundOverlay({required this.camera}) : super(priority: -10);

  final CameraComponent camera;
  Image? _grain;
  late final Image _vignette;
  final math.Random _random = math.Random(3);
  final Paint _vignettePaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _flickerPaint = Paint();
  final Paint _grainPaint = Paint()
    ..color = const Color(0x0DFFFFFF)
    ..filterQuality = FilterQuality.none;
  double _flicker = 0;
  double _sinceFlicker = 0;

  @override
  Future<void> onLoad() async {
    if (Flame.images.containsKey('grain.png')) {
      _grain = Flame.images.fromCache('grain.png');
    }
    _vignette = _bakeVignette();
  }

  /// The vignette and the darker top edge, baked once into a small image
  /// that is stretched over the screen. Drawn live, the radial gradient's
  /// stops showed as dashed rings under Impeller on the Android emulator.
  static Image _bakeVignette() {
    const double w = 512, h = 256;
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    const Rect full = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      full,
      Paint()
        ..shader = Gradient.radial(
          const Offset(w * 0.5, h * 0.47),
          math.sqrt(w * w + h * h) * 0.56,
          const [
            Color(0x00000000),
            Color(0x00000000),
            Color(0x8C000000),
            Color(0xF2000000),
          ],
          const [0, 0.42, 0.78, 1],
        ),
    );
    canvas.drawRect(
      full,
      Paint()
        ..shader = Gradient.linear(
          Offset.zero,
          const Offset(0, h * 0.3),
          const [Color(0x66000000), Color(0x00000000)],
        ),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w.toInt(), h.toInt());
    picture.dispose();
    return image;
  }

  @override
  void update(double dt) {
    // The flicker changes at film rate, not at display rate.
    _sinceFlicker += dt;
    if (_sinceFlicker >= 1 / 24) {
      _sinceFlicker = 0;
      _flicker = _random.nextDouble() * _random.nextDouble() * 0.045;
    }
  }

  @override
  void render(Canvas canvas) {
    final Vector2 viewport = camera.viewport.size;
    if (viewport.x <= 0 || viewport.y <= 0) return;
    final Rect full = Rect.fromLTWH(0, 0, viewport.x, viewport.y);
    canvas.drawImageRect(
      _vignette,
      Rect.fromLTWH(
        0,
        0,
        _vignette.width.toDouble(),
        _vignette.height.toDouble(),
      ),
      full,
      _vignettePaint,
    );

    _flickerPaint.color = Color.fromRGBO(0, 0, 0, _flicker);
    canvas.drawRect(full, _flickerPaint);

    final Image? grain = _grain;
    if (grain == null) return;
    final double ox = -_random.nextDouble() * grain.width;
    final double oy = -_random.nextDouble() * grain.height;
    final Rect src = Rect.fromLTWH(
      0,
      0,
      grain.width.toDouble(),
      grain.height.toDouble(),
    );
    final double tile = grain.width * 1.5;
    for (double y = oy; y < viewport.y; y += tile) {
      for (double x = ox; x < viewport.x; x += tile) {
        canvas.drawImageRect(
          grain,
          src,
          Rect.fromLTWH(x, y, tile, tile),
          _grainPaint,
        );
      }
    }
  }

  @override
  void onRemove() {
    _vignette.dispose();
    super.onRemove();
  }
}

/// Fades the picture to black and back for the death sequence.
class ScreenFade extends Component {
  ScreenFade({required this.camera, required this.blackness})
    : super(priority: -5);

  final CameraComponent camera;
  final double Function() blackness;
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    final double alpha = blackness();
    if (alpha <= 0) return;
    final Vector2 viewport = camera.viewport.size;
    _paint.color = Color.fromRGBO(0, 0, 0, alpha.clamp(0.0, 1.0));
    canvas.drawRect(Rect.fromLTWH(0, 0, viewport.x, viewport.y), _paint);
  }
}
