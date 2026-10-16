import 'dart:ui';

import '../config/palette.dart';

/// The light and air of a place: what the fog behind the world looks like.
///
/// Every stage has one. The fog backdrop reads it for the sky, the tone of
/// each depth layer, the light shining through the fog (a low dusk sun, the
/// moon, a hole in a cave roof) and how much mist and dust hang in the air.
/// The only colour any mood carries is the faintest warmth or chill in its
/// light; the lamp's amber and the vampires' red belong to things, not to
/// the air.
class Mood {
  const Mood({
    required this.name,
    required this.sky,
    required this.layerTones,
    this.light = const Color(0xFFFFFFFF),
    required this.lightAt,
    this.lightDrift = 0.12,
    required this.lightSize,
    this.lightStrength = 1,
    this.moon = false,
    this.shafts = 1,
    this.shaftTilt = 0.04,
    this.shaftFan = 0.34,
    this.mist = 1,
    this.mistTone = const Color(0xFFB4B4B4),
    this.dust = 1,
    this.drips = false,
    this.trees = true,
  });

  final String name;

  /// Top to bottom of the screen, at stops 0, 0.32, 0.6 and 1.
  final List<Color> sky;

  /// The four depth layers, far to near.
  final List<Color> layerTones;

  /// The light in the fog: its tint, where it sits on screen (fractions of
  /// width and height), how far it drifts sideways as the camera travels,
  /// its radius (a fraction of width) and its strength.
  final Color light;
  final Offset lightAt;
  final double lightDrift;
  final double lightSize;
  final double lightStrength;

  /// A pale disc at the light's centre.
  final bool moon;

  /// The beams falling from the light: strength, the angle of the middle
  /// one (radians from straight down) and the angle between neighbours.
  final double shafts, shaftTilt, shaftFan;

  /// Ground mist lying along each layer's ground line: strength and tone.
  final double mist;
  final Color mistTone;

  /// Dust drifting in the light, and whether specks fall as water drips.
  final double dust;
  final bool drips;

  /// Whether a forest stands in the fog. A cave has rock instead.
  final bool trees;

  static const List<double> skyStops = [0.0, 0.32, 0.6, 1.0];

  /// The grey forest the game was built in: no time of day at all.
  static const fog = Mood(
    name: 'fog',
    sky: [
      Color(0xFF3E3E3E),
      Color(0xFF9C9C9C),
      Color(0xFFB8B8B8),
      Color(0xFF8E8E8E),
    ],
    layerTones: [
      Color(0xFFA6A6A6),
      Color(0xFF7E7E7E),
      Color(0xFF4A4A4A),
      Color(0xFF202020),
    ],
    lightAt: Offset(0.56, 0.24),
    lightSize: 0.62,
  );

  /// Late evening at the edge of the forest: the fog a touch warm, the sun
  /// low and large behind it.
  static const dusk = Mood(
    name: 'dusk',
    sky: [
      Color(0xFF3B3936),
      Color(0xFF9D9891),
      Color(0xFFC2BAAE),
      Color(0xFF8F8A83),
    ],
    layerTones: [
      Color(0xFFAAA49B),
      Color(0xFF817B74),
      Color(0xFF4C4844),
      Color(0xFF211F1D),
    ],
    light: Palette.duskLight,
    lightAt: Offset(0.6, 0.5),
    lightDrift: 0.06,
    lightSize: 0.78,
    lightStrength: 1.1,
    shafts: 0.8,
    shaftTilt: 0.1,
    shaftFan: 0.42,
    mistTone: Color(0xFFBCB4A8),
    dust: 0.9,
  );

  /// Night in the forest: dark cold fog, a pale moon high up, thin mist.
  static const night = Mood(
    name: 'night',
    sky: [
      Color(0xFF101114),
      Color(0xFF3E4148),
      Color(0xFF5E626A),
      Color(0xFF2F3137),
    ],
    layerTones: [
      Color(0xFF61646B),
      Color(0xFF41444A),
      Color(0xFF25272C),
      Color(0xFF0E0F11),
    ],
    light: Palette.moonLight,
    lightAt: Offset(0.7, 0.17),
    lightDrift: 0.05,
    lightSize: 0.46,
    lightStrength: 0.75,
    moon: true,
    shafts: 0.55,
    mist: 0.55,
    mistTone: Color(0xFF6C7078),
    dust: 0.45,
  );

