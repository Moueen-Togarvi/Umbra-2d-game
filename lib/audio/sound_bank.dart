// Written by tool/audio/build_sounds.py; do not edit by hand.

/// Every sound the game has, under assets/audio/.
abstract final class SoundBank {
  /// Each one-shot effect and how many takes it has.
  static const Map<String, int> effects = {
    'step_run': 6,
    'step_stone': 6,
    'step_wood': 6,
    'step_water': 6,
    'land': 5,
    'rope': 3,
    'drag': 3,
    'tick': 4,
    'gear': 4,
    'hammer': 3,
    'bell': 3,
    'gate': 3,
    'chain': 4,
    'wood': 4,
    'fire': 3,
    'burn': 2,
    'shriek': 4,
    'thunder': 2,
    'splash': 5,
    'rumble': 3,
    'heartbeat': 2,
    'creak': 4,
    'vampire_step': 3,
    'vampire_cloth': 3,
    'checkpoint': 2,
    'slash': 3,
    'throw': 2,
    'hit': 2,
    'kill': 2,
    'dash': 2,
  };

  /// Effects too long for Android's low-latency pool.
  static const Set<String> long = {'bell', 'heartbeat', 'rumble', 'thunder'};

  /// The loops: the beds under a place.
  static const List<String> loops = [
    'rain',
    'river',
    'cave',
    'dungeon',
    'clockwork',
    'birds',
  ];

  /// Fixed menu, alternating gameplay, and credits music.
  static const String menu = 'bg_distant_sun';
  static const String gameplayTomb = 'bg_tomb';
  static const String gameplayWastelands = 'bg_wastelands';
  static const String ending = 'ending';

  static String effect(String name, int take) =>
      'audio/sfx/${name}_$take.${long.contains(name) ? 'ogg' : 'wav'}';
  static String loop(String name) => 'audio/loops/$name.ogg';
  static String music(String name) => 'audio/music/$name.ogg';
}
