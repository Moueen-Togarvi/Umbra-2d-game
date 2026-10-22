import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/palette.dart';

/// The picture behind the main menu: the old white tree on its hill in the
/// fog, a lantern hung in it, petals coming down, and the boy beneath it.
///
/// Drawn in a 1600 x 720 frame scaled to cover the screen, so it keeps its
/// composition on any phone; the right of it stays quiet for the words.
/// Everything in it is still except the petals and the lantern's flame.
class MenuScene extends StatefulWidget {
  const MenuScene({super.key});

  static const Size frame = Size(1600, 720);

  @override
  State<MenuScene> createState() => _MenuSceneState();
}

class _MenuSceneState extends State<MenuScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 60),
  )..repeat();

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Palette.brandBlack,
    child: Stack(
      fit: StackFit.expand,
      children: [
        ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            // On a squarer screen the right is what is cut: the tree stays.
            alignment: Alignment.centerLeft,
            child: SizedBox.fromSize(
              size: MenuScene.frame,
              child: Stack(
                children: [
                  const Positioned.fill(child: CustomPaint(painter: _Land())),
                  // Graves far off, nearly lost in the fog.
                  Positioned(
                    left: 930,
                    top: 462,
                    height: 90,
                    child: Opacity(
                      opacity: .28,
                      child: Image.asset('assets/images/part1/ch2_graves.png'),
                    ),
                  ),
                  const Positioned.fill(child: CustomPaint(painter: _Ground())),
                  Positioned(
                    left: 40,
                    top: 50,
                    height: 520,
                    child: ColorFiltered(
                      colorFilter: const ColorFilter.matrix([
                        .92, 0, 0, 0, 0, //
                        0, .92, 0, 0, 0, //
                        0, 0, .92, 0, 0, //
                        0, 0, 0, 1, 0, //
                      ]),
                      child: Image.asset(
                        'assets/images/white_trees/'
                        'white_tree_05_ancient_blossom.webp',
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                  // The boy under it, his shadow on the crest.
                  Positioned(
                    left: 466,
                    top: 469,
                    height: 74,
                    child: Image.asset(
                      'assets/images/ui/menu_boy.png',
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(painter: _Living(_time)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        // On the screen itself, not the picture: the dark the words sit in
        // stays on the right however much of the picture a screen shows.
        const CustomPaint(painter: _Shade()),
        Opacity(
          opacity: .05,
          child: Image.asset(
            'assets/images/grain.png',
            repeat: ImageRepeat.repeat,
          ),
        ),
      ],
    ),
  );
}

/// An elliptical radial gradient: [rx] by [ry] about [centre].
ui.Gradient _ellipse(
  Offset centre,
  double rx,
  double ry,
  List<Color> colors,
  List<double> stops,
) {
  final m = Matrix4.identity()
    ..translateByDouble(centre.dx, centre.dy, 0, 1)
    ..scaleByDouble(rx / ry, 1, 1, 1)
    ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
  return ui.Gradient.radial(
    centre,
    ry,
    colors,
    stops,
    TileMode.clamp,
    m.storage,
  );
}

/// The fog-lit sky, the far hill and the band of mist along it.
class _Land extends CustomPainter {
  const _Land();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = _ellipse(
          const Offset(512, 331),
          880,
          432,
          const [
            Color(0xFF8F8D89),
            Color(0xFF5E5C59),
            Color(0xFF2B2A29),
            Color(0xFF0D0D0D),
          ],
          const [0, .30, .62, 1],
        ),
    );
    final far = Path()
      ..moveTo(0, 520)
      ..cubicTo(300, 470, 700, 500, 1000, 470)
      ..cubicTo(1300, 440, 1400, 480, 1600, 470)
      ..lineTo(1600, 720)
      ..lineTo(0, 720)
      ..close();
    canvas.drawPath(far, Paint()..color = const Color(0x47000000));
    canvas.drawRect(
      const Rect.fromLTWH(-160, 470, 1920, 140),
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 470),
          const Offset(0, 610),
          const [Color(0x00C8C6C0), Color(0x47C8C6C0), Color(0x00C8C6C0)],
          const [0, .5, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The hill he stands on: a shade lighter than black, lit a little where
/// the tree is, with the fog catching its crest.
class _Ground extends CustomPainter {
  const _Ground();

  static Path crest() => Path()
    ..moveTo(0, 610)
    ..cubicTo(120, 560, 300, 530, 480, 540)
    ..cubicTo(660, 550, 760, 590, 900, 610)
    ..cubicTo(1040, 630, 1300, 625, 1600, 620);

  @override
  void paint(Canvas canvas, Size size) {
    final hill = crest()
      ..lineTo(1600, 720)
      ..lineTo(0, 720)
      ..close();
    canvas.drawPath(
      hill,
      Paint()
        ..shader = ui.Gradient.linear(
          const Offset(0, 530),
          const Offset(0, 720),
          const [Color(0xFF1F1E1C), Color(0xFF161615), Color(0xFF0D0D0D)],
          const [0, .4, 1],
        ),
    );
    canvas.drawPath(
      hill,
      Paint()
        ..shader = _ellipse(
          const Offset(480, 540),
          560,
          66,
          const [Color(0x734A4844), Color(0x004A4844)],
          const [0, 1],
        ),
    );
    canvas.drawPath(
      crest(),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0x618F8B83)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.2),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// What moves: petals drifting down through the fog, and the lantern's
/// flame breathing a little.
class _Living extends CustomPainter {
  _Living(this.time) : super(repaint: time);
  final Animation<double> time;

  static final List<_Petal> _petals = () {
    final r = math.Random(3);
    return [
      for (var i = 0; i < 36; i++)
        _Petal(
          x: 120 + r.nextDouble() * 780,
          phase: r.nextDouble(),
          size: 2 + r.nextInt(3).toDouble(),
          opacity: .35 + r.nextDouble() * .55,
          speed: .7 + r.nextDouble() * .6,
          sway: r.nextDouble() * math.pi * 2,
        ),
    ];
  }();

  static const Offset _lamp = Offset(536, 362);

  @override
  void paint(Canvas canvas, Size size) {
    final double t = time.value * 60; // seconds
    final petal = Paint();
    for (final p in _petals) {
      // From the canopy down to the hill, about twenty seconds a fall.
      final double fall = (p.phase + t * p.speed / 20) % 1;
      final double y = 220 + fall * 380;
      final double x = p.x + fall * 70 + math.sin(t * .6 + p.sway) * 9;
      final double fade = math.min(1, math.min(fall * 6, (1 - fall) * 6));
      petal.color = Color.fromRGBO(244, 241, 234, p.opacity * fade);
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * .4 + p.sway);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: p.size,
          height: p.size * .7,
        ),
        petal,
      );
      canvas.restore();
    }

    // The lantern: its string, its glass, and the warm air around it.
    canvas.drawLine(
      const Offset(536, 322),
      const Offset(536, 356),
      Paint()
        ..color = const Color(0xFF000000)
        ..strokeWidth = 1,
    );
    final double breath =
        .9 + .06 * math.sin(t * 1.7) + .04 * math.sin(t * 4.3 + 1);
    for (final (radius, alpha, blur) in const [
      (60.0, .12, 50.0),
      (22.0, .35, 16.0),
      (8.0, .9, 4.0),
    ]) {
      canvas.drawCircle(
        _lamp,
        radius,
        Paint()
          ..color = Palette.lampAmber.withValues(alpha: alpha * breath)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: _lamp, width: 10, height: 14),
        const Radius.circular(3),
      ),
      Paint()..color = const Color(0xFFFFD58A),
    );
  }

  @override
  bool shouldRepaint(covariant _Living oldDelegate) => false;
}

class _Petal {
  const _Petal({
    required this.x,
    required this.phase,
    required this.size,
    required this.opacity,
    required this.speed,
    required this.sway,
  });
  final double x, phase, size, opacity, speed, sway;
}

/// The dark the words sit in on the right, and the edges closing in.
class _Shade extends CustomPainter {
  const _Shade();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(size.width, 0),
          const [Color(0x000B0B0B), Color(0x8C0B0B0B), Color(0xDB0B0B0B)],
          const [.46, .68, 1],
        ),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..shader = _ellipse(
          Offset(size.width * .4, size.height * .5),
          size.width * .85,
          size.height * .95,
          const [Color(0x00050505), Color(0x00050505), Color(0xBF050505)],
          const [0, .55, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
