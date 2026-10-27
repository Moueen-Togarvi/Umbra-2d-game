import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chapters/chapters.dart';
import '../chapters/campaign_catalog.dart';
import '../config/palette.dart';
import '../game/umbra_game.dart';
import 'menu_scene.dart';
import 'main_menu_choice.dart';
import 'menu_word.dart';
import 'settings_panel.dart';
import 'wordmark.dart';

/// The main menu: a quiet field with the boy at its centre (see [MenuScene])
/// and a compact wordmark and menu at the left. The selected word rests on a
/// pale brush mark. The picture comes up first, then the words; leaving, it
/// all fades into the game. Beginning again over a saved place asks first.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key, required this.game});
  final UmbraGame game;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3300),
  );
  late final AnimationController _leave = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  _Page _page = _Page.main;
  SettingsTab _tab = SettingsTab.display;
  bool _leaving = false;
  int _mainSelection = 0;

  @override
  void initState() {
    super.initState();
    // The words come up after the picture has.
    _fade.forward();
    // The menu covers the screen: the world behind it is not drawn.
    widget.game.coveredByMenu = true;
    widget.game.titleBack = _back;
  }

  @override
  void dispose() {
    widget.game
      ..previewBackground = null
      ..coveredByMenu = false;
    if (widget.game.titleBack == _back) widget.game.titleBack = null;
    _fade.dispose();
    _leave.dispose();
    super.dispose();
  }

  void _open(_Page page) => setState(() {
    _page = page;
    widget.game.previewBackground = null;
  });

  void _settings(SettingsTab tab) {
    _tab = tab;
    _open(_Page.settings);
  }

  /// Android's back: out of a panel to the menu, and from the menu out of
  /// the game.
  void _back() {
    if (_leaving) return;
    if (_page != _Page.main) {
      _open(_Page.main);
    } else {
      SystemNavigator.pop();
    }
  }

  Future<void> _go(void Function() action) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    // The world shows through again as the menu fades.
    widget.game.coveredByMenu = false;
    await _leave.forward();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final director = widget.game.director;
    final progress = widget.game.progress;
    final int reached = progress.reached;
    final Size size = MediaQuery.sizeOf(context);
    final double unit = size.shortestSide / 100;
    Widget chapterChoice(int i) => _Choice(
      label: '${CampaignCatalog.roman(i + 1)}   ${Chapters.all[i].title}',
      size: unit,
      small: true,
      status: i > reached
          ? 'Locked'
          : i == progress.current
          ? 'Current'
          : 'Replay',
      enabled: i <= reached,
      onTap: director == null || i > reached
          ? null
          : () =>
                _go(() => i == 0 ? director.begin() : director.playChapter(i)),
    );
    final choices = <(String, VoidCallback?)>[
      if (progress.canContinue)
        (
          'Continue',
          director == null
              ? null
              : () => _go(
                  () => director.playChapter(progress.current, resume: true),
                ),
        ),
      (
        'Begin',
        director == null
            ? null
            : progress.canContinue
            // Beginning again moves the saved place back to the start.
            ? () => _open(_Page.confirmBegin)
            : () => _go(director.begin),
      ),
      ('Chapters', () => _open(_Page.chapters)),
      ('Settings', () => _settings(SettingsTab.display)),
    ];
    Widget mainMenu() => Positioned(
      left: size.width * .055,
      top: size.height * .19,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: size.width * .40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'UMBRA',
              semanticsLabel: 'Umbra',
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: (unit * 8.2).clamp(38, 72),
                fontWeight: FontWeight.w400,
                letterSpacing: (unit * 2).clamp(8, 17),
                color: const Color(0xFFE1E0DE),
                shadows: const [
                  Shadow(color: Color(0x66000000), blurRadius: 16),
                ],
              ),
            ),
            SizedBox(height: (unit * 5.4).clamp(22, 48)),
            for (final (i, (label, onTap)) in choices.indexed)
              MainMenuChoice(
                label: label,
                unit: unit,
                selected: i == _mainSelection,
                autofocus: i == 0,
                onHighlight: () {
                  if (_mainSelection != i) {
                    setState(() => _mainSelection = i);
                  }
                },
                onTap: onTap,
              ),
          ],
        ),
      ),
    );
    Widget words(List<Widget> children) => Positioned(
      right: size.width * 0.069,
      top: size.height * 0.11,
      bottom: size.height * 0.04,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Wordmark(height: unit * 9.8, eyes: Palette.lampAmber),
            SizedBox(height: unit * 7),
            ...children,
          ],
        ),
      ),
    );
    final back = _Choice(
      label: 'Back',
      size: unit,
      small: true,
      onTap: () => _open(_Page.main),
    );
    Widget panel(String title, List<Widget> children, {double? width}) => Align(
      alignment: const Alignment(0.95, 0),
      child: Container(
        width: width ?? size.width * 0.51,
        height: size.height * 0.88,
        padding: EdgeInsets.symmetric(horizontal: unit * 1.5),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'Cinzel',
                  fontSize: (unit * 4).clamp(16, 28),
                  letterSpacing: unit * 0.8,
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
              ...children,
            ],
          ),
        ),
      ),
    );
    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: _leave,
        builder: (context, child) =>
            Opacity(opacity: 1 - _leave.value, child: child),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Black first, so the game behind never shows through as the
            // picture comes up.
            const ColoredBox(color: Palette.brandBlack),
            FadeTransition(
              opacity: CurvedAnimation(
                parent: _fade,
                curve: const Interval(0, 0.35, curve: Curves.easeOut),
              ),
              child: const MenuScene(),
            ),
            FadeTransition(
              opacity: CurvedAnimation(
                parent: _fade,
                curve: const Interval(0.3, 1, curve: Curves.easeInOut),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_page == _Page.main) mainMenu(),
                  if (_page == _Page.confirmBegin)
                    words([
                      Text(
                        'Begin again?',
                        style: TextStyle(
                          fontFamily: 'Cormorant',
                          fontStyle: FontStyle.italic,
                          fontSize: unit * 6.1,
                          color: Palette.brandInk,
                        ),
                      ),
                      SizedBox(height: unit * 1.2),
                      SizedBox(
                        width: unit * 52,
                        child: Text(
                          'Your place in chapter '
                          '${CampaignCatalog.roman(progress.current + 1)}, '
                          '${Chapters.all[progress.current].title}, is set '
                          'back to the start. Every chapter you have reached '
                          'stays open.',
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontFamily: 'Cormorant',
                            fontStyle: FontStyle.italic,
                            fontSize: unit * 3.3,
                            height: 1.35,
                            color: Palette.brandInk.withValues(alpha: .6),
                          ),
                        ),
                      ),
                      SizedBox(height: unit * 3),
                      MenuWord(
                        numeral: 'I',
                        label: 'Begin again',
                        unit: unit,
                        primary: true,
                        onTap: director == null
                            ? null
                            : () => _go(director.begin),
                      ),
                      MenuWord(
                        numeral: 'II',
                        label: 'Back',
                        unit: unit,
                        onTap: () => _open(_Page.main),
                      ),
                    ]),
                  if (_page == _Page.chapters)
                    panel('CHAPTERS', [
                      for (var group = 0; group < 8; group++) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 12, bottom: 4),
                          child: Text(
                            '${group * 5 + 1}–${group * 5 + 5}',
                            style: const TextStyle(
                              fontFamily: 'Cinzel',
                              letterSpacing: 2,
                              color: Palette.lampAmber,
                            ),
                          ),
                        ),
                        for (var i = group * 5; i < group * 5 + 5; i++)
                          chapterChoice(i),
                      ],
                      back,
                    ]),
                  if (_page == _Page.settings)
                    Positioned(
                      right: size.width * 0.069,
                      top: size.height * 0.08,
                      bottom: size.height * 0.03,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'SETTINGS',
                              style: TextStyle(
                                fontFamily: 'Cinzel',
                                fontSize: (unit * 4).clamp(16, 28),
                                letterSpacing: unit * 0.8,
                                color: Palette.brandInk,
                              ),
                            ),
                            SizedBox(height: unit * 1.4),
                            Container(
                              width: unit * 5,
                              height: 1,
                              color: Palette.lampAmber.withValues(alpha: .7),
                            ),
                            SizedBox(height: unit * 2.2),
                            SettingsPanel(
                              key: ValueKey(_tab),
                              settings: widget.game.settings,
                              unit: unit,
                              initialTab: _tab,
                              width: math.min(
                                (unit * 70).clamp(380, 620),
                                size.width * 0.6,
                              ),
                              // Picked here, it plays at once to be heard.
                              onTry: (id) => widget.game.previewBackground = id,
                            ),
                            SizedBox(height: unit * 1.6),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                MenuWord(
                                  numeral: 'I',
                                  label: 'Reset',
                                  unit: unit,
                                  scale: .55,
                                  onTap: widget.game.settings.reset,
                                ),
                                SizedBox(width: unit * 5),
                                MenuWord(
                                  numeral: 'II',
                                  label: 'Back',
                                  unit: unit,
                                  scale: .55,
                                  onTap: () => _open(_Page.main),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _Page { main, chapters, settings, confirmBegin }

/// Keyboard, touch and assistive-technology accessible menu choice.
class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.size,
    required this.onTap,
    this.small = false,
    this.enabled = true,
    this.status,
  });
  final String label;
  final double size;
  final VoidCallback? onTap;
  final bool small, enabled;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final ink = Palette.brandInk.withValues(alpha: enabled ? .94 : .62);
    return TextButton(
      onPressed: enabled ? onTap : null,
      style: ButtonStyle(
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)
              ? Palette.lampAmber
              : ink,
        ),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: size, vertical: small ? 5 : 8),
        ),
        overlayColor: const WidgetStatePropertyAll(Color(0x0CFFFFFF)),
        textStyle: WidgetStatePropertyAll(
          TextStyle(
            fontFamily: 'Cormorant',
            fontStyle: FontStyle.italic,
            fontSize: (size * (small ? 3.4 : 5.4)).clamp(
              small ? 14.0 : 18.0,
              small ? 24.0 : 38.0,
            ),
            letterSpacing: .3,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, textAlign: TextAlign.center),
          if (status != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!enabled)
                    Padding(
                      padding: const EdgeInsets.only(right: 3),
                      child: Icon(Icons.lock_outline, size: 10, color: ink),
                    ),
                  Text(
                    status!.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'Cinzel',
                      fontStyle: FontStyle.normal,
                      fontSize: 9,
                      letterSpacing: 1.5,
                      color: status == 'Current' ? Palette.lampAmber : ink,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
