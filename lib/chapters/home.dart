import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/ground.dart';
import '../entities/home_props.dart';
import '../entities/physics_props.dart';
import '../entities/rock.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/cottage.dart';
import '../story/cutscene.dart';
import 'chapter.dart';

/// Chapter one, Home: dusk at the edge of the village.
///
/// The cottage with the lamp lit and the argument in the window; the door
/// thrown open and the boy running out; his mother in the doorway. Then
/// the way out to the forest: the garden with the sheets on the line and
/// a fence, a cart to push against the field wall, the meadow and its
/// ditch with a plank on a post, the old orchard with a tyre swing over a
/// gully, and the hill up to the trees, where he stops and looks back at
/// the one lit window. Dusk falls into night as he goes.
///
/// ```
///  0    7      14   21–26  28.5  31 34.5   40   46.6–51.2   58   66–69.8      100   118 122
///  |  cottage   |  sheets fence cart wall  scarecrow ditch  log  gully+tyre  look back exit
/// ```
class HomeChapter extends Chapter {
  HomeChapter({required super.intent, this.atTitle = false});

  /// Built behind the title screen: the boy is still indoors and nothing
  /// moves until the story begins.
  final bool atTitle;

  @override
  void restoreWorld(double x) {
    player.hidden = false;
    cottage.burstOpen();
  }

  @override
  int get number => 1;
  @override
  String get title => 'Home';
  @override
  double get coreWidth => 122;

  @override
  MoodTrack get moods => const MoodTrack(Mood.dusk, Mood.night, 66, 112);

  /// Open country: trees here and there, not yet the forest.
  @override
  List<FogLayerSpec> get backdropSpecs => FogBackdrop.sparse;

  static const double yard = 7.0;

  @override
  List<List<double>> get baseProfile => const [
    // The yard, the garden and the meadow, to the ditch.
    [
      0, yard, 8, yard, 14, 7.02, 18, 6.96, 24, 7.04, 30, 7.0, //
      34, 6.98, 37, 7.0, 41, 6.92, 44, 6.9, ditchLeft, 6.95,
    ],
    // The orchard, to the gully.
    [ditchRight, 6.95, 54, 6.9, 58, 6.78, 62, 6.85, gullyLeft, 6.9],
    // Up the hill to the forest.
    [
      gullyRight, 6.9, 74, 6.95, 80, 6.72, 86, 6.35, 92, 6.05, //
      98, 5.9, 104, 5.92, 110, 6.0, 116, 6.08, 122, 6.1,
    ],
  ];

  static const double ditchLeft = 46.6, ditchRight = 51.2;
  static const double gullyLeft = 66.0, gullyRight = 69.2;

  @override
  List<double> get coreCheckpointXs => const [16, 37.5, 52.5, 71, 100];

  @override
  Vector2 get spawn =>
      Vector2(cottage.door.center.dx, yard - GameConfig.playerHeight / 2);

  @override
  double get coreExitX => 118.5;

  @override
  List<String> get art => const [
    Cottage.art,
    'part1/ch1_woodpile.png',
    'part1/ch1_well.png',
    'part1/ch1_scarecrow.png',
    'part1/ch1_picket_fence_far.png',
    'part1/ch1_far_village_far.png',
    'part1/ch1_orchard_tree_a.png',
    'part1/ch1_orchard_tree_a_far.png',
    'part1/ch1_orchard_tree_b.png',
    'part1/ch1_orchard_tree_b_far.png',
    'part1/ch2_giant_tree_a.png',
    'part1/ch2_giant_tree_b.png',
    'part1/ch2_giant_tree_c.png',
    'part1/ch2_giant_tree_b_far.png',
  ];

  final Cottage cottage = Cottage(centreX: 7.6, groundY: yard, height: 8.0);

  /// The window still lit, far behind him: seen once he is out in the
  /// orchard, always to his left.
  late final DistantLight homeLight = DistantLight(
    x: 38,
    y: 6.6,
    depth: 0.15,
    showFrom: 52,
    showTo: 62,
  );

  /// The cart and the plank, for tests and scenes.
  late final Cart cart;
  late final Seesaw plank;

  /// Where the camera frames the cottage for the title and the opening.
  static final Vector2 cottageShot = Vector2(9.0, 3.8);

