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

class _ChapterCompleteScreenState extends State<ChapterCompleteScreen> {
  int _selection = 0;
  bool _leaving = false;

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
          SafeArea(
            minimum: const EdgeInsets.all(18),
            child: Center(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'CHAPTER COMPLETE',
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
