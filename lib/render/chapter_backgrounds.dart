import '../chapters/campaign_catalog.dart';

/// Four painted locations per chapter, timed to the actual story geography.
/// The atlas is a 2x2 sheet in reading order; it contains background only.
class BackgroundArea {
  const BackgroundArea(this.start, this.name);
  final double start;
  final String name;
}

class ChapterBackground {
  const ChapterBackground(this.number, this.areas);
  final int number;
  final List<BackgroundArea> areas;
  String get asset =>
      'assets/images/backgrounds/${CampaignCatalog.ids[number - 1]}.webp';

  /// Crossfade over eight metres, driven by position (also works backwards).
  /// Outside a transition just one opaque panel is drawn.
  ({int from, int to, double mix}) blendAt(double x) {
    for (var i = 1; i < areas.length; i++) {
      final boundary = areas[i].start;
      if (x < boundary - 4) return (from: i - 1, to: i - 1, mix: 0);
      if (x < boundary + 4) {
        final t = ((x - boundary + 4) / 8).clamp(0.0, 1.0);
        return (from: i - 1, to: i, mix: t * t * (3 - 2 * t));
      }
    }
    return (from: areas.length - 1, to: areas.length - 1, mix: 0);
  }

  /// Existing surface dressing keeps its placement. Only the far scenery
  /// and oversized near-background trees are replaced by the new paintings.
  bool replacesProp(String asset, double depth) =>
      depth < .85 ||
      (depth < 1 &&
          (asset.contains('giant_tree') ||
              asset.contains('orchard_tree') ||
              asset.contains('dead_tree_wind') ||
              asset.contains('clock_face') ||
              asset.contains('cage_child')));
}

abstract final class ChapterBackgrounds {
  static const legacy = [
    ChapterBackground(1, [
      BackgroundArea(0, 'Village edge'),
      BackgroundArea(32, 'Quiet fields'),
      BackgroundArea(56, 'Old orchard'),
      BackgroundArea(96, 'Forest boundary'),
    ]),
    ChapterBackground(2, [
      BackgroundArea(0, 'Old woodland'),
      BackgroundArea(44, 'Hunters ravine'),
      BackgroundArea(94, 'Deep hollow'),
      BackgroundArea(152, 'Graveyard clearing'),
    ]),
    ChapterBackground(3, [
      BackgroundArea(0, 'Holding cavern'),
      BackgroundArea(32, 'Hanging cages'),
      BackgroundArea(52, 'Winch chamber'),
      BackgroundArea(76, 'Low tunnel'),
    ]),
    ChapterBackground(4, [
      BackgroundArea(0, 'Limestone pool'),
      BackgroundArea(52, 'River gorge'),
      BackgroundArea(110, 'Old cistern'),
      BackgroundArea(156, 'Dry ascent'),
    ]),
    ChapterBackground(5, [
      BackgroundArea(0, 'Crypt entrance'),
      BackgroundArea(44, 'Burial gallery'),
      BackgroundArea(88, 'Flooded vault'),
      BackgroundArea(136, 'Ancient passage'),
    ]),
    ChapterBackground(6, [
      BackgroundArea(0, 'Lower cavern'),
      BackgroundArea(44, 'Bone chamber'),
      BackgroundArea(86, 'Flood shaft'),
      BackgroundArea(116, 'Stone throat'),
    ]),
    ChapterBackground(7, [
      BackgroundArea(0, 'Service corridor'),
      BackgroundArea(38, 'Abandoned library'),
      BackgroundArea(66, 'Stair gallery'),
      BackgroundArea(104, 'Escape passage'),
    ]),
    ChapterBackground(8, [
      BackgroundArea(0, 'Vaulted entrance'),
      BackgroundArea(24, 'Shadow gallery'),
      BackgroundArea(48, 'Lift shaft'),
      BackgroundArea(72, 'Upper windows'),
    ]),
    ChapterBackground(9, [
      BackgroundArea(0, 'Ballroom approach'),
      BackgroundArea(34, 'Grand ballroom'),
      BackgroundArea(64, 'Organ gallery'),
      BackgroundArea(100, 'Throne arcade'),
    ]),
    ChapterBackground(10, [
      BackgroundArea(0, 'Pendulum shaft'),
      BackgroundArea(24, 'Striking train'),
      BackgroundArea(44, 'Clock face'),
      BackgroundArea(70, 'Belfry'),
    ]),
    ChapterBackground(11, [
      BackgroundArea(0, 'Cell corridor'),
      BackgroundArea(26, 'Old ward'),
      BackgroundArea(50, 'Service passage'),
      BackgroundArea(78, 'Drain tunnel'),
    ]),
    ChapterBackground(12, [
      BackgroundArea(0, 'Mill race'),
      BackgroundArea(24, 'Wheel chamber'),
      BackgroundArea(46, 'Reservoir'),
      BackgroundArea(78, 'Stone channel'),
    ]),
    ChapterBackground(13, [
      BackgroundArea(0, 'Courtyard'),
      BackgroundArea(22, 'Gatehouse'),
      BackgroundArea(44, 'Moat'),
      BackgroundArea(64, 'Outer wall'),
    ]),
    ChapterBackground(14, [
      BackgroundArea(0, 'Coastal path'),
      BackgroundArea(24, 'Windblown crags'),
      BackgroundArea(46, 'Sea chasm'),
      BackgroundArea(68, 'Exposed ridge'),
    ]),
    ChapterBackground(15, [
      BackgroundArea(0, 'Last woodland'),
      BackgroundArea(36, 'First light'),
      BackgroundArea(76, 'Morning orchard'),
      BackgroundArea(114, 'Homeward fields'),
    ]),
  ];

  static final all = List<ChapterBackground>.generate(40, (i) {
    final old = CampaignCatalog.legacyPositions.indexOf(i + 1);
    return ChapterBackground(i + 1, old >= 0 ? legacy[old].areas : [
      const BackgroundArea(0, 'Arrival'),
      BackgroundArea(40.0 * (i < 10 ? 1 : 2), 'Inner passage'),
      BackgroundArea(80.0 * (i < 10 ? 1 : 2), 'Heart of the chapter'),
      BackgroundArea(120.0 * (i < 10 ? 1 : 2), 'Far boundary'),
    ]);
  });
  static ChapterBackground forChapter(int number) => all[number - 1];
}
