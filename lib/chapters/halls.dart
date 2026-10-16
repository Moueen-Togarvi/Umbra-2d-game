import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/castle_props.dart';
import '../entities/physics_props.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/cutscene.dart';
import '../story/hunters.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter eight, The Halls.
///
/// The castle proper, where the vampires keep to the dark. Under the one
/// open window the boy learns the rule: one of them comes for him, stops
/// at the edge of the moonlight, shields its face and backs away. A
/// lantern on a cart, pushed down a black corridor, drives the next one
/// before it until it has nowhere left to go, and it burns. A lift on a
/// counterweight, held down by the chest on it: he gets on, shoves the
/// chest off, and the counterweight carries him up. Last, a gallery of
/// shuttered windows with one of them pacing it. Each shutter's cord hangs
/// in the light of the one before; window by window the moon drives it to
/// the end of the gallery, and there it burns.
///
/// ```
///  0  W0 at 8.5  15.5 the cart  20–47.6 the corridor  48–54 the wall
///  58–60.8 the lift  61 the gallery  64.5–76.3 four windows  96 out
/// ```
class HallsChapter extends Chapter {
  HallsChapter({required super.intent});

  @override
  int get number => 8;
  @override
  String get title => 'The Halls';
  @override
  double get width => 104;
  @override
  MoodTrack get moods => const MoodTrack(Mood.castle);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.hallSpecs;
  @override
  bool get grassy => false;

  static const double floor = 7.0;
  static const double wallLeft = 48, wallTop = 4.2, wallRight = 54;
  static const double liftX = 59.4, gallery = 3.6, galleryLeft = 61;
  static const double firstLight = 64.5;
  static const double doorway = 76.6;

  @override
  List<List<double>> get profile => const [
    [0, floor, 104, floor],
  ];

  @override
  List<double> get checkpointXs => const [14, 46, 55, 62, 78];

  @override
  Vector2 get spawn => Vector2(3, floor - GameConfig.playerHeight / 2);

  @override
  double get exitX => 96;

  @override
  List<String> get art => const [
    'part3/ch8_gothic_window.png',
    'part3/ch8_suit_of_armour.png',
    'part3/ch8_suit_of_armour_far.png',
    'part3/ch8_banners.png',
    'part3/ch8_vaulted_hall.png',
    'part3/ch8_vaulted_hall_far.png',
    'part3/ch8_long_table.png',
    'part3/ch9_far_chandelier.png',
  ];

  late final MoonWindow intro;
  late final LanternCart cart;
  late final LiftPlatform lift;
  late final Counterweight counterweight;
  late final PhysicsCrate chest;
  final List<MoonWindow> windows = [];
  final List<PullCord> cords = [];

  final Vampire visitor = Vampire(x: 22, groundY: floor, facing: -1);
  final Vampire corridor = Vampire(x: 34, groundY: floor, facing: -1);
  final Vampire keeper = Vampire(x: 73, groundY: gallery, facing: -1);
  late final Stalker corridorHunt, galleryHunt;
  double _stuck = 0;

  /// The floor under x for the vampires: the hall, or the gallery.
  double _ground(double x) => x >= galleryLeft ? gallery : floor;

