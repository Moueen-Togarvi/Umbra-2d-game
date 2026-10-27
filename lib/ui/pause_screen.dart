import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/palette.dart';
import '../game/umbra_game.dart';
import 'main_menu_choice.dart';
import 'settings_panel.dart';

/// Pause menu styled to match the quiet, brush-highlighted title menu.
class PauseScreen extends StatefulWidget {
  const PauseScreen({super.key, required this.game});
  final UmbraGame game;

  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  bool _leaving = false;
  bool _showSettings = false;
  int _selection = 0;

  void _back() {
    if (_showSettings) {
      setState(() => _showSettings = false);
    } else {
      widget.game.resumeGameplay();
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final size = MediaQuery.sizeOf(context);
    final unit = size.shortestSide / 100;

    final actions = <(String, VoidCallback?)>[
      ('Resume', game.resumeGameplay),
      ('Settings', () => setState(() => _showSettings = true)),
      ('Reset puzzle', game.resetFromPause),
      if (game.campaign)
        (
          'Main menu',
          _leaving
              ? null
              : () async {
                  setState(() => _leaving = true);
                  await game.returnToTitle();
                },
        ),
    ];

    Widget title(String text) => Text(
      text,
      style: TextStyle(
        fontFamily: 'Cinzel',
        fontSize: (unit * 8.2).clamp(38, 72),
        fontWeight: FontWeight.w400,
        letterSpacing: (unit * 2).clamp(8, 17),
        color: const Color(0xFFE1E0DE),
        shadows: const [Shadow(color: Color(0x99000000), blurRadius: 12)],
      ),
    );

    Widget choices() => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, action) in actions.indexed)
          MainMenuChoice(
            label: action.$1,
            unit: unit,
            selected: i == _selection,
            autofocus: i == 0,
            onHighlight: () {
              if (_selection != i) setState(() => _selection = i);
            },
            onTap: action.$2,
          ),
      ],
    );

    Widget settings(double width) => Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'SETTINGS',
          style: TextStyle(
            fontFamily: 'Cinzel',
            fontSize: (unit * 4).clamp(16, 28),
            letterSpacing: unit * .8,
            color: Palette.brandInk,
          ),
        ),
        SizedBox(height: unit * 1.4),
        Container(
          width: unit * 5,
          height: 1,
          color: Palette.lampAmber.withValues(alpha: .7),
        ),
        SizedBox(height: unit * 2),
        SettingsPanel(
          settings: game.settings,
          unit: unit,
          width: width,
          centered: true,
        ),
        SizedBox(height: unit * 1.4),
        SizedBox(
          width: width,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.translate(
                offset: Offset(unit * 4, 0),
                child: MainMenuChoice(
                  label: 'Reset settings',
                  unit: unit * .72,
                  selected: false,
                  autofocus: false,
                  onHighlight: () {},
                  onTap: game.settings.reset,
                  centered: true,
                ),
              ),
              SizedBox(width: unit * 5.5),
              MainMenuChoice(
                label: 'Back',
                unit: unit * .72,
                selected: true,
                autofocus: false,
                onHighlight: () {},
                onTap: () => setState(() => _showSettings = false),
                centered: true,
              ),
            ],
          ),
        ),
      ],
    );

    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _back();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: const ColoredBox(color: Color(0xA6080A0B)),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(18),
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final compact = bounds.maxWidth < 620;
                  final content = AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    child: _showSettings
                        ? KeyedSubtree(
                            key: const ValueKey('settings'),
                            child: settings(
                              compact
                                  ? bounds.maxWidth * .92
                                  : (unit * 64)
                                        .clamp(400, bounds.maxWidth * .9)
                                        .toDouble(),
                            ),
                          )
                        : KeyedSubtree(
                            key: const ValueKey('pause-menu'),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                title('UMBRA'),
                                SizedBox(height: unit * 1.2),
                                Text(
                                  'PAUSED',
                                  style: TextStyle(
                                    fontFamily: 'Cinzel',
                                    fontSize: (unit * 2).clamp(12, 18),
                                    letterSpacing: unit * .8,
                                    color: Palette.brandInk.withValues(
                                      alpha: .72,
                                    ),
                                  ),
                                ),
                                SizedBox(height: unit * 3),
                                choices(),
                              ],
                            ),
                          ),
                  );
                  return Align(
                    alignment: _showSettings
                        ? Alignment.center
                        : compact
                        ? const Alignment(-.9, -.1)
                        : const Alignment(-.82, 0),
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: _showSettings
                              ? bounds.maxWidth
                              : compact
                              ? bounds.maxWidth
                              : bounds.maxWidth * .62,
                        ),
                        child: content,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
