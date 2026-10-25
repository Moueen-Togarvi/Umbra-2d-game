import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/palette.dart';
import '../game/umbra_game.dart';
import 'menu_word.dart';
import 'settings_panel.dart';

/// The pause screen, over the game blurred and darkened: on the left the
/// menu's words — Resume, Restart checkpoint, Main menu — and on the right
/// the same settings as the main menu. Settings live outside the
/// fixed-step simulation and persist independently.
class PauseScreen extends StatefulWidget {
  const PauseScreen({super.key, required this.game});
  final UmbraGame game;
  @override
  State<PauseScreen> createState() => _PauseScreenState();
}

class _PauseScreenState extends State<PauseScreen> {
  bool _leaving = false;
  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final Size size = MediaQuery.sizeOf(context);
    final double unit = size.shortestSide / 100;
    // Smaller rather than cut off where the column is narrow.
    Widget word(
      String numeral,
      String label,
      VoidCallback? onTap, {
      bool primary = false,
    }) => FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: MenuWord(
        numeral: numeral,
        label: label,
        unit: unit,
        scale: .8,
        alignNumerals: true,
        primary: primary,
        onTap: onTap,
      ),
    );
    final menu = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'PAUSED',
          style: TextStyle(
            fontFamily: 'Cinzel',
            color: Palette.lampAmber,
            fontSize: (unit * 3.6).clamp(18, 30),
            letterSpacing: unit * .9,
          ),
        ),
        SizedBox(height: unit * 1.4),
        Container(
          width: unit * 5,
          height: 1,
          color: Palette.lampAmber.withValues(alpha: .7),
        ),
        SizedBox(height: unit * 2),
        word('I', 'Resume', game.resumeGameplay, primary: true),
        word('II', 'Reset puzzle', game.resetFromPause),
        if (game.campaign)
          word(
            'III',
            'Main menu',
            _leaving
                ? null
                : () async {
                    setState(() => _leaving = true);
                    await game.returnToTitle();
                  },
          ),
        SizedBox(height: unit * 3),
        Text(
          'A / D  move     Space  jump\n'
          'E  hold to grab or pull\n'
          'S / Down  hold to crouch or hide\n'
          'On a rope  W / S to climb',
          style: TextStyle(
            fontFamily: 'Cormorant',
            fontStyle: FontStyle.italic,
            fontSize: (unit * 2.4).clamp(12, 18),
            height: 1.5,
            color: Palette.brandInk.withValues(alpha: .42),
          ),
        ),
      ],
    );
    Widget settings(double width) => Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsPanel(settings: game.settings, unit: unit, width: width),
        SizedBox(height: unit * 1.6),
        _Small('Reset settings', unit, game.settings.reset),
        Padding(
          padding: EdgeInsets.only(right: unit * 1.2),
          child: Text(
            'Saved as you change them.',
            style: TextStyle(
              fontFamily: 'Cormorant',
              fontStyle: FontStyle.italic,
              fontSize: (unit * 2.2).clamp(11, 16),
              color: Palette.brandInk.withValues(alpha: .35),
            ),
          ),
        ),
      ],
    );
    return Focus(
      autofocus: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          game.resumeGameplay();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The game, held still behind, blurred and darkened.
            BackdropFilter(
              filter: ui.ImageFilter.blur(sigmaX: 9, sigmaY: 9),
              child: const ColoredBox(color: Color(0xBF080A0B)),
            ),
            SafeArea(
              minimum: const EdgeInsets.all(18),
              child: LayoutBuilder(
                builder: (context, bounds) {
                  if (bounds.maxWidth < 620) {
                    return SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          menu,
                          SizedBox(height: unit * 5),
                          settings(bounds.maxWidth),
                        ],
                      ),
                    );
                  }
                  final double width = math.min(
                    (unit * 70).clamp(380, 620),
                    bounds.maxWidth * .58,
                  );
                  return Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width * .05,
                      vertical: size.height * .04,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: SingleChildScrollView(child: menu)),
                        SizedBox(width: unit * 4),
                        SingleChildScrollView(child: settings(width)),
                      ],
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

/// A small italic word to press, lit amber under the pointer or focused.
class _Small extends StatelessWidget {
  const _Small(this.label, this.unit, this.onTap);
  final String label;
  final double unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused)
            ? Palette.lampAmber
            : Palette.brandInk.withValues(alpha: .7),
      ),
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
      padding: WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: unit * 1.2),
      ),
      textStyle: WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Cormorant',
          fontStyle: FontStyle.italic,
          fontSize: (unit * 3).clamp(15, 22),
        ),
      ),
    ),
    child: Text(label),
  );
}
