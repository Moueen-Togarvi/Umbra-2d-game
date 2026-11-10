import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/game_settings.dart';

/// The three pages of the settings.
enum SettingsTab { display, controls, sound }

/// Shared settings panel for the title and pause screens.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.unit,
    this.initialTab = SettingsTab.display,
    this.width = 470,
    this.centered = false,
    this.onCustomize,
    this.onBack,
  });

  final GameSettings settings;

  /// The screen's size unit (a hundredth of its shorter side).
  final double unit;
  final SettingsTab initialTab;
  final double width;
  final bool centered;
  final VoidCallback? onCustomize;
  final VoidCallback? onBack;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late SettingsTab _tab = widget.initialTab;
  String _feedback = "Changes save automatically";

  @override
  void didUpdateWidget(covariant SettingsPanel old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) _tab = widget.initialTab;
  }

  @override
  Widget build(BuildContext context) {
    final double u = widget.unit;
    final settings = widget.settings;
    return SizedBox(
      width: widget.width,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: (u * 2).clamp(10, 18),
              vertical: (u * 1.4).clamp(8, 14),
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: const Color(0x99111111),
              border: Border.all(color: Colors.white.withValues(alpha: .19)),
              boxShadow: const [
                BoxShadow(color: Color(0x99000000), blurRadius: 28),
                BoxShadow(color: Color(0x18FFFFFF), blurRadius: 0),
              ],
            ),
            child: ListenableBuilder(
              listenable: settings,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Settings',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 24,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: .27),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        for (final tab in SettingsTab.values)
                          Expanded(
                            child: _Tab(
                              label: _label(tab),
                              chosen: tab == _tab,
                              unit: u,
                              onTap: () => setState(() => _tab = tab),
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(height: u * 3),
                  SizedBox(
                    height: (MediaQuery.sizeOf(context).height - 235).clamp(
                      80.0,
                      340.0,
                    ),
                    child: SingleChildScrollView(
                      key: ValueKey(_tab),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _withDividers(_page(settings, u)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _feedback,
                    textAlign: TextAlign.center,
                    semanticsLabel: _feedback,
                    style: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12,
                      color: Color(0xFFCCCCCC),
                    ),
                  ),
                  if (widget.onBack != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        SettingsAction(
                          label: 'Reset',
                          onTap: () async {
                            final reset = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                backgroundColor: const Color(0xFF181818),
                                title: const Text(
                                  'Reset all settings?',
                                  style: TextStyle(color: Colors.white),
                                ),
                                content: const Text(
                                  'Sound, display and control layout will return to defaults. Chapter progress stays saved.',
                                  style: TextStyle(color: Color(0xFFCCCCCC)),
                                ),
                                actions: [
                                  SettingsAction(
                                    label: 'Cancel',
                                    onTap: () => Navigator.pop(context, false),
                                  ),
                                  SettingsAction(
                                    label: 'Reset',
                                    primary: true,
                                    onTap: () => Navigator.pop(context, true),
                                  ),
                                ],
                              ),
                            );
                            if (reset == true) {
                              await settings.reset();
                              if (mounted) {
                                setState(() => _feedback = 'Settings restored');
                                Future.delayed(const Duration(seconds: 3), () {
                                  if (mounted) {
                                    setState(
                                      () => _feedback =
                                          'Changes save automatically',
                                    );
                                  }
                                });
                              }
                            }
                          },
                        ),
                        SettingsAction(
                          label: 'Back',
                          primary: true,
                          onTap: widget.onBack!,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _withDividers(List<Widget> rows) => [
    for (final (index, row) in rows.indexed) ...[
      if (index > 0)
        Divider(
          height: 1,
          thickness: 1,
          color: Colors.white.withValues(alpha: .16),
        ),
      row,
    ],
  ];

  static String _label(SettingsTab tab) => switch (tab) {
    SettingsTab.display => 'Display',
    SettingsTab.controls => 'Controls',
    SettingsTab.sound => 'Sound',
  };

  List<Widget> _page(GameSettings s, double u) => switch (_tab) {
    SettingsTab.display => [
      _SliderRow(s, 'Brightness', 'brightness', u, min: .8, max: 1.3),
      _SliderRow(s, 'Film grain', 'atmosphere', u),
      _ToggleRow(
        'Reduced motion',
        s.reducedMotion,
        u,
        (on) => s.setFlag('reducedMotion', on),
        id: 'reducedMotion',
      ),
      _ToggleRow(
        'Camera shake',
        s.cameraShake,
        u,
        (on) => s.setFlag('cameraShake', on),
        id: 'cameraShake',
        compact: true,
      ),
    ],
    SettingsTab.controls => [
      _SliderRow(s, 'Button size', 'controlsScale', u, min: .8, max: 1.3),
      _SliderRow(s, 'Button opacity', 'controlsOpacity', u, min: .3, max: 1),
      _ToggleRow(
        'Left-handed',
        s.leftHanded,
        u,
        (on) => s.setFlag('leftHanded', on),
        id: 'leftHanded',
      ),
      _ToggleRow(
        'Vibration',
        s.vibration,
        u,
        (on) => s.setFlag('vibration', on),
        id: 'vibration',
      ),
      if (widget.onCustomize != null) ...[
        OutlinedButton(
          onPressed: widget.onCustomize,
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF111111),
            backgroundColor: Colors.white,
            side: BorderSide(color: Colors.white),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
            minimumSize: const Size(180, 44),
          ),
          child: Text(
            'Customize Layout',
            style: _labelStyle(
              (u * 2.8).clamp(15, 20),
              const Color(0xFF111111),
            ),
          ),
        ),
      ],
    ],
    SettingsTab.sound => [
      _ToggleRow(
        'Music',
        s.musicOn,
        u,
        (on) => s.setFlag('musicOn', on),
        id: 'musicOn',
      ),
      _ToggleRow(
        'Sound',
        s.soundOn,
        u,
        (on) => s.setFlag('soundOn', on),
        id: 'soundOn',
      ),
      _SliderRow(s, 'Music volume', 'music', u),
      _SliderRow(s, 'Ambience', 'ambience', u),
      _SliderRow(s, 'Effects', 'effects', u),
    ],
  };
}

TextStyle _labelStyle(double size, Color color) => TextStyle(
  fontFamily: 'Roboto',
  fontWeight: FontWeight.w500,
  fontSize: size,
  height: 1.5,
  color: color,
);

const Color _dim = Color(0xFFCCCCCC);

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.chosen,
    required this.unit,
    required this.onTap,
  });
  final String label;
  final bool chosen;
  final double unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: AnimatedContainer(
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: (unit * 1.6).clamp(10, 18),
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color: chosen ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: (unit * 2).clamp(10, 14),
                letterSpacing: 1,
                color: chosen ? const Color(0xFF111111) : Colors.white,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// A setting with its thin slider and its value.
class _SliderRow extends StatelessWidget {
  const _SliderRow(
    this.settings,
    this.label,
    this.setting,
    this.unit, {
    this.min = 0,
    this.max = 1,
  });

  final GameSettings settings;
  final String label, setting;
  final double unit, min, max;

  double get _value => switch (setting) {
    'brightness' => settings.brightness,
    'atmosphere' => settings.atmosphere,
    'controlsScale' => settings.controlsScale,
    'controlsOpacity' => settings.controlsOpacity,
    'ambience' => settings.ambience,
    'effects' => settings.effects,
    'music' => settings.music,
    _ => throw ArgumentError.value(setting, 'setting'),
  };

  @override
  Widget build(BuildContext context) {
    final double value = _value;
    return SizedBox(
      height: (unit * 7.6).clamp(44, 64),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                textAlign: TextAlign.left,
                maxLines: 1,
                style: _labelStyle(
                  (unit * 2.4).clamp(14, 17),
                  Colors.white.withValues(alpha: .92),
                ),
              ),
            ),
          ),
          SizedBox(width: unit * 3.2),
          Expanded(
            flex: 1,
            child: ThinSlider(
              key: ValueKey(setting),
              value: value,
              min: min,
              max: max,
              label: label,
              onChanged: (v) => settings.set(setting, v),
            ),
          ),
          SizedBox(
            width: 44,
            child: Text(
              '${(value * 100).round()}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: (unit * 1.6).clamp(10, 13),
                letterSpacing: 1,
                color: _dim,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  const _ToggleRow(
    this.label,
    this.on,
    this.unit,
    this.changed, {
    required this.id,
    this.compact = false,
  });
  final String label, id;
  final bool compact;
  final bool on;
  final double unit;
  final ValueChanged<bool> changed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: (unit * 7.6).clamp(44, 64),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      mainAxisSize: MainAxisSize.max,
      children: [
        Flexible(
          child: Text(
            label,
            style: _labelStyle(
              (unit * 2.4).clamp(14, 17),
              Colors.white.withValues(alpha: .92),
            ),
          ),
        ),
        SizedBox(width: compact ? unit * 1.4 : unit * 3.2),
        PillToggle(
          key: ValueKey('toggle-$id'),
          value: on,
          label: label,
          onChanged: changed,
        ),
      ],
    ),
  );
}