  @override
  Future<void> furnish(List<Component> pieces) async {
    double g(double x) => groundAt(x);

    // --- Far off: the village on its hill, the orchard in the fog -------
    pieces.addAll([
      SceneryProp(
        'part1/ch1_far_village.png',
        x: 40,
        baseY: yard + 2.2,
        height: 7,
        depth: 0.28,
        priority: -90,
      ),
      for (final (x, image, h, flip) in const [
        (56.0, 'a', 7.0, false),
        (63.0, 'b', 8.0, true),
        (72.0, 'a', 6.5, true),
        (80.0, 'b', 7.5, false),
      ])
        SceneryProp(
          'part1/ch1_orchard_tree_$image.png',
          x: x,
          baseY: yard + 0.6,
          height: h,
          depth: 0.5,
          flip: flip,
          priority: -80,
        ),
      SceneryProp(
        'part1/ch1_picket_fence.png',
        x: 25,
        baseY: yard + 0.15,
        height: 1.4,
        depth: 0.72,
        priority: -70,
      ),
      for (final (x, image, h, flip) in const [
        (104.0, 'b', 13.0, false),
        (113.0, 'b', 15.0, true),
      ])
        SceneryProp(
          'part1/ch2_giant_tree_$image.png',
          x: x,
          baseY: yard,
          height: h,
          depth: 0.6,
          flip: flip,
          priority: -75,
        ),
      homeLight,
    ]);

    // --- Close: the yard, the orchard, the forest edge --------------------
    pieces.addAll([
      cottage,
      DoorLight(cottage),
      SceneryProp(
        'part1/ch1_woodpile.png',
        x: 16.2,
        baseY: g(16.2) + 0.12,
        height: 1.15,
        depth: 0.96,
        priority: -5,
      ),
      SceneryProp(
        'part1/ch1_well.png',
        x: 19.0,
        baseY: g(19) + 0.25,
        height: 2.5,
        depth: 0.9,
        priority: -40,
      ),
      SceneryProp(
        'part1/ch1_scarecrow.png',
        x: 41,
        baseY: g(41) + 0.3,
        height: 3.0,
        depth: 0.9,
        priority: -40,
      ),
      for (final (x, image, h, flip) in const [
        (55.0, 'b', 5.5, false),
        (61.5, 'a', 5.2, true),
        (75.0, 'b', 5.8, true),
      ])
        SceneryProp(
          'part1/ch1_orchard_tree_$image.png',
          x: x,
          baseY: groundAt(x) + 0.3,
          height: h,
          depth: 0.88,
          fog: 0.14,
          flip: flip,
          priority: -45,
        ),
      for (final (x, image, h, flip) in const [
        (108.0, 'a', 11.0, false),
        (115.5, 'c', 12.5, true),
        (121.0, 'b', 12.0, false),
      ])
        SceneryProp(
          'part1/ch2_giant_tree_$image.png',
          x: x,
          baseY: groundAt(x) + 0.5,
          height: h,
          depth: 0.97,
          // A step behind the path, so he reads in front of the trunks.
          fog: 0.16,
          flip: flip,
          priority: -30,
        ),
    ]);

    // --- Things to run past, hop, push, climb and swing on ---------------
    cart = Cart(x: 31.2, groundY: g(31.2));
    plank = Seesaw(
      pivot: Vector2((ditchLeft + ditchRight) / 2, 6.95 + Seesaw.thickness / 2),
      length: 4.4,
      postBottom: height,
    );
    pieces.addAll([
      ClothLine(
        left: 21,
        right: 26.5,
        lineY: yard - 1.95,
        groundY: yard,
        player: player,
      ),
      LowFence(x: 28.6, groundY: g(28.6)),
      cart,
      StoneWall(
        left: 34.3,
        right: 36.2,
        top: yard - 2.8,
        bottom: yard + 0.6,
        groundY: g(35.25),
      ),
      plank,
      Ground.restingLog(
        left: 58.2,
        right: 60.4,
        diameter: 0.72,
        groundBelow: groundAt,
      ),
      SwingRope(anchor: Vector2(67.8, 2.5), length: 3.5, tyre: true),
      Rock(left: 83.2, right: 84.0, height: 0.4, groundBelow: groundAt),
      Ground.restingLog(
        left: 93.0,
        right: 94.6,
        diameter: 0.5,
        groundBelow: groundAt,
      ),
    ]);

    // He looks back from the top of the hill at the window still lit.
    onReach(99.5, () => play(_lookBack()));
    // Behind him his mother goes in, and the door swings shut.
    onReach(19.5, () {
      cottage.mother
        ..reach = 0
        ..grief = 0
        ..presence = 0;
      cottage.swingShut();
    });
  }

  @override
  void begin() {
    if (atTitle) {
      // Nothing moves until the story begins: the boy is indoors and the
      // upper window stays lit without visible figures.
      intent.beginScript();
      player.hidden = true;
      cameraFocus = cottageShot.clone();
    }
  }

  @override
  void startStory() {
    if (atTitle) {
      play(_opening());
    }
  }

  /// The argument, the door, his mother.
  Cutscene _opening() => Cutscene([
    Look(cottageShot),
    Wait(3.4),
    Wait(1.1),
    Wait(0.7),
    Do((_) => cottage.burstOpen()),
    Wait(0.16),
    Do((_) {
      player.hidden = false;
    }),
    Together([
      Run(1, toX: 15.2),
      Sequence([
        Wait(0.9),
        Do((_) => cottage.mother.presence = 1),
        Wait(0.5),
        Do((_) => cottage.mother.reach = 1),
      ]),
    ]),
    Wait(0.5),
    Do((_) => player.forceLookBack = true),
    Wait(1.9),
    Do((_) {
      cottage.mother
        ..reach = 0
        ..grief = 1;
    }),
    Wait(0.9),
    Do((_) => player.forceLookBack = false),
    Wait(0.35),
    Look(null),
  ]);

  /// At the top of the hill: he stops, looks back, and goes on.
  Cutscene _lookBack() => Cutscene([
    Wait(0.25),
    Do((_) => player.forceLookBack = true),
    Look(Vector2(player.body.position.x - 3.5, player.body.position.y - 1.2)),
    Wait(2.8),
    Do((_) => player.forceLookBack = false),
    Look(null),
    Wait(0.4),
  ]);
}
