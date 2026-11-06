import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../chapters/chapters.dart';
import '../config/palette.dart';
import '../game/umbra_game.dart';
import 'main_menu_choice.dart';

/// A quiet pause between chapters, using the same type and brush mark as the
/// title and pause menus.
class ChapterCompleteScreen extends StatefulWidget {
  const ChapterCompleteScreen({super.key, required this.game});

  final UmbraGame game;

  @override
  State<ChapterCompleteScreen> createState() => _ChapterCompleteScreenState();
}

class _ChapterCompleteScreenState extends State<ChapterCompleteScreen>
    with SingleTickerProviderStateMixin {
  int _selection = 0;
  bool _leaving = false;
  late final AnimationController _confetti = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2300),
  )..forward();

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final director = widget.game.director!;
    final chapter = Chapters.all[director.index];
    final hasNext = director.index + 1 < Chapters.all.length;
    final size = MediaQuery.sizeOf(context);
    final unit = size.shortestSide / 100;
    final actions = <(String, VoidCallback)>[
      (hasNext ? 'Next chapter' : 'View ending', director.nextChapter),
      ('Restart', director.restartChapter),
      (
        'Main menu',
        () {
          if (_leaving) return;
          setState(() => _leaving = true);
          director.completedToTitle();
        },
      ),
    ];

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: const ColoredBox(color: Color(0xBF080A0B)),
          ),
          if (!MediaQuery.disableAnimationsOf(context))
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _confetti,
                  builder: (context, _) =>
                      CustomPaint(painter: _ConfettiPainter(_confetti.value)),
                ),
              ),
            ),
          SafeArea(
            minimum: const EdgeInsets.all(18),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CHAPTER ${(director.index + 1).toString().padLeft(2, '0')} COMPLETE',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: (unit * 4).clamp(20, 34),
                        letterSpacing: (unit * .9).clamp(3, 8),
                        color: Palette.brandInk,
                      ),
                    ),
                    SizedBox(height: unit * 1.7),
                    Container(
                      width: unit * 6,
                      height: 1,
                      color: Palette.lampAmber.withValues(alpha: .75),
                    ),
                    SizedBox(height: unit * 2),
                    Text(
                      chapter.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: (unit * 2.6).clamp(15, 23),
                        color: Palette.brandInk.withValues(alpha: .72),
                      ),
                    ),
                    SizedBox(height: unit * 3),
                    for (final (i, action) in actions.indexed)
                      MainMenuChoice(
                        label: action.$1,
                        unit: unit,
                        selected: i == _selection,
                        amberSelected: true,
                        autofocus: i == 0,
                        centered: true,
                        onHighlight: () {
                          if (_selection != i) setState(() => _selection = i);
                        },
                        onTap: _leaving ? null : action.$2,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One short shower of fog-white and lamp-amber paper flecks.
class _ConfettiPainter extends CustomPainter {
  const _ConfettiPainter(this.progress);

  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final t = Curves.easeOutCubic.transform(progress);
    final opacity = (1 - progress * progress).clamp(0.0, 1.0);
    for (var i = 0; i < 36; i++) {
      final a = ((i * 73) % 101) / 101.0;
      final b = ((i * 47 + 19) % 97) / 97.0;
      final x =
          size.width * (.14 + .72 * a) + math.sin(progress * 5 + i * 1.7) * 12;
      final y = size.height * (.04 + .15 * b + .53 * t);
      final paint = Paint()
        ..color = (i % 4 == 0 ? Palette.lampAmber : Palette.brandInk)
            .withValues(alpha: opacity * (i % 4 == 0 ? .78 : .52));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(progress * (i.isEven ? 3 : -3) + a * math.pi);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: 3, height: 6),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ConfettiPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
