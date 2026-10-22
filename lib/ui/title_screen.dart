import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../chapters/chapters.dart';
import '../chapters/campaign_catalog.dart';
import '../config/palette.dart';
import '../game/umbra_game.dart';
import 'audio_settings.dart';
import 'menu_scene.dart';
import 'wordmark.dart';

/// The main menu: the white tree on its hill (see [MenuScene]), and on the
/// right the wordmark over a few numbered words — Continue, Begin,
/// Chapters, Music — with the lantern's warm light behind the first. The
/// picture comes up first, then the words; leaving, it all fades into
/// the game.
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
  bool _chapters = false;

  /// The music and sound settings are open.
  bool _music = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // The words come up after the picture has.
    _fade.forward();
  }

  @override
  void dispose() {
    widget.game.previewBackground = null;
    _fade.dispose();
    _leave.dispose();
    super.dispose();
  }

  Future<void> _go(void Function() action) async {
    if (_leaving) return;
    setState(() => _leaving = true);
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
      ('Begin', director == null ? null : () => _go(director.begin)),
      ('Chapters', () => setState(() => _chapters = true)),
      ('Music', () => setState(() => _music = true)),
    ];
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
                  if (!_chapters && !_music)
                    Positioned(
                      right: size.width * 0.069,
                      top: size.height * 0.11,
                      bottom: size.height * 0.04,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Wordmark(
                              height: unit * 9.8,
                              eyes: Palette.lampAmber,
                            ),
                            SizedBox(height: unit * 7),
                            for (final (i, (label, onTap)) in choices.indexed)
                              _MenuItem(
                                numeral: CampaignCatalog.roman(i + 1),
                                label: label,
                                unit: unit,
                                primary: i == 0,
                                onTap: onTap,
                              ),
                          ],
                        ),
                      ),
                    ),
                  if (_chapters)
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
                      _Choice(
                        label: 'Back',
                        size: unit,
                        small: true,
                        onTap: () => setState(() => _chapters = false),
                      ),
                    ]),
                  if (_music)
                    panel('MUSIC', width: (size.width * 0.5).clamp(320, 560), [
                      AudioSettings(
                        settings: widget.game.settings,
                        // Picked here, it plays at once to be heard.
                        onTry: (id) => widget.game.previewBackground = id,
                      ),
                      _Choice(
                        label: 'Back',
                        size: unit,
                        small: true,
                        onTap: () => setState(() {
                          _music = false;
                          widget.game.previewBackground = null;
                        }),
                      ),
                    ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One of the main menu's words: a Cinzel numeral in amber, the word in
/// italic Cormorant, and the lantern's light behind it when it is the
/// first, or under the pointer, or focused.
class _MenuItem extends StatefulWidget {
  const _MenuItem({
    required this.numeral,
    required this.label,
    required this.unit,
    required this.onTap,
    this.primary = false,
  });
  final String numeral, label;
  final double unit;
  final VoidCallback? onTap;
  final bool primary;

  @override
  State<_MenuItem> createState() => _MenuItemState();
}

class _MenuItemState extends State<_MenuItem> {
  bool _hot = false;

  void _set(bool hot) {
    if (hot != _hot) setState(() => _hot = hot);
  }

  @override
  Widget build(BuildContext context) {
    final double u = widget.unit;
    final bool lit = widget.primary || _hot;
    return TextButton(
      onPressed: widget.onTap,
      onHover: _set,
      onFocusChange: _set,
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        minimumSize: const WidgetStatePropertyAll(Size(44, 44)),
        padding: WidgetStatePropertyAll(
          EdgeInsets.symmetric(vertical: u * 1.9),
        ),
      ),
      child: CustomPaint(
        painter: lit ? _Glow(u) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              widget.numeral,
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: u * 2.1,
                letterSpacing: u * .42,
                color: Palette.lampAmber.withValues(alpha: lit ? 1 : .55),
              ),
            ),
            SizedBox(width: u * 3),
            Text(
              widget.label,
              style: TextStyle(
                fontFamily: 'Cormorant',
                fontStyle: FontStyle.italic,
                fontSize: u * 6.1,
                height: 1.1,
                color: Palette.brandInk.withValues(alpha: lit ? .96 : .5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lantern's warm light behind a menu word, fading out to the left.
class _Glow extends CustomPainter {
  const _Glow(this.unit);
  final double unit;

  @override
  void paint(Canvas canvas, Size size) {
    // Drawn in the design's 720-high frame, scaled to this screen.
    final double s = unit / 7.2;
    final centre = Offset(size.width - 62 * s, size.height / 2);
    final double rx = 236 * s, ry = 59 * s;
    final m = Matrix4.identity()
      ..translateByDouble(centre.dx, centre.dy, 0, 1)
      ..scaleByDouble(rx / ry, 1, 1, 1)
      ..translateByDouble(-centre.dx, -centre.dy, 0, 1);
    canvas.drawRect(
      Rect.fromCenter(center: centre, width: rx * 2, height: ry * 2),
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          ry,
          [
            Palette.lampAmber.withValues(alpha: .30),
            Palette.lampAmber.withValues(alpha: 0),
          ],
          const [0, 1],
          TileMode.clamp,
          m.storage,
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _Glow oldDelegate) => oldDelegate.unit != unit;
}

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