/// A slider drawn as a hairline with an white bead: dragged, tapped, or
/// stepped with the arrow keys.
class ThinSlider extends StatefulWidget {
  const ThinSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
    this.min = 0,
    this.max = 1,
  });
  final double value, min, max;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  State<ThinSlider> createState() => _ThinSliderState();
}

class _ThinSliderState extends State<ThinSlider> {
  bool _focused = false, _held = false;

  double get _t =>
      ((widget.value - widget.min) / (widget.max - widget.min)).clamp(0, 1);

  void _setFrom(double dx, double width) {
    final double t = (dx / width).clamp(0.0, 1.0);
    widget.onChanged(widget.min + (widget.max - widget.min) * t);
  }

  void _nudge(double by) => widget.onChanged(
    (widget.value + (widget.max - widget.min) * by).clamp(
      widget.min,
      widget.max,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final int percent = (widget.value * 100).round();
    return Semantics(
      slider: true,
      label: widget.label,
      value: '$percent percent',
      increasedValue: '${(percent + 5).clamp(0, 999)} percent',
      decreasedValue: '${(percent - 5).clamp(0, 999)} percent',
      onIncrease: () => _nudge(.05),
      onDecrease: () => _nudge(-.05),
      child: Focus(
        onFocusChange: (f) => setState(() => _focused = f),
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            _nudge(.05);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            _nudge(-.05);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: LayoutBuilder(
          builder: (context, box) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _setFrom(d.localPosition.dx, box.maxWidth),
            onHorizontalDragStart: (d) {
              setState(() => _held = true);
              _setFrom(d.localPosition.dx, box.maxWidth);
            },
            onHorizontalDragUpdate: (d) =>
                _setFrom(d.localPosition.dx, box.maxWidth),
            onHorizontalDragEnd: (_) => setState(() => _held = false),
            child: SizedBox(
              height: 44,
              child: CustomPaint(
                painter: _ThinSliderPainter(_t, _focused || _held),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ThinSliderPainter extends CustomPainter {
  _ThinSliderPainter(this.t, this.lit);
  final double t;
  final bool lit;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final double x = size.width * t;
    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..strokeWidth = 3,
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(x, y),
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..strokeWidth = 3,
    );
    canvas.drawCircle(
      Offset(x, y),
      lit ? 11 : 8,
      Paint()
        ..color = Colors.white.withValues(alpha: lit ? .32 : .22)
        ..maskFilter = const MaskFilter.blur(ui.BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      Offset(x, y),
      lit ? 6.5 : 5.5,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _ThinSliderPainter old) =>
      old.t != t || old.lit != lit;
}

/// An on/off button using the menu's ivory and charcoal treatment.
class PillToggle extends StatelessWidget {
  const PillToggle({
    super.key,
    required this.value,
    required this.onChanged,
    required this.label,
  });
  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    toggled: value,
    label: label,
    button: true,
    excludeSemantics: true,
    child: InkWell(
      onTap: () => onChanged(!value),
      customBorder: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
      ),
      child: SizedBox(
        width: 82,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 200),
            width: 74,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: value ? Colors.white : Colors.black,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: Colors.white.withValues(alpha: .35)),
            ),
            child: Text(
              value ? 'ON' : 'OFF',
              style: TextStyle(
                fontFamily: 'Roboto',
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: value ? const Color(0xFF111111) : Colors.white,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Shared action treatment for settings in both menus.
class SettingsAction extends StatelessWidget {
  const SettingsAction({
    super.key,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) => OutlinedButton(
    onPressed: onTap,
    style: OutlinedButton.styleFrom(
      foregroundColor: primary ? const Color(0xFF111111) : Colors.white,
      backgroundColor: primary
          ? Colors.white
          : Colors.white.withValues(alpha: .04),
      minimumSize: const Size(120, 44),
      side: BorderSide(color: Colors.white.withValues(alpha: .35)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
      textStyle: const TextStyle(
        fontFamily: 'Roboto',
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
    child: Text(label),
  );
}