  /// A shuttered gothic window in the wall over [floorY], [above] metres
  /// up, placed so that its light falls on the floor from [lightLeft]:
  /// its wall, its art, and its light.
  MoonWindow _window(
    List<Component> pieces,
    double lightLeft,
    double floorY, {
    double above = 2.0,
    bool open = false,
  }) {
    const double h = 4.6;
    const double w = h * 443 / 808;
    const double slant = 0.6;
    final double baseY = floorY - above;
    final double top = baseY - h;
    final double paneBottom = top + 0.855 * h;
    final double paneLeft = lightLeft - slant * (floorY - paneBottom);
    final double artLeft = paneLeft - 0.2009 * w;
    pieces.addAll([
      // The wall it is set in, a little wider than the window.
      StoneBlock(
        left: artLeft - 0.5,
        top: top - 2,
        right: artLeft + w + 0.5,
        bottom: baseY - 0.02,
        seed: (paneLeft * 10).round(),
        solid: false,
        priority: -37,
      ),
      // Over the light drawn behind it, which shows through its panes.
      SceneryProp(
        'part3/ch8_gothic_window.png',
        x: artLeft + w / 2,
        baseY: baseY,
        height: h,
        priority: -34,
      ),
    ]);
    final window = MoonWindow(
      paneLeft: paneLeft,
      paneRight: artLeft + 0.799 * w,
      paneTop: top + 0.3366 * h,
      paneBottom: paneBottom,
      floorY: floorY,
      slant: slant,
      open: open,
    );
    pieces.add(window);
    return window;
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    pieces.add(LightLayer());
    // --- Stone: vaults, the corridor's end wall, the gallery --------------
    pieces.addAll([
      StoneBlock(left: -3, top: -6, right: wallRight, bottom: 0.4, seed: 21),
      StoneBlock(left: wallRight, top: -6, right: 107, bottom: -3.4, seed: 22),
      StoneBlock(
        left: wallLeft,
        top: wallTop,
        right: wallRight,
        bottom: floor + 0.05,
        seed: 23,
      ),
      // Above the wall, up to the vault.
      StoneBlock(
        left: wallLeft,
        top: 0.4,
        right: wallRight,
        bottom: 1.4,
        seed: 24,
      ),
      StoneBlock(
        left: galleryLeft,
        top: gallery,
        right: 107,
        bottom: gallery + 0.6,
        seed: 25,
      ),
      // Under the gallery, a cellar where the chest falls: walled off.
      StoneBlock(
        left: 64.5,
        top: gallery + 0.6,
        right: 107,
        bottom: floor + 0.05,
        seed: 27,
      ),
      // The doorway out of the gallery.
      StoneBlock(
        left: doorway,
        top: -3.4,
        right: doorway + 0.7,
        bottom: 0.8,
        seed: 26,
      ),
    ]);

    // --- Art ---------------------------------------------------------------
    pieces.addAll([
      for (final x in const [30.0, 70.0])
        SceneryProp(
          'part3/ch8_vaulted_hall.png',
          x: x,
          baseY: 7.8,
          height: 7.5,
          depth: 0.55,
        ),
      for (final (double x, bool flip) in const [
        (5.0, false),
        (44.0, true),
        (88.0, false),
      ])
        SceneryProp(
          'part3/ch8_suit_of_armour.png',
          x: x,
          baseY: x > 60 ? gallery + 0.1 : floor + 0.1,
          height: 2.4,
          depth: 0.94,
          fog: 0.12,
          flip: flip,
          priority: -32,
        ),
      for (final x in const [17.0, 39.0, 84.0])
        SceneryProp(
          'part3/ch8_banners.png',
          x: x,
          baseY: x > 60 ? gallery - 1.4 : 4.0,
          height: 3.0,
          depth: 0.9,
          fog: 0.12,
          priority: -35,
        ),
      SceneryProp(
        'part3/ch8_long_table.png',
        x: 66,
        baseY: floor + 0.1,
        height: 1.4,
        depth: 0.9,
        fog: 0.12,
        priority: -35,
      ),
    ]);

    // --- The rule: the open window --------------------------------------------
    intro = _window(pieces, 8.4, floor, open: true);

    // --- The corridor and the lantern --------------------------------------
    cart = LanternCart(x: 15.5, groundY: floor);
    corridorHunt = Stalker(
      corridor,
      stage: this,
      ground: _ground,
      left: 12,
      right: wallLeft - 0.4,
      wake: 7,
      patrolA: 28,
      patrolB: 40,
    );
    pieces.addAll([cart, visitor..gone = true, corridor]);

    // --- The lift --------------------------------------------------------------
    lift = LiftPlatform(
      position: Vector2(liftX, floor - 0.12),
      rise: floor - 0.24 - gallery,
    );
    counterweight = Counterweight(
      position: Vector2(56.6, 0.9),
      massKg: 65,
      rise: 0,
      drop: floor - 0.24 - gallery,
    );
    chest = PhysicsCrate(
      position: Vector2(liftX + 0.75, floor - 0.24 - 0.5),
      size: Vector2(1, 1),
      massKg: 50,
    );
    pieces.addAll([
      lift,
      counterweight,
      Pulley(a: lift, b: counterweight, wheelY: -0.4),
      chest,
    ]);

    // --- The gallery of windows ---------------------------------------------
    const double span = 2.94;
    for (var k = 0; k < 4; k++) {
      final MoonWindow window = _window(
        pieces,
        firstLight + span * k,
        gallery,
        above: 1.4,
      );
      windows.add(window);
      final (double l, double r) = window.floorSpan;
      // The first cord hangs in the dark before the gallery's first
      // window; each of the others in the light of the one before.
      final double cordX = k == 0 ? l - 1.1 : l - span / 2 + 0.25;
      final cord = PullCord(
        anchor: Vector2(cordX, gallery - 4.5),
        length: 3.6,
        onPulled: window.open,
      );
      cords.add(cord);
      assert(r > l);
    }
    pieces.addAll(cords);
    galleryHunt = Stalker(
      keeper,
      stage: this,
      ground: _ground,
      left: galleryLeft + 0.6,
      right: windows.last.floorSpan.$2 - 0.4,
      wake: 5,
      patrolA: 70,
      patrolB: 75,
    );
    pieces.add(keeper);
  }

