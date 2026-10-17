import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/palette.dart';
import '../game/umbra_game.dart';

/// Settings live outside the fixed-step simulation and persist independently.
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
        color: const Color(0xCC080A0B),
        child: SafeArea(
          minimum: const EdgeInsets.all(18),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 920),
              child: ListenableBuilder(
                listenable: game.settings,
                builder: (context, _) => LayoutBuilder(
                  builder: (context, bounds) {
                    final wide = bounds.maxWidth >= 620;
                    final menu = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'PAUSED',
                          style: TextStyle(
                            fontFamily: 'Cinzel',
                            color: Palette.brandInk,
                            fontSize: 25,
                            letterSpacing: 5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        const Text(
                          'A / D  Move    Space  Jump\nE  Hold to grab / pull\nOn a rope: W / S to climb',
                          style: TextStyle(
                            color: Color(0xFFB4B5B2),
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _action('RESUME', game.resumeGameplay, primary: true),
                        _action('RESTART CHECKPOINT', game.resetFromPause),
                        if (game.campaign)
                          _action(
                            'MAIN MENU',
                            _leaving
                                ? null
                                : () async {
                                    setState(() => _leaving = true);
                                    await game.returnToTitle();
                                  },
                          ),
                      ],
                    );
                    final settings = Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SETTINGS',
                          style: TextStyle(
                            color: Palette.brandInk,
                            fontSize: 11,
                            letterSpacing: 2,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _slider(
                          'Brightness',
                          'brightness',
                          game.settings.brightness,
                          .8,
                          1.3,
                        ),
                        _slider(
                          'Film effects',
                          'atmosphere',
                          game.settings.atmosphere,
                          0,
                          1,
                        ),
                        _slider(
                          'Ambience',
                          'ambience',
                          game.settings.ambience,
                          0,
                          1,
                        ),
                        _slider(
                          'Effects',
                          'effects',
                          game.settings.effects,
                          0,
                          1,
                        ),
                        const SizedBox(height: 8),
                        _slider(
                          'Button size',
                          'controlsScale',
                          game.settings.controlsScale,
                          .8,
                          1.3,
                        ),
                        _slider(
                          'Button opacity',
                          'controlsOpacity',
                          game.settings.controlsOpacity,
                          .3,
                          1,
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Settings are saved automatically.',
                          style: TextStyle(
                            color: Color(0xFF959996),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    );
                    return SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(flex: 4, child: menu),
                                  Container(
                                    width: 1,
                                    height: 245,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 28,
                                    ),
                                    color: const Color(0x33C1C4BE),
                                  ),
                                  Expanded(flex: 6, child: settings),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  menu,
                                  const SizedBox(height: 24),
                                  settings,
                                ],
                              ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _action(String label, VoidCallback? action, {bool primary = false}) =>
      TextButton(
        onPressed: action,
        style: TextButton.styleFrom(
          foregroundColor: primary ? Palette.lampAmber : Palette.brandInk,
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
          minimumSize: const Size(190, 40),
          alignment: Alignment.centerLeft,
          textStyle: const TextStyle(
            fontFamily: 'Roboto',
            fontSize: 12,
            letterSpacing: 1.4,
          ),
        ),
        child: Text(label),
      );

  Widget _slider(
    String label,
    String key,
    double value,
    double min,
    double max,
  ) => SizedBox(
    height: 34,
    child: Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: Palette.brandInk, fontSize: 12),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: Palette.brandInk.withValues(alpha: .75),
              inactiveTrackColor: const Color(0xFF363B3D),
              thumbColor: Palette.lampAmber,
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 13),
            ),
            child: Slider(
              key: ValueKey(key),
              value: value,
              min: min,
              max: max,
              semanticFormatterCallback: (v) =>
                  '$label ${(v * 100).round()} percent',
              onChanged: (v) => widget.game.settings.set(key, v),
            ),
          ),
        ),
        SizedBox(
          width: 32,
          child: Text(
            '${(value * 100).round()}',
            textAlign: TextAlign.right,
            style: const TextStyle(color: Color(0xFFB4B5B2), fontSize: 11),
          ),
        ),
      ],
    ),
  );
}
