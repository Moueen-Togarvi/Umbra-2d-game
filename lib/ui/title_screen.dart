import 'package:flutter/material.dart';

import '../chapters/chapters.dart';
import '../config/palette.dart';
import '../game/umbra_game.dart';
import 'wordmark.dart';

/// The title, laid over the game's first scene: the cottage at dusk with
/// the lamp lit. The wordmark, and three quiet words — Begin, Continue,
/// Chapters — fade in after the picture does. Nothing else: no logo
/// splash, no button chrome; it should feel like the opening shot of the
/// story with its name over it.
class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key, required this.game});
  final UmbraGame game;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 3300),
  );
  bool _chapters = false;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    // The words come up after the picture has.
    _fade.forward();
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  Future<void> _go(void Function() action) async {
    if (_leaving) return;
    setState(() => _leaving = true);
    await _fade.animateBack(0, duration: const Duration(milliseconds: 700));
    action();
  }

  @override
  Widget build(BuildContext context) {
    final director = widget.game.director;
    final int reached = widget.game.progress.reached;
    final Size size = MediaQuery.sizeOf(context);
    final double unit = size.shortestSide / 100;
    Widget chapterChoice(int i) => _Choice(
      label: '${_roman(i + 1)}   ${Chapters.all[i].title}',
      size: unit,
      small: true,
      status: i > reached
          ? 'Locked'
          : i == reached
          ? 'Current'
          : 'Replay',
      enabled: i <= reached,
      onTap: director == null || i > reached
          ? null
          : () =>
                _go(() => i == 0 ? director.begin() : director.playChapter(i)),
    );
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _fade,
          curve: const Interval(0.27, 1, curve: Curves.easeInOut),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // A shade on the right, where the words are, so they read over
            // the fog without a panel.
            const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: [
                      Color(0x00000000),
                      Color(0x00000000),
                      Color(0x77000000),
                      Color(0xA6000000),
                    ],
                    stops: [0, 0.35, 0.55, 1],
                  ),
                ),
              ),
            ),
            if (!_chapters)
              Align(
                alignment: const Alignment(0.62, 0),
                child: SizedBox(
                  width: size.width * 0.43,
                  height: size.height * 0.86,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Wordmark(height: unit * 13, eyes: Palette.lampAmber),
                        SizedBox(height: unit * 2.4),
                        Container(
                          width: unit * 7,
                          height: unit * 0.35,
                          color: Palette.lampAmber.withValues(alpha: 0.8),
                        ),
                        SizedBox(height: unit * 3.5),
                        _Choice(
                          label: 'Begin',
                          size: unit,
                          onTap: director == null
                              ? null
                              : () => _go(director.begin),
                        ),
                        if (reached > 0)
                          _Choice(
                            label: 'Continue',
                            size: unit,
                            onTap: director == null
                                ? null
                                : () =>
                                      _go(() => director.playChapter(reached)),
                          ),
                        _Choice(
                          label: 'Chapters',
                          size: unit,
                          onTap: () => setState(() => _chapters = true),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (_chapters)
              Align(
                alignment: const Alignment(0.95, 0),
                child: Container(
                  width: size.width * 0.51,
                  height: size.height * 0.88,
                  padding: EdgeInsets.symmetric(horizontal: unit),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'CHAPTERS',
                          style: TextStyle(
                            fontFamily: 'Cinzel',
                            fontSize: (unit * 4).clamp(16, 28),
                            letterSpacing: unit * 0.8,
                            color: Palette.brandInk,
                          ),
                        ),
                        SizedBox(height: unit * 3),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  for (
                                    var i = 0;
                                    i < (Chapters.all.length + 1) ~/ 2;
                                    i++
                                  )
                                    chapterChoice(i),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  for (
                                    var i = (Chapters.all.length + 1) ~/ 2;
                                    i < Chapters.all.length;
                                    i++
                                  )
                                    chapterChoice(i),
                                ],
                              ),
                            ),
                          ],
                        ),
                        _Choice(
                          label: 'Back',
                          size: unit,
                          small: true,
                          onTap: () => setState(() => _chapters = false),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static String _roman(int n) => const [
    '', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', //
    'XI', 'XII', 'XIII', 'XIV', 'XV',
  ][n.clamp(0, 15)];
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
            fontFamily: 'Cinzel',
            fontSize: (size * (small ? 2.7 : 4.6)).clamp(
              small ? 11.0 : 15.0,
              small ? 19.0 : 32.0,
            ),
            letterSpacing: small ? .6 : 2,
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
                    status!,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 9,
                      letterSpacing: 1,
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
