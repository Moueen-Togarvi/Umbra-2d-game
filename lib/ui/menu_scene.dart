import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/palette.dart';
import '../config/game_config.dart';
import '../render/character_silhouette.dart';

/// The restrained landscape behind the title screen.
///
/// The painted plate contains the landscape and distant vampire; the hero is
/// drawn from the gameplay rig at the right edge.
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
                    'assets/images/ui/menu_background_chase.png',
                    fit: BoxFit.cover,
                    alignment: Alignment.center,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(painter: _MenuHero(t), size: Size.infinite),
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

/// The title scene uses the same procedural silhouette rig as gameplay, so
/// the child keeps his in-game proportions and running gait.
class _MenuHero extends CustomPainter {
  _MenuHero(this.time)
    : _boy = CharacterSilhouette(height: GameConfig.playerHeight);

  final double time;
  final CharacterSilhouette _boy;

  @override
  void paint(Canvas canvas, Size size) {
    final double scale = size.height * .155 / GameConfig.playerHeight;
    canvas.save();
    canvas.translate(size.width * .965, size.height * .752);
    canvas.scale(scale);
    canvas.translate(0, -.5);
    _boy.draw(
      canvas,
      CharacterPose(
        facing: -1,
        gait: .94,
        gaitPhase: time * math.pi * 2,
        bodyLean: .10,
        clock: time * 24,
      ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MenuHero oldDelegate) =>
      oldDelegate.time != time;
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
