import 'dart:math' as math;

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/hazard.dart';
import '../entities/outdoor_props.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../render/weather.dart';
import '../story/hunters.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter fourteen, The Storm.
///
/// Over the drawbridge and up onto the cliffs, the keeper still behind
/// him, in a storm off the sea. Rain drives across, the wind shoves at
/// him, and every few seconds lightning turns everything white: for that
/// moment the keeper cannot move. Stones break loose higher up the path
/// and come bounding down it. A bridge of planks on ropes over a chasm,
/// bucking in the wind; as he steps off it, lightning takes its far post,
/// and it goes down into the dark, with the keeper if he is on it.
///
/// ```
///  0  20–40 the climb, stones from 44  47–59 the rope bridge
///  60–80 the ridge  86 out
/// ```
class StormChapter extends Chapter with KeeperChase {
  StormChapter({required super.intent});

  @override
  void restoreWorld(double x) {
    if (x < chasmRight) {
      chasing = true;
      stones.active = x >= 20;
    } else {
      bridge.snap();
      stones.stop();
      endChase();
    }
  }

  @override
  String? get ambience => 'rain';
  @override
  int get number => 35;
  @override
  String get title => 'The Storm';
  @override
  double get coreWidth => 92;
  @override
  MoodTrack get moods => const MoodTrack(Mood.storm);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.sparse;

  static const double chasmLeft = 47, chasmRight = 59;
  static const double ledge = 5.5;

  @override
  List<List<double>> get baseProfile => const [
    [0, 7.0, 10, 7.0, 20, 7.0, 30, 6.3, 40, ledge, chasmLeft, ledge],
    [chasmRight, ledge, 70, 5.3, 80, 5.0, 92, 5.0],
  ];

  @override
  List<double> get coreCheckpointXs => const [8, 20, 44, 62];

  @override
  Vector2 get spawn => Vector2(4, 7.0 - GameConfig.playerHeight / 2);

  @override
  double get coreExitX => 86;

  @override
  List<String> get art => const [
    'part4/ch14_cliff_rocks.png',
    'part4/ch14_cliff_rocks_far.png',
    'part4/ch14_dead_tree_wind.png',
    'part4/ch14_dead_tree_wind_far.png',
    'part4/ch14_ruined_tower.png',
    'part4/ch14_ruined_tower_far.png',
  ];

  late final Lightning lightning;
  late final Rain rain;
  late final RockFall stones;
  late final RopeBridge bridge;
  final Vampire keeper = Vampire(x: -2, groundY: 7.0, facing: 1);
  @override
  late final Pursuer pursuer = Pursuer(keeper, stage: this);
  double _gust = 0, _gustClock = 0;
  bool _struck = false;

  /// How hard the wind is pushing now, newtons (towards the left).
  double get gust => _gust;

  @override
  List<Component> buildPit(int index, double left, double right, double lip) =>
      [
        Hazard.zone(
          left: left,
          right: right,
          top: lip + GameConfig.pitDepth + 2,
          bottom: height,
          stakes: false,
        ),
      ];

  @override
  Future<void> furnish(List<Component> pieces) async {
    lightning = Lightning();
    rain = Rain();
    // Stones break loose at the top of the climb and roll down it at him.
    stones = RockFall(from: Vector2(46.2, ledge - 0.6))..active = true;
    bridge = RopeBridge(
      from: Vector2(chasmLeft, ledge),
      to: Vector2(chasmRight, ledge),
      planks: 18,
    );
    pieces.addAll([
      for (final (double x, double depth, double h) in const [
        (12.0, 0.55, 5.5),
        (52.0, 0.5, 6.5),
        (84.0, 0.55, 5.5),
      ])
        SceneryProp(
          'part4/ch14_cliff_rocks.png',
          x: x,
          baseY: 7.8,
          height: h,
          depth: depth,
        ),
      SceneryProp(
        'part4/ch14_ruined_tower.png',
        x: 70,
        baseY: 7.6,
        height: 9,
        depth: 0.45,
      ),
      for (final (double x, double h) in const [(26.0, 5.0), (66.0, 5.5)])
        SceneryProp(
          'part4/ch14_dead_tree_wind.png',
          x: x,
          baseY: groundAt(x) + 0.2,
          height: h,
          depth: 0.92,
          fog: 0.12,
          priority: -30,
        ),
      stones,
      bridge,
      keeper..gone = true,
      lightning,
      rain,
    ]);
  }

  @override
  void begin() {
    // Once he is on his way, the keeper comes on out of the dark behind,
    // still after him.
    onReach(5.5, () {
      keeper
        ..revive()
        ..x = 0.6
        ..groundY = 7.0
        ..facing = 1
        ..eyes = 1;
      startChase();
    });
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted) return;
    updateChase(dt);
    // No new stones once he is up at the top where they break loose.
    if (!_struck) stones.active = player.body.position.x < 41;
    // The wind: gusts off the sea every few seconds, pushing him back.
    _gustClock += dt;
    final double phase = _gustClock % 6.5;
    _gust = phase > 4.5 ? 140 * math.sin((phase - 4.5) / 2 * math.pi) : 0;
    rain.slant = -0.3 - _gust / 300;
    if (!player.isDead && _gust > 0) {
      player.body.applyForce(Vector2(-_gust, 0));
    }
    // Off the bridge: the lightning takes its far post.
    if (!_struck && player.body.position.x > chasmRight + 1.2) {
      _struck = true;
      lightning.strikeAt(Vector2(chasmRight, ledge - 1));
      bridge.snap();
      stones.stop();
    }
    if (_struck &&
        !keeper.gone &&
        keeper.x > chasmLeft &&
        keeper.x < chasmRight) {
      // Down with it into the chasm.
      endChase();
    }
  }

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (at < chasmRight && (chasing || pursuer.caught)) {
      final double from = at - 8;
      keeperBehind(from, groundAt(from));
    }
  }
}
