import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/palette.dart';

/// One short logo reveal before the title screen on each cold start.
class StartupIntro extends StatefulWidget {
  const StartupIntro({super.key});

  @override
  State<StartupIntro> createState() => _StartupIntroState();
}

class _StartupIntroState extends State<StartupIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 5200),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _visible = false);
      }
    });
  late final Animation<double> _logo = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween<double>(begin: 0, end: 1).chain(
        CurveTween(curve: Curves.easeOut),
      ),
      weight: 25,
    ),
    TweenSequenceItem(tween: ConstantTween(1), weight: 42),
    TweenSequenceItem(
      tween: Tween<double>(begin: 1, end: 0).chain(
        CurveTween(curve: Curves.easeIn),
      ),
      weight: 33,
    ),
  ]).animate(_controller);
  late final Animation<double> _fog = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, .88, curve: Curves.easeInOut),
  );
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _skip() => _controller.animateTo(
    1,
    duration: const Duration(milliseconds: 450),
    curve: Curves.easeOut,
  );

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _skip,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => ColoredBox(
          color: Palette.brandBlack,
          child: LayoutBuilder(
            builder: (context, bounds) {
              final shortest = bounds.biggest.shortestSide;
              final fogSize = shortest * 1.1;
              return Stack(
                alignment: Alignment.center,
                children: [
                  _mist(
                    fogSize,
                    Alignment(-.7 + _fog.value * .55, -.25),
                    Palette.fogMid.withValues(alpha: .23 * _fog.value),
                  ),
                  _mist(
                    fogSize * .9,
                    Alignment(.75 - _fog.value * .45, .35),
                    Palette.fogMid.withValues(alpha: .17 * _fog.value),
                  ),
                  Opacity(
                    opacity: _logo.value,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                        sigmaX: (1 - _logo.value) * 16,
                        sigmaY: (1 - _logo.value) * 16,
                      ),
                      child: Image.asset(
                        'assets/brand/wordmark_transparent.png',
                        width: shortest * .42,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _mist(double size, Alignment alignment, Color color) => Align(
    alignment: alignment,
    child: ImageFiltered(
      imageFilter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
      child: Container(
        width: size,
        height: size * .45,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    ),
  );
}
