import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chapters/campaign_catalog.dart';
import 'settings_panel.dart';

/// Five visible cards from the forty-chapter campaign. Locked chapters can be
/// browsed, but their artwork is obscured and they cannot be played.
class ChapterCarousel extends StatefulWidget {
  const ChapterCarousel({
    super.key,
    required this.reached,
    required this.initialIndex,
    required this.onBack,
    required this.onPlay,
    this.currentIndex,
  });

  final int reached;
  final int initialIndex;
  final int? currentIndex;
  final VoidCallback onBack;
  final ValueChanged<int> onPlay;

  @override
  State<ChapterCarousel> createState() => _ChapterCarouselState();
}

class _ChapterCarouselState extends State<ChapterCarousel> {
  late int selected = widget.initialIndex.clamp(
    0,
    CampaignCatalog.ids.length - 1,
  );

  void move(int delta) => setState(() {
    selected = (selected + delta).clamp(0, CampaignCatalog.ids.length - 1);
  });

  double _drag = 0;
  String get status => selected > widget.reached
      ? 'Locked'
      : selected == (widget.currentIndex ?? widget.initialIndex)
      ? 'Current chapter'
      : selected < widget.reached
      ? 'Completed'
      : 'Unlocked';

  @override
  Widget build(BuildContext context) => Focus(
    autofocus: true,
    onKeyEvent: (_, event) {
      if (event is! KeyDownEvent) return KeyEventResult.ignored;
      if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
        move(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
        move(1);
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: ColoredBox(
      color: const Color(0xB8111111),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, bounds) => SingleChildScrollView(
            child: SizedBox(
              height: math.max(bounds.maxHeight, 330),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'CHAPTERS',
                            style: TextStyle(
                              fontFamily: 'Cinzel',
                              fontSize: 22,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Text(
                          '${selected + 1} / ${CampaignCatalog.ids.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 16),
                        DropdownButton<int>(
                          value: selected ~/ 5,
                          dropdownColor: const Color(0xFF202020),
                          style: const TextStyle(
                            color: Colors.white,
                            fontFamily: 'Roboto',
                            fontSize: 14,
                          ),
                          underline: const SizedBox.shrink(),
                          items: [
                            for (var i = 0; i < 8; i++)
                              DropdownMenuItem(
                                value: i,
                                child: Text('${i * 5 + 1}–${i * 5 + 5}'),
                              ),
                          ],
                          onChanged: (group) {
                            if (group != null) {
                              setState(() => selected = group * 5);
                            }
                          },
                        ),
                      ],
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, area) {
                          final h = math.min(area.maxHeight - 12, 420.0);
                          final w = math.min(h * .70, area.maxWidth * .42);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: (_) => _drag = 0,
                            onHorizontalDragUpdate: (d) => _drag += d.delta.dx,
                            onHorizontalDragEnd: (d) {
                              final velocity = d.primaryVelocity ?? 0;
                              if (_drag.abs() > 35 || velocity.abs() > 150) {
                                move(
                                  (_drag.abs() > 35 ? _drag : velocity) < 0
                                      ? 1
                                      : -1,
                                );
                              }
                            },
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                for (final offset in [-2, 2, -1, 1, 0])
                                  if (selected + offset >= 0 &&
                                      selected + offset <
                                          CampaignCatalog.ids.length)
                                    AnimatedPositioned(
                                      duration:
                                          MediaQuery.disableAnimationsOf(
                                            context,
                                          )
                                          ? Duration.zero
                                          : const Duration(milliseconds: 180),
                                      left:
                                          area.maxWidth / 2 +
                                          offset * w * .98 -
                                          w * (offset == 0 ? 1 : .78) / 2,
                                      top:
                                          (area.maxHeight -
                                              h * (offset == 0 ? 1 : .78)) /
                                          2,
                                      width: w * (offset == 0 ? 1 : .78),
                                      height: h * (offset == 0 ? 1 : .78),
                                      child: _ChapterCard(
                                        index: selected + offset,
                                        selected: offset == 0,
                                        locked:
                                            selected + offset > widget.reached,
                                        onTap: () =>
                                            setState(() => selected += offset),
                                      ),
                                    ),
                                Align(
                                  alignment: Alignment.centerLeft,
                                  child: _Arrow(
                                    left: true,
                                    enabled: selected > 0,
                                    onTap: () => move(-1),
                                  ),
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: _Arrow(
                                    left: false,
                                    enabled:
                                        selected <
                                        CampaignCatalog.ids.length - 1,
                                    onTap: () => move(1),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      CampaignCatalog.titles[selected],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cinzel',
                        fontSize: 18,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selected > widget.reached
                          ? 'Complete chapter $selected to unlock'
                          : status,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Roboto',
                        fontSize: 13,
                        color: Color(0xFFCCCCCC),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SettingsAction(label: 'Back', onTap: widget.onBack),
                        _FooterAction(
                          label: selected > widget.reached
                              ? 'LOCKED'
                              : status == 'Current chapter'
                              ? 'CONTINUE'
                              : status == 'Completed'
                              ? 'REPLAY'
                              : 'PLAY',
                          onTap: selected > widget.reached
                              ? null
                              : () => widget.onPlay(selected),
                          accent: true,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.index,
    required this.selected,
    required this.locked,
    required this.onTap,
  });
  final int index;
  final bool selected, locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    label:
        'Chapter ${index + 1}, ${CampaignCatalog.titles[index]}, ${locked ? 'locked' : 'unlocked'}',
    button: true,
    selected: selected,
    child: InkWell(
      key: ValueKey('chapter-card-$index'),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: selected
                ? Colors.white
                : Colors.white.withValues(alpha: .22),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.white.withValues(alpha: .12),
                    blurRadius: 15,
                  ),
                ]
              : null,
        ),
        child: ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: locked ? 5 : 0,
                  sigmaY: locked ? 5 : 0,
                ),
                child: Image.asset(
                  'assets/images/chapter_cards/${CampaignCatalog.ids[index]}.webp',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.medium,
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Colors.transparent, const Color(0xE6000000)],
                  ),
                ),
              ),
              if (locked) ...[
                const ColoredBox(color: Color(0x66000000)),
                Center(
                  child: CustomPaint(
                    key: ValueKey('chapter-lock-$index'),
                    size: Size.square(selected ? 38 : 29),
                    painter: const _LockPainter(),
                  ),
                ),
              ],
              Positioned(
                left: 8,
                right: 8,
                bottom: 12,
                child: Text(
                  '${CampaignCatalog.roman(index + 1)} · ${CampaignCatalog.titles[index].toUpperCase()}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Cinzel',
                    fontSize: selected ? 15 : 12,
                    letterSpacing: 1.8,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Arrow extends StatelessWidget {
  const _Arrow({
    required this.left,
    required this.enabled,
    required this.onTap,
  });
  final bool left;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: enabled ? onTap : null,
    icon: Opacity(
      opacity: enabled ? 1 : .25,
      child: CustomPaint(
        size: const Size(26, 32),
        painter: _ChevronPainter(left),
      ),
    ),
    tooltip: left ? 'Previous chapter' : 'Next chapter',
  );
}

class _ChevronPainter extends CustomPainter {
  const _ChevronPainter(this.left);
  final bool left;

  @override
  void paint(Canvas canvas, Size size) {
    final x = left ? size.width * .7 : size.width * .3;
    final tip = left ? size.width * .3 : size.width * .7;
    canvas.drawPath(
      Path()
        ..moveTo(x, 2)
        ..lineTo(tip, size.height / 2)
        ..lineTo(x, size.height - 2),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );
  }

  @override
  bool shouldRepaint(_ChevronPainter oldDelegate) => oldDelegate.left != left;
}

class _LockPainter extends CustomPainter {
  const _LockPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: .86)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          size.width * .23,
          size.height * .42,
          size.width * .54,
          size.height * .43,
        ),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        size.width * .32,
        size.height * .15,
        size.width * .36,
        size.height * .48,
      ),
      math.pi,
      math.pi,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _LockPainter oldDelegate) => false;
}

class _FooterAction extends StatelessWidget {
  const _FooterAction({
    required this.label,
    required this.onTap,
    this.accent = false,
  });
  final String label;
  final VoidCallback? onTap;
  final bool accent;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(
      minimumSize: const Size(120, 44),
      backgroundColor: onTap == null ? const Color(0x22FFFFFF) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontFamily: 'Roboto',
        letterSpacing: 1,
        fontSize: 14,
        color: onTap == null
            ? Colors.white.withValues(alpha: .4)
            : Colors.black,
      ),
    ),
  );
}