  /// Deep in the rock: nearly black, one pale shaft of moonlight falling
  /// from a hole in the roof, and water dripping through it.
  static const cave = Mood(
    name: 'cave',
    sky: [
      Color(0xFF070708),
      Color(0xFF1C1D20),
      Color(0xFF292A2E),
      Color(0xFF0C0C0D),
    ],
    layerTones: [
      Color(0xFF34363A),
      Color(0xFF232427),
      Color(0xFF141416),
      Color(0xFF070707),
    ],
    light: Palette.moonLight,
    lightAt: Offset(0.46, -0.04),
    lightDrift: 0.0,
    lightSize: 0.34,
    lightStrength: 0.8,
    shafts: 2.2,
    shaftTilt: 0.0,
    shaftFan: 0.09,
    mist: 0.3,
    mistTone: Color(0xFF3A3C40),
    dust: 1.3,
    drips: true,
    trees: false,
  );

  /// Inside the castle at night: dark stone halls, the moon slanting in
  /// through high windows, a little dust in its beams.
  static const castle = Mood(
    name: 'castle',
    sky: [
      Color(0xFF0A0B0D),
      Color(0xFF25272C),
      Color(0xFF34373D),
      Color(0xFF101113),
    ],
    layerTones: [
      Color(0xFF3E4146),
      Color(0xFF2A2C30),
      Color(0xFF17181A),
      Color(0xFF080808),
    ],
    light: Palette.moonLight,
    lightAt: Offset(0.28, -0.06),
    lightDrift: 0.03,
    lightSize: 0.42,
    lightStrength: 0.85,
    shafts: 1.5,
    shaftTilt: 0.3,
    shaftFan: 0.16,
    mist: 0.25,
    mistTone: Color(0xFF3C3F44),
    dust: 1.0,
    trees: false,
  );

  /// This mood blended towards [other] by [t] (0 is this one). Switches
  /// (the moon, drips, trees) follow whichever is nearer.
  Mood lerp(Mood other, double t) {
    if (t <= 0) return this;
    if (t >= 1) return other;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    double num(double a, double b) => a + (b - a) * t;
    final near = t < 0.5 ? this : other;
    return Mood(
      name: near.name,
      sky: [for (var i = 0; i < 4; i++) mix(sky[i], other.sky[i])],
      layerTones: [
        for (var i = 0; i < 4; i++) mix(layerTones[i], other.layerTones[i]),
      ],
      light: mix(light, other.light),
      lightAt: Offset.lerp(lightAt, other.lightAt, t)!,
      lightDrift: num(lightDrift, other.lightDrift),
      lightSize: num(lightSize, other.lightSize),
      lightStrength: num(lightStrength, other.lightStrength),
      moon: near.moon,
      shafts: num(shafts, other.shafts),
      shaftTilt: num(shaftTilt, other.shaftTilt),
      shaftFan: num(shaftFan, other.shaftFan),
      mist: num(mist, other.mist),
      mistTone: mix(mistTone, other.mistTone),
      dust: num(dust, other.dust),
      drips: near.drips,
      trees: near.trees,
    );
  }
}

/// Where a stage's mood comes from as the camera travels: one mood
/// throughout, or a blend from one to another between two x positions
/// (dusk falling into night across Chapter 1).
class MoodTrack {
  const MoodTrack(this.from, [Mood? to, this.start = 0, this.end = 1])
    : to = to ?? from;

  final Mood from, to;
  final double start, end;

  Mood at(double x) {
    if (identical(from, to)) return from;
    final double t = ((x - start) / (end - start)).clamp(0.0, 1.0);
    // Smoothstep, so the change has no visible start or finish.
    return from.lerp(to, t * t * (3 - 2 * t));
  }
}
