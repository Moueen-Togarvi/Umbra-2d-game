import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chapters/chapters.dart';
import '../chapters/campaign_catalog.dart';
import '../config/palette.dart';
import '../game/umbra_game.dart';
import 'menu_scene.dart';
import 'main_menu_choice.dart';
import 'menu_word.dart';
import 'control_layout_editor.dart';
import 'chapter_carousel.dart';
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _fade.value = 1;
      _leave.duration = Duration.zero;
    } else {
      _leave.duration = const Duration(milliseconds: 700);
    }
  }

  @override
  void dispose() {
    widget.game.coveredByMenu = false;
    if (widget.game.titleBack == _back) widget.game.titleBack = null;
    _fade.dispose();
    _leave.dispose();
    super.dispose();
  }

  void _open(_Page page) => setState(() {
    _page = page;
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
        'New game',
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
    Widget mainMenu() => Positioned.fill(
      child: CustomPaint(
        painter: const _MainMenuFramePainter(),
        child: Stack(
          children: [
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.symmetric(vertical: unit * 3),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: math.min(size.width * .82, 430),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          'UMBRA',
                          semanticsLabel: 'Umbra',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: (unit * 7.2).clamp(34, 64),
                            fontWeight: FontWeight.w400,
                            letterSpacing: (unit * 1.8).clamp(7, 15),
                            color: Palette.brandInk,
                            shadows: const [
                              Shadow(color: Color(0x66000000), blurRadius: 16),
                            ],
                          ),
                        ),
                        SizedBox(height: unit * .5),
                        Text(
                          'A child lost between dusk and dawn',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'Cormorant',
                            fontStyle: FontStyle.italic,
                            fontSize: (unit * 3.3).clamp(15, 22),
                            color: Palette.brandInk.withValues(alpha: .82),
                            shadows: const [
                              Shadow(color: Color(0x99000000), blurRadius: 8),
                            ],
                          ),
                        ),
                        SizedBox(height: (unit * 3.2).clamp(16, 28)),
                        for (final (i, (label, onTap)) in choices.indexed)
                          MainMenuChoice(
                            label: label,
                            unit: unit,
                            selected: i == _mainSelection,
                            centered: true,
                            ornamental: true,
                            minimumWidth: math.min(size.width * .52, 300),
                            autofocus: i == 0,
                            onHighlight: () {
                              if (_mainSelection != i) {
                                setState(() => _mainSelection = i);
                              }
                            },
                            onTap: onTap,
                          ),
                        if (progress.saveFailed)
                          Padding(
                            padding: EdgeInsets.only(top: unit),
                            child: const Text(
                              'Progress could not be saved. Check device storage.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Palette.brandInk,
                                fontSize: 13,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: size.height * .075,
              child: IgnorePointer(
                child: Text(
                  'UMBRA · MAIN MENU',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: (unit * 1.4).clamp(8, 11),
                    letterSpacing: 1,
                    color: Palette.brandInk.withValues(alpha: .92),
                    shadows: const [
                      Shadow(color: Color(0xCC000000), blurRadius: 6),
                    ],
                  ),
                ),
              ),
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
            BackdropFilter(
              filter: ui.ImageFilter.blur(
                sigmaX: _page == _Page.main ? 3 : 8,
                sigmaY: _page == _Page.main ? 3 : 8,
              ),
              child: ColoredBox(
                color: _page == _Page.main
                    ? const Color(0x66080A0B)
                    : const Color(0xA6080A0B),
              ),
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
                        'Start a new game?',
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
                        label: 'New game',
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
                    Positioned.fill(
                      child: ChapterCarousel(
                        reached: reached,
                        initialIndex: progress.current,
                        currentIndex: progress.current,
                        onBack: () => _open(_Page.main),
                        onPlay: (i) {
                          if (director != null) {
                            _go(
                              () => i == 0
                                  ? director.begin()
                                  : director.playChapter(i),
                            );
                          }
                        },
                      ),
                    ),
                  if (_page == _Page.settings)
                    Positioned.fill(
                      child: SafeArea(
                        child: Center(
                          child: SingleChildScrollView(
                            child: SizedBox(
                              key: const ValueKey('title-settings-content'),
                              width: math.min(
                                (unit * 70).clamp(340, 620),
                                size.width * .88,
                              ),
                              child: SettingsPanel(
                                key: ValueKey(_tab),
                                settings: widget.game.settings,
                                unit: unit,
                                initialTab: _tab,
                                centered: true,
                                onBack: () => _open(_Page.main),
                                onCustomize: () => showControlLayoutEditor(
                                  context,
                                  widget.game.settings,
                                ),
                              ),
                            ),
                          ),
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

class _MainMenuFramePainter extends CustomPainter {
  const _MainMenuFramePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(
      size.width * .09,
      size.height * .07,
      size.width * .91,
      size.height * .93,
    );
    final paint = Paint()
      ..color = const Color(0x82D2D4D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(rect, paint);

    final corner = 18.0;
    final notch = 7.0;
    final details = Path()
      ..moveTo(rect.left + corner, rect.top)
      ..lineTo(rect.left + notch, rect.top)
      ..lineTo(rect.left + notch, rect.top + notch)
      ..lineTo(rect.left, rect.top + notch)
      ..moveTo(rect.right - corner, rect.top)
      ..lineTo(rect.right - notch, rect.top)
      ..lineTo(rect.right - notch, rect.top + notch)
      ..lineTo(rect.right, rect.top + notch)
      ..moveTo(rect.left + corner, rect.bottom)
      ..lineTo(rect.left + notch, rect.bottom)
      ..lineTo(rect.left + notch, rect.bottom - notch)
      ..lineTo(rect.left, rect.bottom - notch)
      ..moveTo(rect.right - corner, rect.bottom)
      ..lineTo(rect.right - notch, rect.bottom)
      ..lineTo(rect.right - notch, rect.bottom - notch)
      ..lineTo(rect.right, rect.bottom - notch);
    canvas.drawPath(details, paint..color = const Color(0xC2D2D4D0));
  }

  @override
  bool shouldRepaint(covariant _MainMenuFramePainter oldDelegate) => false;
}
