/// Three original silhouettes sharing controller dimensions and joint lengths.
/// The approved hooded character remains option 03 and the default.
enum CharacterPreset {
  scarf('01 · Scarf', 'Short swept hair, narrow tunic and trailing scarf'),
  satchel('02 · Satchel', 'Soft cap, short jacket and a small shoulder bag'),
  raincoat('03 · Raincoat', 'Hooded raincoat and a small lantern');

  const CharacterPreset(this.label, this.description);
  final String label;
  final String description;

  static const defaultPreset = raincoat;
}
