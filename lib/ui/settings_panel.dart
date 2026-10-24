import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../audio/sound_bank.dart';
import '../config/game_settings.dart';
import '../config/palette.dart';

/// The three pages of the settings.
enum SettingsTab { display, controls, sound }

/// The settings, the same on the main menu and the pause screen: three
/// words across the top (Display · Controls · Sound), the one chosen
/// underlined in the lantern's amber, and under it only that page — thin
/// sliders with an amber bead, small pill switches, and on the sound page
/// the music to play under the game. Set right, in the menu's italic.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.unit,
    this.initialTab = SettingsTab.display,
    this.onTry,
    this.width = 470,
  });

  final GameSettings settings;

  /// The screen's size unit (a hundredth of its shorter side).
  final double unit;
  final SettingsTab initialTab;
  final double width;

  /// Called with a piece of music as it is picked, to play it at once.
  final void Function(String id)? onTry;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  late SettingsTab _tab = widget.initialTab;

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
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Smaller rather than cut off on a narrow screen.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final tab in SettingsTab.values)
                    Padding(
                      padding: EdgeInsets.only(left: u * 3.4),
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
            ..._page(settings, u),
          ],
        ),
      ),
    );
  }

  static String _label(SettingsTab tab) => switch (tab) {
    SettingsTab.display => 'Display',
    SettingsTab.controls => 'Controls',
    SettingsTab.sound => 'Sound',
  };

  List<Widget> _page(GameSettings s, double u) => switch (_tab) {
    SettingsTab.display => [
      _SliderRow(s, 'Brightness', 'brightness', u, min: .8, max: 1.3),
      _SliderRow(s, 'Film grain', 'atmosphere', u),
    ],
    SettingsTab.controls => [
      _SliderRow(s, 'Button size', 'controlsScale', u, min: .8, max: 1.3),
      _SliderRow(s, 'Button opacity', 'controlsOpacity', u, min: .3, max: 1),
      _ToggleRow(
        'Vibration',
        s.vibration,
        u,
        (on) => s.setFlag('vibration', on),
        id: 'vibration',
      ),
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
      SizedBox(height: u * 1.6),
      _Caption('While playing', u),
      SizedBox(height: u * 0.6),
      for (final (id, title, artist) in SoundBank.backgrounds)
        _Track(
          key: ValueKey('music-$id'),
          title: title,
          artist: artist,
          chosen: id == s.background,
          unit: u,
          onTap: () {
            s.setBackground(id);
            widget.onTry?.call(id);
          },
        ),
    ],
  };
}

TextStyle _italic(double size, Color color) => TextStyle(
  fontFamily: 'Cormorant',
  fontStyle: FontStyle.italic,
  fontSize: size,
  height: 1.15,
  color: color,
);

const Color _dim = Color(0x61D8D4CC);

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
      customBorder: const StadiumBorder(),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: _italic(
                (unit * 4.2).clamp(18, 34),
                chosen ? Palette.brandInk : _dim,
              ),
            ),
            SizedBox(height: unit * 0.8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              height: 1,
              width: chosen ? unit * 9 : 0,
              color: Palette.lampAmber.withValues(alpha: .85),
            ),
          ],
        ),
      ),
    ),
  );
}

class _Caption extends StatelessWidget {
  const _Caption(this.text, this.unit);
  final String text;
  final double unit;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: TextStyle(
      fontFamily: 'Cinzel',
      fontSize: (unit * 1.5).clamp(9, 12),
      letterSpacing: unit * 0.55,
      color: Palette.lampAmber.withValues(alpha: .75),
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
            child: Text(
              label,
              textAlign: TextAlign.right,
              maxLines: 1,
              style: _italic(
                (unit * 3.6).clamp(16, 28),
                Palette.brandInk.withValues(alpha: .92),
              ),
            ),
          ),
          SizedBox(width: unit * 3.2),
          SizedBox(
            width: (unit * 36).clamp(150, 300),
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
            width: unit * 6,
            child: Text(
              '${(value * 100).round()}',
              textAlign: TextAlign.right,
              style: TextStyle(
                fontFamily: 'Cinzel',
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
  });
  final String label, id;
  final bool on;
  final double unit;
  final ValueChanged<bool> changed;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: (unit * 7.6).clamp(44, 64),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          label,
          style: _italic(
            (unit * 3.6).clamp(16, 28),
            Palette.brandInk.withValues(alpha: .92),
          ),
        ),
        SizedBox(width: unit * 3.2),
        PillToggle(
          key: ValueKey('toggle-$id'),
          value: on,
          label: label,
          onChanged: changed,
        ),
        SizedBox(width: unit * 6),
      ],
    ),
  );
}

class _Track extends StatelessWidget {
  const _Track({
    super.key,
    required this.title,
    required this.artist,
    required this.chosen,
    required this.unit,
    required this.onTap,
  });
  final String title, artist;
  final bool chosen;
  final double unit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    selected: chosen,
    label: '$title by $artist',
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _italic(
                  (unit * 3.1).clamp(14, 24),
                  chosen ? Palette.lampAmber : _dim,
                ),
              ),
            ),
            SizedBox(width: unit * 1.6),
            Text(
              artist.toUpperCase(),
              style: TextStyle(
                fontFamily: 'Cinzel',
                fontSize: (unit * 1.3).clamp(8, 11),
                letterSpacing: 1.6,
                color: const Color(0x4DD8D4CC),
              ),
            ),
            SizedBox(width: unit * 1.6),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: chosen ? Palette.lampAmber : Colors.transparent,
                boxShadow: chosen
                    ? const [BoxShadow(color: Palette.lampAmber, blurRadius: 8)]
                    : null,
              ),
            ),
            SizedBox(width: unit * 6 - 6),
          ],
        ),
      ),
    ),
  );
}

/// A slider drawn as a hairline with an amber bead: dragged, tapped, or
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
        ..color = const Color(0x38D8D4CC)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(0, y),
      Offset(x, y),
      Paint()
        ..color = const Color(0xD9D8D4CC)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(
      Offset(x, y),
      lit ? 11 : 8,
      Paint()
        ..color = Palette.lampAmber.withValues(alpha: lit ? .32 : .22)
        ..maskFilter = const MaskFilter.blur(ui.BlurStyle.normal, 6),
    );
    canvas.drawCircle(
      Offset(x, y),
      lit ? 6.5 : 5.5,
      Paint()..color = Palette.lampAmber,
    );
  }

  @override
  bool shouldRepaint(covariant _ThinSliderPainter old) =>
      old.t != t || old.lit != lit;
}

/// An on/off switch: a hairline pill with a bead, amber and to the right
/// when on.
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
      customBorder: const StadiumBorder(),
      child: SizedBox(
        width: 56,
        height: 44,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 46,
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: value
                    ? Palette.lampAmber.withValues(alpha: .8)
                    : const Color(0x59D8D4CC),
              ),
            ),
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Palette.lampAmber : const Color(0x8CD8D4CC),
                boxShadow: value
                    ? const [
                        BoxShadow(color: Color(0x99E8A84A), blurRadius: 10),
                      ]
                    : null,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
