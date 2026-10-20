import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'chapter_backgrounds.dart';
import 'mood.dart';
import 'scenery.dart';

/// Painted backgrounds behind the real physics world. One atlas is owned by
/// the active chapter; at most two panels are drawn during a transition.
/// These are paintings with camera panning, not fake collision geometry.
class ChapterBackdrop extends Component {
  ChapterBackdrop({
    required this.camera,
    required this.plan,
    required this.stageWidth,
    this.groundFor,
    required this.moods,
    required this.props,
  });

  final CameraComponent camera;
  final ChapterBackground plan;
  final double stageWidth;
  final double Function(double)? groundFor;
  final MoodTrack moods;
  final List<BackdropDrawable> Function() props;
  Image? _atlas;
  double? _ground;
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;
  final Paint _fill = Paint()..color = const Color(0xFF414141);
  final List<Rect> _panels = [];

  bool get hasArtwork => _atlas != null;

  @override
  Future<void> onLoad() async {
    final data = await rootBundle.load(plan.asset);
    final codec = await instantiateImageCodec(data.buffer.asUint8List());
    try {
      _atlas = (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
    final width = _atlas!.width / 2;
    final height = _atlas!.height / 2;
    // Two pixels of inset avoid sampling the atlas divisions at any zoom.
    for (var i = 0; i < 4; i++) {
      _panels.add(
        Rect.fromLTWH(
          (i % 2) * width,
          (i ~/ 2) * height,
          width,
          height,
        ).deflate(2),
      );
    }
  }

  @override
  void update(double dt) {
    final target = groundFor?.call(camera.viewfinder.position.x) ?? 7;
    _ground = _ground == null
        ? target
        : _ground! + (target - _ground!) * (1 - math.exp(-dt * 1.2));
  }

  @override
  void render(Canvas canvas) {
    final size = camera.viewport.size;
    final image = _atlas;
    if (size.x <= 0 || size.y <= 0 || image == null) return;
    final viewport = Rect.fromLTWH(0, 0, size.x, size.y);
    final blend = plan.blendAt(camera.viewfinder.position.x);
    canvas.save();
    canvas.clipRect(viewport);
    canvas.drawRect(viewport, _fill);
    _drawPanel(canvas, image, blend.from, 1);
    if (blend.to != blend.from) _drawPanel(canvas, image, blend.to, blend.mix);
    // Story actors at distant depths remain live. Replaced decorative
    // SceneryProps never register here, so painted geometry is not doubled.
    final cam = camera.viewfinder.position;
    final view = camera.visibleWorldRect;
    canvas.save();
    canvas.scale(size.x / view.width, size.y / view.height);
    canvas.translate(-view.left, -view.top);
    for (final prop in props()) {
      prop.paint(canvas, cam, moods.at(cam.x));
    }
    canvas.restore();
    canvas.restore();
  }

  void _drawPanel(Canvas canvas, Image image, int index, double opacity) {
    final source = _panels[index];
    final size = camera.viewport.size;
    final view = camera.visibleWorldRect;
    final camX = camera.viewfinder.position.x;
    final ppm = size.y / view.height;
    final ground = ((_ground ?? 7) - view.top) * ppm;
    // Overscan gives a gentle pan, without stretching, tiling or exposing
    // neighbouring atlas panels on wide screens or during a camera rise.
    final scale = math.max(
      size.x * 1.14 / source.width,
      size.y * 1.14 / source.height,
    );
    final width = source.width * scale;
    final height = source.height * scale;
    final start = plan.areas[index].start;
    final end = index + 1 < plan.areas.length
        ? plan.areas[index + 1].start
        : stageWidth;
    final progress = ((camX - start) / math.max(1, end - start)).clamp(
      0.0,
      1.0,
    );
    final x = -(width - size.x) * (.15 + .7 * progress);
    final y = (ground - height * .82).clamp(size.y - height, 0.0);
    _paint.color = Color.fromRGBO(255, 255, 255, opacity);
    canvas.drawImageRect(
      image,
      source,
      Rect.fromLTWH(x, y, width, height),
      _paint,
    );
  }

  @override
  void onRemove() {
    _atlas?.dispose();
    _atlas = null;
    super.onRemove();
  }
}
