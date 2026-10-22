import 'package:flutter/material.dart';

import '../config/game_settings.dart';
import '../config/palette.dart';

/// The sound settings, on the main menu and the pause screen: music and all
/// sound (the speaker) on or off, how loud the music, the ambience and the
/// effects are, and which music plays under the game.
class AudioSettings extends StatelessWidget {
  const AudioSettings({super.key, required this.settings, this.onTry});

  final GameSettings settings;

  /// Called with a piece of music as it is picked, to play it at once (the
  /// main menu tries it out over its own music).
  final void Function(String id)? onTry;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: settings,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: _toggle(
                'Music',
                Icons.music_note_outlined,
                settings.musicOn,
                (on) => settings.setFlag('musicOn', on),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _toggle(
                'Sound',
                settings.soundOn
                    ? Icons.volume_up_outlined
                    : Icons.volume_off_outlined,
                settings.soundOn,
                (on) => settings.setFlag('soundOn', on),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SettingSlider(settings: settings, label: 'Music', setting: 'music'),
        SettingSlider(
          settings: settings,
          label: 'Ambience',
          setting: 'ambience',
        ),
        SettingSlider(settings: settings, label: 'Effects', setting: 'effects'),
        const SizedBox(height: 10),
        const Text(
          'MUSIC WHILE PLAYING',
          style: TextStyle(
            color: Palette.brandInk,
            fontSize: 11,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 4),
        for (final (id, title, artist) in GameSettings.playBackgrounds)
          _track(id, title, artist, selected: id == settings.background),
      ],
    ),
  );

  Widget _toggle(
    String label,
    IconData icon,
    bool on,
    ValueChanged<bool> changed,
  ) => Row(
    children: [
      Icon(icon, size: 18, color: on ? Palette.lampAmber : Palette.brandInk),
      const SizedBox(width: 8),
      Text(
        label,
        style: const TextStyle(color: Palette.brandInk, fontSize: 12),
      ),
      const Spacer(),
      Switch(
        value: on,
        onChanged: changed,
        activeThumbColor: Palette.lampAmber,
        activeTrackColor: Palette.lampAmber.withValues(alpha: .35),
        inactiveThumbColor: Palette.brandInk,
        inactiveTrackColor: const Color(0xFF363B3D),
      ),
    ],
  );

  Widget _track(
    String id,
    String title,
    String artist, {
    required bool selected,
  }) => InkWell(
    key: ValueKey('music-$id'),
    onTap: () {
      settings.setBackground(id);
      onTry?.call(id);
    },
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            selected ? Icons.check_circle_outline : Icons.circle_outlined,
            size: 16,
            color: selected ? Palette.lampAmber : const Color(0xFF6E7270),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: title,
                    style: TextStyle(
                      color: selected ? Palette.lampAmber : Palette.brandInk,
                      fontSize: 12,
                    ),
                  ),
                  TextSpan(
                    text: '   $artist',
                    style: const TextStyle(
                      color: Color(0xFF8F938F),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// One setting on a slider, with its value in percent.
class SettingSlider extends StatelessWidget {
  const SettingSlider({
    super.key,
    required this.settings,
    required this.label,
    required this.setting,
    this.min = 0,
    this.max = 1,
  });

  final GameSettings settings;
  final String label, setting;
  final double min, max;

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
                key: ValueKey(setting),
                value: value,
                min: min,
                max: max,
                semanticFormatterCallback: (v) =>
                    '$label ${(v * 100).round()} percent',
                onChanged: (v) => settings.set(setting, v),
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
}
