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
  };

  /// Effects too long for Android's low-latency pool.
  static const Set<String> long = {'bell', 'heartbeat', 'rumble', 'thunder'};

  /// The loops: the wind and the beds under it.
  static const List<String> loops = [
    'wind',
    'rain',
    'river',
    'cave',
    'dungeon',
    'clockwork',
    'birds',
  ];

  /// The music the player can pick to play under the game: id, title and
  /// who made it.
  static const List<(String, String, String)> backgrounds = [
    ('bg_tragic', 'Tragic ambient main menu', 'HaelDB'),
    ('bg_decoherence', 'Decoherence', 'Scott Buckley'),
    ('bg_descent', 'Descent', 'Scott Buckley'),
    ('bg_solitude', 'In Search Of Solitude', 'Scott Buckley'),
    ('bg_distant_sun', 'The Distant Sun', 'Scott Buckley'),
    ('bg_creepy_forest', 'Creepy Forest', 'HaelDB'),
    ('bg_wastelands', 'Post Apocalyptic Wastelands', 'Juhani Junkala'),
    ('bg_tomb', 'Forgotten tomb ambience', 'kindland'),
    ('bg_overshadow', 'Overshadow', 'cinameng'),
  ];

  /// The fixed music: on the main menu, in a chase, under the credits.
  static const String menu = 'bg_tragic', chase = 'chase', ending = 'ending';

  static String effect(String name, int take) =>
      'audio/sfx/${name}_$take.${long.contains(name) ? 'ogg' : 'wav'}';
  static String loop(String name) => 'audio/loops/$name.ogg';
  static String music(String name) => 'audio/music/$name.ogg';
}
