import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

enum WhiteBlossomTreeKind { windSwept, weeping }

/// A surface-rooted blossom tree with a small, deterministic fall of petals.
/// Pure scenery: it has no collision body and never changes gameplay physics.
class WhiteBlossomTree extends PositionComponent {
  WhiteBlossomTree({
    required this.kind,
    required Vector2 at,
    required double height,
    required int seed,
    this.flip = false,
  }) : _height = height,
       _petals = _makePetals(seed),
       super(
         position: at,
         size: Vector2(height * kind.fallbackAspect, height),
         anchor: Anchor.bottomCenter,
         priority: -34,
       );

  final WhiteBlossomTreeKind kind;
  final double _height;
  final bool flip;
  final List<_Petal> _petals;
  ui.Image? _image;
  double _time = 0;

  final ui.Paint _imagePaint = ui.Paint()..filterQuality = ui.FilterQuality.low;
  final ui.Paint _petalPaint = ui.Paint();
  final ui.Path _petal = ui.Path()
    ..moveTo(-.026, 0)
    ..quadraticBezierTo(-.008, -.019, .027, .002)
    ..quadraticBezierTo(.007, .017, -.026, 0)
    ..close();

  @override
  Future<void> onLoad() async {
    try {
      _image = await Flame.images.load(kind.asset);
      size = Vector2(_height * _image!.width / _image!.height, _height);
    } catch (_) {
      // Bare unit tests do not always install an asset bundle.
    }
  }

  @override
  void update(double dt) {
    _time += dt;
  }

  @override
  void render(ui.Canvas canvas) {
    final image = _image;
    if (image != null) {
      final source = ui.Rect.fromLTWH(
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
      );
      final target = ui.Rect.fromLTWH(0, 0, size.x, size.y);
      if (flip) {
        canvas.save();
        canvas.translate(size.x, 0);
        canvas.scale(-1, 1);
        canvas.drawImageRect(image, source, target, _imagePaint);
        canvas.restore();
      } else {
        canvas.drawImageRect(image, source, target, _imagePaint);
      }
    }

    for (final petal in _petals) {
      final age = (_time + petal.delay) % petal.life;
      final progress = age / petal.life;
      final emitter = kind.emitters[petal.emitter];
      final startX = flip ? 1 - emitter.$1 : emitter.$1;
      final x =
          startX * size.x +
          petal.drift * progress +
          math.sin(age * petal.sway + petal.phase) * .17;
      final y =
          emitter.$2 * size.y +
          (size.y - emitter.$2 * size.y) *
              (.22 * progress + .78 * progress * progress);
      final opacity =
          (age / .28).clamp(0.0, 1.0) *
          ((1 - progress) / .13).clamp(0.0, 1.0) *
          petal.opacity;
      _petalPaint.color = ui.Color.fromRGBO(242, 242, 236, opacity);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(age * petal.spin + petal.phase);
      canvas.scale(
        petal.scale,
        petal.scale * (.45 + .55 * math.cos(age * 2.1 + petal.phase).abs()),
      );
      canvas.drawPath(_petal, _petalPaint);
      canvas.restore();
    }
  }

  static List<_Petal> _makePetals(int seed) {
    final random = math.Random(seed);
    return List.generate(18, (index) {
      return _Petal(
        emitter: index % 12,
        delay: random.nextDouble() * 8,
        life: 6.5 + random.nextDouble() * 3.5,
        phase: random.nextDouble() * math.pi * 2,
        sway: .8 + random.nextDouble() * .7,
        drift: -.3 + random.nextDouble() * .75,
        spin: .55 + random.nextDouble() * .85,
        scale: .72 + random.nextDouble() * .55,
        opacity: .58 + random.nextDouble() * .32,
      );
    });
  }
}

extension on WhiteBlossomTreeKind {
  String get asset => switch (this) {
    WhiteBlossomTreeKind.windSwept =>
      'white_trees/white_tree_02_wind_swept.webp',
    WhiteBlossomTreeKind.weeping =>
      'white_trees/white_tree_03_weeping_white.webp',
  };

  double get fallbackAspect => switch (this) {
    WhiteBlossomTreeKind.windSwept => 1.5,
    WhiteBlossomTreeKind.weeping => .94,
  };

  List<(double, double)> get emitters => switch (this) {
    WhiteBlossomTreeKind.windSwept => const [
      (.15, .34),
      (.23, .26),
      (.32, .18),
      (.41, .31),
      (.51, .12),
      (.61, .25),
      (.71, .16),
      (.81, .27),
      (.90, .39),
      (.67, .43),
      (.79, .48),
      (.35, .43),
    ],
    WhiteBlossomTreeKind.weeping => const [
      (.14, .31),
      (.25, .20),
      (.38, .12),
      (.51, .18),
      (.64, .20),
      (.76, .29),
      (.86, .40),
      (.25, .43),
      (.43, .35),
      (.58, .41),
      (.71, .52),
      (.17, .56),
    ],
  };
}

class _Petal {
  const _Petal({
    required this.emitter,
    required this.delay,
    required this.life,
    required this.phase,
    required this.sway,
    required this.drift,
    required this.spin,
    required this.scale,
    required this.opacity,
  });

  final int emitter;
  final double delay, life, phase, sway, drift, spin, scale, opacity;
}
