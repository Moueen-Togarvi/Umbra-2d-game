import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../entities/home_props.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../render/weather.dart';
import '../story/cottage.dart';
import '../story/cutscene.dart';
import '../story/hunters.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter fifteen, Dawn.
///
/// Down off the cliffs into open country, the night going grey. Two of
/// them come out of the trees behind him for the last time, and he runs,
/// over a fence, over a ditch; then the sun comes up over the hills
/// ahead, and its light sweeps across the fields towards him, over him,
/// and on to them, and they burn. The rest is the walk home in the
/// morning: the orchard, the village, the cottage with its lamp still lit,
/// his mother in the door. She holds him. And in the last moment, as she
/// does, his eyes catch the light: red.
///
/// ```
///  0  14 them  40 sunrise  50 fence  58–59.3 ditch  70–130 home
///  138 the cottage
/// ```
class DawnChapter extends Chapter {
  DawnChapter({required super.intent});

  /// The birds start once the sun is up.
  @override
  String? get ambience => isLoaded && sun.rising ? 'birds' : null;

  @override
  int get number => 15;
  @override
  String get title => 'Dawn';
  @override
  double get width => 150;
  @override
  MoodTrack get moods => const MoodTrack(Mood.night, Mood.dawn, 30, 100);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.sparse;

  static const double ditchLeft = 58, ditchRight = 59.3;

  @override
  List<List<double>> get profile => const [
    [0, 6.6, 12, 6.8, 24, 7.0, 36, 7.1, 48, 7.0, ditchLeft, 7.0],
    [ditchRight, 7.0, 70, 6.9, 84, 7.0, 100, 7.1, 120, 7.0, 150, 7.0],
  ];

  @override
  List<double> get checkpointXs => const [8, 30, 62, 100];

  @override
  Vector2 get spawn => Vector2(3, 6.6 - GameConfig.playerHeight / 2);

  @override
  double get exitX => 149;

  @override
  List<String> get art => const [
    Cottage.art,
    'part4/ch15_windmill.png',
    'part4/ch15_windmill_far.png',
    'part4/ch15_village_far.png',
    'part4/ch15_village_far_far.png',
    'part1/ch1_orchard_tree_a.png',
    'part1/ch1_orchard_tree_a_far.png',
    'part1/ch1_orchard_tree_b.png',
    'part1/ch1_orchard_tree_b_far.png',
    'part1/ch2_giant_tree_a.png',
    'part1/ch2_giant_tree_a_far.png',
  ];

  late final Sunrise sun;
  late final Cottage cottage = Cottage(centreX: 141, groundY: 7.0, height: 8.0);
  final List<Vampire> last = [
    Vampire(x: 6, groundY: 6.7, facing: 1),
    Vampire(x: 3.5, groundY: 6.6, facing: 1),
  ];
  late final List<Pursuer> _hunt = [
    for (final v in last)
      Pursuer(v, stage: this, speed: 2.75, burnsInLight: true),
  ];
  bool _home = false;

  /// Set once his eyes have gone red, at the very end.
  bool redEyes = false;

  @override
  Future<void> furnish(List<Component> pieces) async {
    sun = Sunrise(edge: 175, speed: 7);
    pieces.addAll([
      SceneryProp(
        'part1/ch2_giant_tree_a.png',
        x: 4,
        baseY: 7.0,
        height: 8,
        depth: 0.95,
        fog: 0.08,
        priority: -30,
      ),
      SceneryProp(
        'part4/ch15_windmill.png',
        x: 96,
        baseY: 7.6,
        height: 7,
        depth: 0.45,
      ),
      SceneryProp(
        'part4/ch15_village_far.png',
        x: 118,
        baseY: 7.6,
        height: 3.2,
        depth: 0.3,
      ),
      for (final (double x, bool b) in const [
        (84.0, false),
        (104.0, true),
        (122.0, false),
      ])
        SceneryProp(
          b ? 'part1/ch1_orchard_tree_b.png' : 'part1/ch1_orchard_tree_a.png',
          x: x,
          baseY: groundAt(x) + 0.2,
          height: 5,
          depth: 0.93,
          fog: 0.1,
          priority: -30,
        ),
      LowFence(x: 50, groundY: groundAt(50)),
      cottage,
      sun,
      for (final v in last) v..gone = true,
    ]);
  }

  @override
  void begin() {
    onReach(14, () {
      for (var i = 0; i < last.length; i++) {
        last[i]
          ..revive()
          ..x = i == 0 ? 6 : 3.5
          ..groundY = groundAt(i == 0 ? 6 : 3.5)
          ..facing = 1
          ..eyes = 1;
        _hunt[i].start();
      }
    });
    onReach(40, () => sun.rising = true);
    onReach(cottage.door.center.dx - 7, () => play(_homecoming()));
  }

  /// Home: his mother in the door, holding him; and his eyes.
  Cutscene _homecoming() => Cutscene([
    Do((_) => cottage.burstOpen()),
    Together([
      Run(1, toX: cottage.door.center.dx - 0.35),
      Sequence([
        Wait(1.0),
        Do((_) => cottage.mother.presence = 1),
        Wait(0.6),
        Do((_) => cottage.mother.reach = 1),
      ]),
    ]),
    Look(Vector2(cottage.door.center.dx, cottage.door.bottom - 1.6)),
    Wait(2.8),
    Do((_) => _home = true),
    // As she holds him: closer, on his face, in the morning light.
    Do((_) => cameraZoom = 3.2),
    Look(Vector2(cottage.door.center.dx - 0.3, cottage.door.bottom - 1.15)),
    Wait(2.2),
    Do((_) {
      redEyes = true;
      player
        ..eyeColor = Palette.vampireRed
        ..eyeGlow = 3;
      cue('heartbeat');
    }),
    Wait(0.7),
    Do((_) => cue('heartbeat', weight: 0.8)),
    Wait(1.4),
    Fade(1, 1.4),
    Do((_) => complete()),
  ]);

  /// Whether he is home.
  bool get home => _home;

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted) return;
    for (final h in _hunt) {
      h.update(dt);
    }
  }

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (sun.rising) return;
    for (var i = 0; i < last.length; i++) {
      if (last[i].gone) continue;
      final double from = at - 8 - i * 2.5;
      last[i]
        ..revive()
        ..x = from
        ..groundY = groundAt(from)
        ..facing = 1;
      _hunt[i].start();
    }
  }
}
