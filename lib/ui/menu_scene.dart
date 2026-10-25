import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/palette.dart';

/// The restrained landscape behind the title screen.
///
/// The painted plate already contains the boy and the depth layers. Motion is
/// intentionally slight: a slow camera breath and two translucent fog bands.
class MenuScene extends StatefulWidget {
  const MenuScene({super.key});

  @override
  State<MenuScene> createState() => _MenuSceneState();
}

class _MenuSceneState extends State<MenuScene>
    with SingleTickerProviderStateMixin {
  late final AnimationController _time = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool still = MediaQuery.disableAnimationsOf(context);
    return ColoredBox(
      color: Palette.brandBlack,
      child: AnimatedBuilder(
        animation: _time,
        builder: (context, _) {
          final double t = still ? .5 : _time.value;
          return Stack(
            fit: StackFit.expand,
            children: [
              Transform.scale(
                scale: 1.008 + t * .006,
                child: Transform.translate(
                  offset: Offset((t - .5) * 4, (t - .5) * -2),
                  child: Image.asset(
                    'assets/images/ui/menu_background_v2.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              if (!still) RepaintBoundary(child: CustomPaint(painter: _Fog(t))),
              Opacity(
                opacity: .035,
                child: Image.asset(
                  'assets/images/grain.png',
                  repeat: ImageRepeat.repeat,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Fog extends CustomPainter {
  const _Fog(this.time);
  final double time;

  @override
  void paint(Canvas canvas, Size size) {
    void band(double y, double height, double shift, double opacity) {
      final Rect rect = Rect.fromLTWH(
        -size.width * .25 + shift,
        y,
        size.width * 1.5,
        height,
      );
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topLeft,
            rect.topRight,
            [
              Colors.transparent,
              const Color(0xFFCDD0D2).withValues(alpha: opacity),
              Colors.transparent,
            ],
            const [0, .5, 1],
          ),
      );
    }

    band(size.height * .47, size.height * .11, (time - .5) * 42, .045);
    band(size.height * .60, size.height * .08, (.5 - time) * 30, .035);
  }

  @override
  bool shouldRepaint(_Fog oldDelegate) => oldDelegate.time != time;
}