  @override
  void begin() {
    onReach(intro.floorSpan.$1 + 0.7, () => play(_rule()));
  }

  /// Under the open window: one of them comes, and cannot come further.
  Cutscene _rule() {
    final double edge = intro.floorSpan.$2 + 0.55;
    return Cutscene([
      Run(1, toX: intro.floorSpan.$1 + 1.3, seconds: 1),
      Do((_) {
        visitor
          ..revive()
          ..x = 24
          ..groundY = floor
          ..facing = -1
          ..eyes = 1
          ..walkSpeed = 2.2
          ..walkTo(edge);
      }),
      Look(Vector2((intro.floorSpan.$2 + 22) / 2, 5.2)),
      WaitUntil((_) => visitor.mode == VampireMode.stand),
      Do((_) => visitor.reachGoal = 1),
      Wait(1.0),
      // It edges forward; the light touches its hand; it flinches back.
      Do((_) {
        visitor
          ..reachGoal = 0
          ..shieldGoal = 1;
      }),
      Wait(0.9),
      Do((_) {
        visitor
          ..walkSpeed = 1.4
          ..walkTo(26);
      }),
      Wait(1.4),
      Look(null),
    ]);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted) return;
    if (visitor.mode == VampireMode.stand && visitor.x > 25.5) {
      visitor.gone = true;
    }
    corridorHunt.update(dt);
    galleryHunt.update(dt);
    // Off the lift on the way up, with the chest already on the floor: put
    // things back so he is never stranded below an empty lift.
    final double feet = player.body.position.y + GameConfig.playerHeight / 2;
    final bool below =
        feet > floor - 0.5 &&
        player.body.position.x > wallRight &&
        player.body.position.x < 70;
    if (!player.isDead && below && lift.travel < -2.5 && !_chestOnLift) {
      _stuck += dt;
      if (_stuck > 3) {
        _stuck = 0;
        _resetLift();
      }
    } else {
      _stuck = 0;
    }
  }

  bool get _chestOnLift =>
      (chest.body.position.x - liftX).abs() < 1.4 &&
      chest.body.position.y < floor - 0.24 - 0.3 + lift.travel + 0.2;

  void _resetLift() {
    lift.resetToStart();
    counterweight.resetToStart();
    chest.resetToStart();
  }

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (at < wallLeft) {
      cart.resetToStart();
      corridorHunt.reset(34);
    }
    if (at < galleryLeft) _resetLift();
    if (at < doorway) {
      for (final w in windows) {
        w.shut();
      }
      for (final c in cords) {
        c.reset();
      }
      galleryHunt.reset(73);
    }
  }
}
