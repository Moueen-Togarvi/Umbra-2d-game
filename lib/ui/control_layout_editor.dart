import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../config/game_config.dart';
import '../config/game_settings.dart';
import '../config/palette.dart';
import '../input/touch_controls.dart';
import 'settings_panel.dart';

Future<void> showControlLayoutEditor(
  BuildContext context,
  GameSettings settings,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ControlLayoutEditor(settings: settings),
);

class _ControlLayoutEditor extends StatefulWidget {
  const _ControlLayoutEditor({required this.settings});
  final GameSettings settings;

  @override
  State<_ControlLayoutEditor> createState() => _ControlLayoutEditorState();
}

class _ControlLayoutEditorState extends State<_ControlLayoutEditor> {
  final _previewKey = GlobalKey();
  late Map<String, Offset> _positions = Map.of(
    widget.settings.controlPositions,
  );
  Size? _lastSize;
  bool _resetLayout = false;
  bool _guides = true;
  Size _viewport = const Size(800, 360);

  Map<String, Offset> _defaults(Size _) => TouchControls.defaultLayout(
    viewport: _viewport,
    scale: widget.settings.controlsScale,
    leftHanded: widget.settings.leftHanded,
  );

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final unit = screen.shortestSide / 100;
    final padding = MediaQuery.paddingOf(context);
    _viewport = Size(
      screen.width - padding.horizontal,
      screen.height - padding.vertical,
    );
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: ColoredBox(
            color: const Color(0xCC111111),
            child: SizedBox(
              width: math.min(screen.width - 48, 980),
              height: math.min(screen.height - 48, 660),
              child: Padding(
                padding: EdgeInsets.all(unit.clamp(4, 12)),
                child: Column(
                  children: [
                    Text(
                      'CUSTOMIZE CONTROLS',
                      style: TextStyle(
                        fontFamily: 'Roboto',
                        color: Palette.brandInk,
                        fontSize: (unit * 3.2).clamp(15, 24),
                        letterSpacing: 2,
                      ),
                    ),
                    SizedBox(height: unit),
                    Text(
                      'Drag each button where it feels comfortable.',
                      style: TextStyle(
                        color: Palette.brandInk.withValues(alpha: .65),
                        fontFamily: 'Roboto',
                        fontSize: (unit * 2.7).clamp(14, 20),
                      ),
                    ),
                    SizedBox(height: unit * 1.5),
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: _viewport.aspectRatio,
                          child: LayoutBuilder(
                            builder: (context, bounds) {
                              final size = Size(
                                bounds.maxWidth,
                                bounds.maxHeight,
                              );
                              final defaults = _defaults(size);
                              if (_lastSize != size) {
                                _lastSize = size;
                                if (_positions.isEmpty) {
                                  _positions = Map.of(defaults);
                                }
                              }
                              final positions = {...defaults, ..._positions};
                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Palette.controlRing,
                                  ),
                                  image: const DecorationImage(
                                    image: AssetImage(
                                      "assets/images/backgrounds/forest.webp",
                                    ),
                                    fit: BoxFit.cover,
                                    opacity: .55,
                                  ),
                                ),
                                child: Stack(
                                  key: _previewKey,
                                  clipBehavior: Clip.hardEdge,
                                  children: [
                                    if (_guides)
                                      Positioned.fill(
                                        child: IgnorePointer(
                                          child: CustomPaint(
                                            painter: _GuidePainter(),
                                          ),
                                        ),
                                      ),
                                    Positioned(
                                      left: 0,
                                      right: 0,
                                      bottom: 12,
                                      child: Container(
                                        height: 1,
                                        color: Palette.controlRing,
                                      ),
                                    ),
                                    for (final id in TouchControls.layoutIds)
                                      _draggable(id, positions[id]!, size),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: unit * 1.5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Checkbox(
                          value: _guides,
                          activeColor: Colors.white,
                          checkColor: Colors.black,
                          onChanged: (v) => setState(() => _guides = v!),
                        ),
                        const Text(
                          'Alignment guides',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                        if (_lastSize != null &&
                            _overlaps(_lastSize!).isNotEmpty)
                          const Flexible(
                            child: Text(
                              '  Overlap — move outlined buttons',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: unit * 2,
                      runSpacing: unit,
                      children: [
                        SettingsAction(
                          label: 'Reset layout',
                          onTap: () => setState(() {
                            _positions = _defaults(_lastSize!);
                            _resetLayout = true;
                          }),
                        ),
                        SettingsAction(
                          label: 'Cancel',
                          onTap: () => Navigator.of(context).pop(),
                        ),
                        SettingsAction(
                          label: 'Save layout',
                          primary: true,
                          onTap: () async {
                            if (_resetLayout) {
                              await widget.settings.resetControlPositions();
                            } else {
                              await widget.settings.saveControlPositions(
                                _positions,
                              );
                            }
                            if (context.mounted) Navigator.of(context).pop();
                          },
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
    );
  }

  double _diameter(String id, Size size) {
    final base = switch (id) {
      'pause' => 46.0,
      'attack' =>
        GameConfig.controlButtonDiameterPx *
            widget.settings.controlsScale *
            1.12,
      _ =>
        GameConfig.controlButtonDiameterPx *
            widget.settings.controlsScale *
            (id.startsWith('climb') ? .78 : 1),
    };
    return base * size.width / _viewport.width;
  }

  Set<String> _overlaps(Size size) {
    final positions = {..._defaults(size), ..._positions};
    final result = <String>{};
    final ids = TouchControls.layoutIds;
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        final a = positions[ids[i]]!, b = positions[ids[j]]!;
        if (Offset(
              (a.dx - b.dx) * size.width,
              (a.dy - b.dy) * size.height,
            ).distance <
            (_diameter(ids[i], size) + _diameter(ids[j], size)) / 2 + 2) {
          result.addAll([ids[i], ids[j]]);
        }
      }
    }
    return result;
  }

  Widget _draggable(String id, Offset position, Size size) {
    final diameter = _diameter(id, size);
    final center = Offset(position.dx * size.width, position.dy * size.height);
    return Positioned(
      left: center.dx - diameter / 2,
      top: center.dy - diameter / 2,
      width: diameter,
      height: diameter,
      child: GestureDetector(
        key: ValueKey('control-layout-$id'),
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          final box =
              _previewKey.currentContext!.findRenderObject()! as RenderBox;
          final local = box.globalToLocal(details.globalPosition);
          setState(() {
            _resetLayout = false;
            _positions[id] = Offset(
              (local.dx / size.width).clamp(
                diameter / (2 * size.width),
                1 - diameter / (2 * size.width),
              ),
              (local.dy / size.height).clamp(
                diameter / (2 * size.height),
                1 - diameter / (2 * size.height),
              ),
            );
          });
        },
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: _overlaps(size).contains(id)
                ? Border.all(color: Colors.white, width: 3)
                : null,
          ),
          child: _PreviewButton(id: id, diameter: diameter),
        ),
      ),
    );
  }
}

class _PreviewButton extends StatelessWidget {
  const _PreviewButton({required this.id, required this.diameter});
  final String id;
  final double diameter;

  @override
  Widget build(BuildContext context) {
    final action =
        id == 'jump' ||
        id == 'sit' ||
        id == 'attack' ||
        id == 'throw' ||
        id == 'dash' ||
        id == 'grab';
    final asset = switch (id) {
      'left' || 'right' || 'climbUp' || 'climbDown' => 'ui_arrow.png',
      'jump' => 'ui_jump.png',
      'sit' => 'ui_sit.png',
      'attack' => 'ui_slash.png',
      'throw' => 'ui_throw.png',
      'dash' => 'ui_dash.png',
      'grab' => 'ui_hand.png',
      _ => 'ui_pause.png',
    };
    final degrees = switch (id) {
      'left' => 180.0,
      'climbUp' => -90.0,
      'climbDown' => 90.0,
      _ => 0.0,
    };
    final Widget face = Image.asset(
            'assets/images/ui/$asset',
            width: diameter * (action ? .48 : .58),
            height: diameter * (action ? .52 : .58),
            fit: BoxFit.contain,
            color: Palette.controlGlyph,
          );
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: action ? Palette.control : const Color(0x0AFFFFFF),
        border: Border.all(color: Palette.controlRing),
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Transform.rotate(angle: degrees * math.pi / 180, child: face),
          if (action)
            Positioned(
              bottom: diameter * .12,
              child: Text(
                switch (id) {
                  'jump' => 'JUMP',
                  'sit' => 'SIT',
                  'attack' => 'SLASH',
                  'throw' => 'THROW',
                  'dash' => 'DASH',
                  _ => 'GRAB',
                },
                style: TextStyle(
                  color: Palette.controlGlyph,
                  fontSize: (diameter * .15).clamp(8, 12),
                  fontWeight: FontWeight.w700,
                  letterSpacing: .8,
                ),
              ),
            ),
          if (!action && id != 'pause')
            Positioned(
              bottom: diameter * .12,
              child: Text(
                switch (id) {
                  'left' => 'LEFT',
                  'right' => 'RIGHT',
                  'climbUp' => 'UP',
                  'climbDown' => 'DOWN',
                  _ => '',
                },
                style: TextStyle(
                  color: Palette.controlGlyph,
                  fontSize: (diameter * .14).clamp(8, 11),
                  fontWeight: FontWeight.w700,
                  letterSpacing: .5,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0x55FFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(Offset.zero & size, paint);
    for (final t in [.25, .5, .75]) {
      canvas.drawLine(
        Offset(size.width * t, 0),
        Offset(size.width * t, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * t),
        Offset(size.width, size.height * t),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidePainter oldDelegate) => false;
}
