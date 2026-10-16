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
    return FadeTransition(
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
                    Color(0x8C000000),
                  ],
                  stops: [0, 0.42, 1],
                ),
              ),
            ),
          ),
          Align(
            alignment: const Alignment(0.62, -0.72),
            child: SizedBox(
              width: size.width * 0.38,
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
                  if (!_chapters) ...[
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
                            : () => _go(() => director.playChapter(reached)),
                      ),
                    _Choice(
                      label: 'Chapters',
                      size: unit,
                      onTap: () => setState(() => _chapters = true),
                    ),
                  ] else ...[
                    for (var i = 0; i < Chapters.all.length; i++)
                      _Choice(
                        label: '${_roman(i + 1)}   ${Chapters.all[i].title}',
                        size: unit,
                        small: true,
                        enabled: i <= reached,
                        onTap: director == null || i > reached
                            ? null
                            : () => _go(
                                () => i == 0
                                    ? director.begin()
                                    : director.playChapter(i),
                              ),
                      ),
                    SizedBox(height: unit * 2),
                    _Choice(
                      label: 'Back',
                      size: unit,
                      small: true,
                      onTap: () => setState(() => _chapters = false),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _roman(int n) => const [
    '', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', //
    'XI', 'XII', 'XIII', 'XIV', 'XV',
  ][n.clamp(0, 15)];
}

/// One word of the menu: quiet ink, warming to amber under a finger.
class _Choice extends StatefulWidget {
  const _Choice({
    required this.label,
    required this.size,
    required this.onTap,
    this.small = false,
    this.enabled = true,
  });
  final String label;
  final double size;
  final VoidCallback? onTap;
  final bool small;
  final bool enabled;

  @override
  State<_Choice> createState() => _ChoiceState();
}

class _ChoiceState extends State<_Choice> {
  bool _hot = false;

  @override
  Widget build(BuildContext context) {
    final double u = widget.size;
    final Color ink = !widget.enabled
        ? Palette.brandInk.withValues(alpha: 0.25)
        : _hot
        ? Palette.lampAmber
        : Palette.brandInk.withValues(alpha: 0.82);
    return MouseRegion(
      cursor: widget.onTap == null
          ? SystemMouseCursors.basic
          : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hot = true),
      onExit: (_) => setState(() => _hot = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _hot = true),
        onTapCancel: () => setState(() => _hot = false),
        onTapUp: (_) => setState(() => _hot = false),
        onTap: widget.onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            vertical: u * (widget.small ? 1.2 : 1.5),
            horizontal: u * 4,
          ),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 220),
            style: TextStyle(
              fontFamily: 'Cinzel',
              fontSize: u * (widget.small ? 3.6 : 4.6),
              letterSpacing: u * (widget.small ? 0.4 : 0.9),
              color: ink,
              fontWeight: FontWeight.w400,
            ),
            child: Text(widget.label),
          ),
        ),
      ),
    );
  }
}
