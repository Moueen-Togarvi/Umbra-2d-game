import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import '../config/palette.dart';

/// Six original monochrome places along one continuous, playable level.
///
/// Each plate covers sixteen metres. The ground and player are separate world
/// objects, so collision stays precise while the art scrolls behind them.
class SixAreasBackdrop extends Component {
  SixAreasBackdrop({required this.camera});

  final CameraComponent camera;
  late final List<Image> _plates;
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.medium;
  final Paint _fogPaint = Paint();
  final Paint _blendPaint = Paint()..blendMode = BlendMode.dstIn;

  @override
  Future<void> onLoad() async {
    _plates = [
      for (var i = 1; i <= 6; i++)
        Flame.images.fromCache('backgrounds/area_0$i.png'),
    ];
  }

  @override
  void render(Canvas canvas) {
    final Vector2 size = camera.viewport.size;
    if (size.x <= 0 || size.y <= 0) return;
    final double ppm = size.y / camera.visibleWorldRect.height;
    final double cameraX = camera.viewfinder.position.x;
    final Rect full = Rect.fromLTWH(0, 0, size.x, size.y);
    canvas.drawRect(full, Paint()..color = Palette.fogMid);

    for (var i = 0; i < _plates.length; i++) {
      // Keep the original area plates, with their distant silhouettes drifting
      // slightly slower than the physical foreground. The small overlap avoids
      // cracks between plates throughout a camera pan.
      final double left =
          size.x / 2 + ((i * 16 + 8 - cameraX) * 0.94 - 8) * ppm;
      final double right = left + 16 * ppm;
      if (right < 0 || left > size.x) continue;
      final Image image = _plates[i];
      final destination = Rect.fromLTRB(left, 0, right, size.y);
      if (i > 0) canvas.saveLayer(destination, Paint());
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        destination,
        _imagePaint,
      );
      if (i > 0) {
        _blendPaint.shader = Gradient.linear(
          Offset(left, 0),
          Offset(left + 16 * 0.06 * ppm, 0),
          const [Color(0x00FFFFFF), Color(0xFFFFFFFF)],
        );
        canvas.drawRect(destination, _blendPaint);
        canvas.restore();
      }
    }

    // The painted plates have dark earth in their lower half. A long, soft
    // veil puts pale fog behind the playable ground and keeps the black child
    // visible wherever the background terrain happens to rise.
    _fogPaint.shader = Gradient.linear(
      Offset(0, size.y * 0.43),
      Offset(0, size.y * 0.79),
      const [Color(0x00DADADA), Color(0xCCDADADA)],
    );
    canvas.drawRect(full, _fogPaint);

    // Broad diffuse backlight follows the camera; it is fog, not a spotlight.
    _fogPaint.shader = Gradient.radial(
      Offset(size.x * 0.43, size.y * 0.57),
      size.x * 0.56,
      const [Color(0x44FFFFFF), Color(0x00FFFFFF)],
    );
    canvas.drawRect(full, _fogPaint);
    _fogPaint.shader = null;
  }
}
