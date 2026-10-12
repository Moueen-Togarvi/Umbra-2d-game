import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

/// A little film grain and a darkened lens edge. The air itself stays empty.
class ForegroundOverlay extends Component {
  ForegroundOverlay({required this.camera}) : super(priority: -10);

  final CameraComponent camera;
  late final Image _grain;
  final math.Random _random = math.Random(3);
  final Paint _vignettePaint = Paint();
  final Paint _grainPaint = Paint()
    ..color = const Color(0x08FFFFFF)
    ..filterQuality = FilterQuality.none;

  @override
  Future<void> onLoad() async {
    _grain = Flame.images.fromCache('grain.png');
  }

  @override
  void render(Canvas canvas) {
    final Vector2 viewport = camera.viewport.size;
    if (viewport.x <= 0 || viewport.y <= 0) return;
    final Rect full = Rect.fromLTWH(0, 0, viewport.x, viewport.y);
    _vignettePaint.shader = Gradient.radial(
      Offset(viewport.x * 0.49, viewport.y * 0.45),
      viewport.x * 0.77,
      const [Color(0x00000000), Color(0x00000000), Color(0xAA000000)],
      const [0, 0.40, 1],
    );
    canvas.drawRect(full, _vignettePaint);

    final double ox = -_random.nextDouble() * _grain.width;
    final double oy = -_random.nextDouble() * _grain.height;
    final Rect src = Rect.fromLTWH(
      0,
      0,
      _grain.width.toDouble(),
      _grain.height.toDouble(),
    );
    final double tile = _grain.width * 2.0;
    for (double y = oy; y < viewport.y; y += tile) {
      for (double x = ox; x < viewport.x; x += tile) {
        canvas.drawImageRect(
          _grain,
          src,
          Rect.fromLTWH(x, y, tile, tile),
          _grainPaint,
        );
      }
    }
  }
}
