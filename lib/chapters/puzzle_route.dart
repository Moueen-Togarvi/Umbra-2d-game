import 'dart:ui';
import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show BodyType, Rot;
import '../config/game_config.dart';
import '../world/footprint.dart';
import '../entities/ground.dart';
import '../entities/hazard.dart';
import '../entities/home_props.dart';
import '../entities/physics_props.dart';
import '../entities/castle_props.dart';
import '../entities/cave_props.dart';
import '../entities/clock_props.dart';
import '../entities/castle_traps.dart';
import '../entities/deep_props.dart';
import '../entities/dungeon_props.dart';
import '../entities/outdoor_props.dart' show Drawbridge, RockFall, RopeBridge;
import '../entities/trap_props.dart';
import '../entities/water_props.dart';
import '../entities/wild_props.dart';
import '../physics/water.dart';
import '../story/creatures.dart' show BatFlock;
import '../story/hunters.dart';
import '../story/vampire.dart';
import '../world/stage.dart';

/// Hand-authored room vocabulary; chapters choose their own sequence.
enum PuzzleKind {
  crawl,
  crate,
  rope,
  raft,
  drain,
  weight,
  patrol,
  lantern,
  pendulum,
  cages,
  hammer,
  oil,
  floodTrap,
  lift,
  seesaw,
  coffin,
  returnLoop,

  /// Hunters' traps in the grass; a crate pushed ahead springs them, and
  /// is the step up a wall with the last trap at its foot.
  traps,

  /// A gate that stands open only while its plate is weighed down: one
  /// crate left on the plate, the other taken through to climb with.
  plateGate,

  /// A rotten rope bridge over stakes that gives way a few seconds after
  /// he sets foot on it: across at a run, or not at all.
  bridge,

  /// A vampire out of the dark behind: over a log and a ditch at a run,
  /// to a gate he drops shut behind him with its plate.
  chase,

  /// Stones breaking loose at the top of a stepped rise and bounding down
  /// it at him: over each as it comes, and up between them.
  rockfall,

  /// Bats out of the dark, sweeping low along the way and up again, over
  /// and over: he waits for them to pass, then goes.
  bats,

  /// A ditch of sharpened stakes, and a row of them in the grass: jumped.
  spikes,

  /// A cask on a hilltop, rolled off it down onto a plate that holds a
  /// gate open; standing on the plate himself, he cannot go through.
  barrel,

  /// A hunters' line across a ravine: hold the handle, ride it over.
  zipline,

  /// A dead tree at a ravine's edge, pushed over to lie across it.
  logBridge,

  /// Wolves out of the trees behind: up onto a rock, out of their reach,
  /// before they close.
  wolves,

  /// Crows on the graves; put up, they wake what lies in one. Crept by,
  /// low and slow.
  crows,

  /// A crate tucked against a ledge, pushed from nowhere: pulled out, got
  /// round, then pushed to the wall.
  pullCrate,

  /// A wood too dark to see the ground in, traps in it, and fireflies
  /// that drift on ahead and hang over each.
  fireflies,

  /// Mud that takes him down if he stands: through it at a jump, from
  /// stone to stone.
  bog,

  /// A long rope by a high ledge: up it hand over hand, then across.
  ropeClimb,

  /// An iron cage on a chain: in, pull its cord, and be wound up.
  cageLift,

  /// A drawbridge standing on its chain: pull the cord, and it comes down
  /// across the gap.
  drawbridge,

  /// Three cords, each with its mark, and the order on the gate: pulled
  /// wrong, they all go back.
  levers,

  /// A gap too wide for one rope: from the first to the second.
  twoRopes,

  /// Stone teeth in the roof that drop as he passes under: never stop.
  stalactites,

  /// A deep channel and two pedals: drain it, cross on its bed, and the
  /// second pedal there opens the gate and lets the water back.
  sluice,

  /// A log on the bank: pushed in, it is a raft.
  logFloat,

  /// A raft that will not hold him long: across before it goes under.
  sinkingRaft,

  /// A dry pool and a crate in it: flood it, and the crate floats up to
  /// where the wall can be reached.
  floatCrate,

  /// The roof coming down behind him all the way along a tunnel.
  collapse,

  /// Stones dropping from the roof in turn: under each while it is up.
  crusher,

  /// Coffins in the floor that open and reach: past each while it is shut.
  coffinHands,

  /// A pit at the foot of a wall: one crate fills it, the other is the step.
  twoCrates,

  /// A vampire asleep on his feet: past him low and slow.
  sleeper,

  /// A heavy crate and a light one: the plate wants the heavy, the wall
  /// the light; pushed together they go the wrong way round.
  heavyLight,

  /// Planks over a pit that go down a moment after they are trodden on.
  fallingFloor,

  /// A boulder on a hilltop, rolled down to break the boards across the way.
  boulder,

  /// Barrels rolling down a long slope at him: over each.
  barrelRun,

  /// Water pouring into a shaft: up the steps ahead of it.
  floodRise,

  /// A tall bookcase at a gap's edge, pushed over to lie across it.
  bookcase,

  /// Fire out of the floor gratings in turn: past each while it is out.
  fireJets,

  /// Stairs up over a pit, each step going down a moment after he is on it.
  fallingStairs,

  /// A plate that holds a far gate open only a few seconds after he steps
  /// off it: a run for it.
  timedDoor,

  /// A guard on the way; a bell behind: rung, he goes to look, and the boy
  /// hides as he passes, then goes on.
  bell,

  /// A vampire asleep in the dark under a shuttered window: open it.
  moonWindow,

  /// An eye in the wall that opens and closes: move only while it is shut.
  watchEye,

  /// A guard under a chandelier, and the chandelier's cord.
  chandelier,

  /// Fire coming along the floor behind him: run, and jump what is in the way.
  fireChase,

  /// A bell rope that opens the gate, slowly, and calls something from
  /// behind: through, and its plate drops the gate on what follows.
  bellGate,

  /// Ankle wires and arrows from the wall: over the first at a jump, the
  /// second (under a low roof) crawled, so they fly over.
  tripwire,

  /// A gate that wants both its plates weighed: a crate on one, the boy on
  /// the other, and a dash for it as he steps off.
  twoPlates,

  /// Off a high ledge at a run, out to a rope over the pit.
  leapRope,

  /// A rope that catches fire as he takes it: over and off, quickly.
  burningRope,

  /// A great stone ball rolling down after him: run, and jump what is in
  /// the way without slowing.
  boulderChase,

  /// A platform going to and fro over a pit: on as it comes, off as it
  /// reaches the far side.
  movingPlatform,
}

class PuzzleRoom {
  PuzzleRoom(
    this.kind,
    this.x, {
    this.floor = 7,
    this.length = 42,
    this.withWatcher = false,
  });
  final PuzzleKind kind;
  final bool withWatcher;
  final double x, floor, length;
  double get end => x + length;
  (double, double)? get gap => switch (kind) {
    PuzzleKind.rope => (x + 16, x + 19.2),
    PuzzleKind.raft ||
    PuzzleKind.floodTrap ||
    PuzzleKind.logFloat ||
    PuzzleKind.sinkingRaft => (x + 14, x + 22),
    PuzzleKind.twoRopes => (x + 13, x + 19.4),
    PuzzleKind.drawbridge => (x + 15, x + 20),
    PuzzleKind.pendulum => (x + 13.5, x + 21.5),
    PuzzleKind.cages => (x + 14, x + 20),
    PuzzleKind.weight => (x + 14, x + 16.2),
    PuzzleKind.seesaw => (x + 14, x + 19),
    PuzzleKind.bridge => (x + 12, x + 20),
    PuzzleKind.chase => (x + 18.6, x + 20.2),
    PuzzleKind.spikes => (x + 13, x + 14.3),
    PuzzleKind.zipline => (x + 12, x + 24),
    PuzzleKind.logBridge || PuzzleKind.bookcase => (x + 16, x + 19.2),
    PuzzleKind.twoCrates => (x + 22, x + 23.2),
    PuzzleKind.fallingFloor => (x + 12, x + 24),
    PuzzleKind.fallingStairs => (x + 10, x + 22),
    PuzzleKind.leapRope => (x + 13, x + 18.4),
    PuzzleKind.burningRope => (x + 16, x + 19.2),
    PuzzleKind.movingPlatform => (x + 13, x + 22),
    _ => null,
  };

  /// The room's own rise and fall, as (metres in, metres above its floor)
  /// pairs in order; empty where the floor is level.
  List<(double, double)> get rise => switch (kind) {
    PuzzleKind.rockfall => [(6, 0), (26, 2), (31, 3.2), (33, 3.2), (36, 0)],
    PuzzleKind.barrel => [(3, 0), (7.5, 1.6), (11, 1.6), (17, 0)],
    PuzzleKind.boulder => [
      (3, 0),
      (9, 1.8),
      (11, 1.8),
      (18, 0),
      (27.9, 0),
      (28.0, -1.4),
      (29.45, -1.4),
      (29.55, 0),
    ],
    PuzzleKind.barrelRun => [(4, 0), (26, 3), (31, 3), (34, 0)],
    _ => const [],
  };

  final List<BearTrap> traps = [];
  PressurePlate? plate;
  SlidingGate? door;
  RopeBridge? bridge;

  /// Seconds before a stepped-on bridge gives way; null until it is.
  double? bridgeFuse;
  Pursuer? chaser;
  bool chaseStarted = false;
  RockFall? stones;
  BatFlock? bats;

  /// Seconds to the next sweep of the bats.
  double batClock = 1;
  RollingBarrel? barrel;
  ZipLine? zip;
  TallBookcase? trunk;
  TimedHazardRow? timed;
  BreakableWall? boards;
  CrumblingPlanks? planks;

  /// Seconds to the next barrel down the slope.
  double barrelClock = 0;
  int nextBarrel = 0;
  final List<RollingBarrel> casks = [];
  bool floodStarted = false;

  /// The heavy crate lodged in the plate's slot, and how long it has lain
  /// there still.
  bool heavyLocked = false;

  /// Seconds the timed gate stays open yet.
  double doorTimer = 0;

  /// The bell's guard: 0 on his beat, 1 going to the bell, 2 there,
  /// 3 coming back; and how long he stays there.
  int bellState = 0;
  double bellTimer = 0;
  WatchEye? eye;
  ArrowTrap? arrows;
  MovingPlatform? ferry;
  PressurePlate? plate2;

  /// Seconds before the bell-rung gate starts up.
  double gateDelay = -1;
  FallingChandelier? chandelierAbove;
  double heavyRest = 0;

  /// The wolves, each with its hunter.
  final List<Pursuer> pack = [];
  CrowFlock? crows;
  final List<SwingRope> ropes = [];
  CageLift? cage;
  PullCord? cord;
  Drawbridge? drawbridge;
  final List<PullCord> cords = [];

  /// The cords pulled so far, and the order they must go in.
  final List<int> pulls = [];
  static const leverOrder = [1, 2, 0];
  StalactiteRow? teeth;
  FootPedal? pedal2;
  Collapse? collapse;

  /// Seconds he has stood on a raft that will not hold him.
  double raftTime = 0;

  /// A room with a raft on open water.
  bool get rafting =>
      kind == PuzzleKind.raft ||
      kind == PuzzleKind.floodTrap ||
      kind == PuzzleKind.logFloat ||
      kind == PuzzleKind.sinkingRaft;
  FireflyGuide? fireflies;
  Bog? bog;
  final List<PhysicsCrate> crates = [];
  final List<HangingCage> cages = [];
  Portcullis? gate;
  WeighPan? pan;
  LiftPlatform? lift;
  Counterweight? counterweight;
  final List<void Function()> resets = [];
  final List<void Function()> completed = [];
  WaterBody? water;
  Stalker? hunter;
  double? hunterStart;
  MoonWindow? window;
  OilLamp? lamp;
  FootPedal? pedal;
  bool solved = false;
  int? movingCoverIndex;

  void restore() {
    solved = false;
    for (final crate in crates) {
      crate.resetToStart();
    }
    for (final reset in resets) {
      reset();
    }
    if (hunter != null) hunter!.reset(hunterStart!);
  }

  List<Component> pit(Stage stage) {
    final bounds = gap!;
    final left = bounds.$1, right = bounds.$2;
    if (rafting) {
      water = WaterBody(
        left: left,
        right: right,
        surface: kind == PuzzleKind.floodTrap ? floor + 2.98 : floor + .15,
        bottom: floor + 3,
        current: 0,
        player: stage.player,
      );
      return [
        Ground.slab(left: left, right: right, top: floor + 3, thickness: 2),
        water!,
      ];
    }
    // A bridge sags under him: its stakes stand well down the chasm, where
    // only a fall reaches them.
    if (kind == PuzzleKind.bridge ||
        kind == PuzzleKind.zipline ||
        kind == PuzzleKind.logBridge ||
        kind == PuzzleKind.bookcase ||
        kind == PuzzleKind.fallingFloor ||
        kind == PuzzleKind.fallingStairs ||
        kind == PuzzleKind.leapRope ||
        kind == PuzzleKind.burningRope ||
        kind == PuzzleKind.movingPlatform ||
        kind == PuzzleKind.twoRopes ||
        kind == PuzzleKind.drawbridge) {
      return [
        Hazard.zone(
          left: left,
          right: right,
          top: floor + 3.6,
          bottom: floor + 5.2,
        ),
      ];
    }
    if (kind == PuzzleKind.twoCrates) {
      return [
        Ground.slab(left: left, right: right, top: floor + 1, thickness: 2),
      ];
    }
    if (kind == PuzzleKind.spikes) {
      return [
        Hazard.zone(
          left: left,
          right: right,
          top: floor + 1.5,
          bottom: floor + 3.1,
        ),
      ];
    }
    // The weighing bucket needs a short well below the walkway.
    if (kind == PuzzleKind.weight) {
      return [
        Ground.slab(left: left, right: right, top: floor + 2.6, thickness: 2),
      ];
    }
    return [];
  }

  void furnish(Stage stage, List<Component> pieces) {
    PhysicsCrate crate(double at, {double size = 1, double mass = 28}) {
      final c = PhysicsCrate(
        position: Vector2(at, floor - size / 2),
        size: Vector2.all(size),
        massKg: mass,
      );
      crates.add(c);
      pieces.add(c);
      return c;
    }

    void roof(double left, double right) {
      pieces.add(
        StoneBlock(
          left: left,
          right: right,
          top: floor - 4,
          bottom: floor - 1.04,
          seed: x.round(),
        ),
      );
    }

    /// A gate's frame: posts either side of the way (drawn, the path runs
    /// between them) and a deep lintel, too high to climb over even from a
    /// crate; the gate fills the opening under it.
    SlidingGate framedGate(double at) {
      pieces.addAll([
        _GatePosts(at, floor),
        StoneBlock(
          left: at - .65,
          right: at + .65,
          top: floor - 4.2,
          bottom: floor - 3.05,
        ),
      ]);
      return SlidingGate(
        x: at,
        openTop: floor - 6.1,
        shutTop: floor - 3,
        height: 3,
        width: 1.3,
      );
    }

    void windowAt(double left, double right, {bool open = true}) {
      final w = MoonWindow(
        paneLeft: left,
        paneRight: right,
        paneTop: floor - 4,
        paneBottom: floor - 2,
        floorY: floor,
        slant: 0,
        open: open,
      );
      pieces.add(w);
      window = w;
    }

    void patrol({bool lantern = false}) {
      final v = Vampire(x: x + 24, groundY: floor);
      hunterStart = v.x;
      hunter = Stalker(
        v,
        stage: stage,
        ground: (_) => floor,
        left: x + 8,
        right: x + 32,
        wake: 7,
        speed: 1.8,
        patrolA: x + 14,
        patrolB: x + 25,
      );
      pieces.add(v);
      if (lantern) {
        final cart = LanternCart(x: x + 8, groundY: floor);
        pieces.add(cart);
        resets.add(cart.resetToStart);
        pieces.add(
          StoneBlock(
            left: x + 38,
            right: x + 39,
            top: floor - .55,
            bottom: floor + .1,
          ),
        );
      } else {
        for (final at in [x + 11, x + 18]) {
          final bounds = Rect.fromLTRB(at, floor - 1.5, at + 2.6, floor + .2);
          stage.hidingPlaces.add(bounds);
          pieces.add(_Cover(bounds));
        }
        windowAt(x + 3, x + 7);
      }
      windowAt(x + 32, x + 37);
    }

    switch (kind) {
      case PuzzleKind.crawl:
        roof(x + 12, x + 22);
        pieces.add(
          StoneBlock(
            left: x + 28,
            right: x + 30,
            top: floor - .65,
            bottom: floor + .1,
          ),
        );
      case PuzzleKind.coffin:
        final coffin = Coffin(
          position: Vector2(x + 10, floor - .45),
          massKg: 28,
          height: .9,
        );
        crates.add(coffin);
        pieces.add(coffin);
        // A sill parks the cover before the next room. Its lid remains low
        // enough to climb over with the ordinary jump, keeping it out of water.
        pieces.add(
          StoneBlock(
            left: x + 33.5,
            right: x + 34.1,
            top: floor - .35,
            bottom: floor + .1,
          ),
        );
        movingCoverIndex = stage.hidingPlaces.length;
        stage.hidingPlaces.add(Rect.zero);
        final v = Vampire(x: x + 24, groundY: floor);
        hunterStart = v.x;
        hunter = Stalker(
          v,
          stage: stage,
          ground: (_) => floor,
          left: x + 12,
          right: x + 31,
          patrolA: x + 16,
          patrolB: x + 26,
          speed: 1.8,
        );
        pieces.add(v);
        windowAt(x + 3, x + 7);
        windowAt(x + 27, x + 37);
      case PuzzleKind.crate:
        crate(x + 9);
        pieces.add(
          StoneBlock(
            left: x + 16,
            right: x + 19,
            top: floor - 2.7,
            bottom: floor + .1,
          ),
        );
      case PuzzleKind.rope:
        pieces.add(
          SwingRope(anchor: Vector2(x + 17.8, floor - 4.5), length: 3.6),
        );
      case PuzzleKind.raft:
      case PuzzleKind.floodTrap:
        final raft = FloatingLog(
          position: Vector2(
            x + 15.5,
            floor + (kind == PuzzleKind.floodTrap ? 2.7 : -.15),
          ),
          length: 2.8,
          diameter: .6,
          massKg: 24,
        );
        pieces.add(raft);
        crates.add(raft);
        if (kind == PuzzleKind.floodTrap) {
          final v = Vampire(x: x + 19, groundY: floor + 3);
          hunterStart = v.x;
          hunter = Stalker(
            v,
            stage: stage,
            ground: (_) => floor + 3,
            left: x + 16,
            right: x + 21,
            patrolA: x + 17,
            patrolB: x + 21,
          );
          pedal = FootPedal(
            hinge: Vector2(x + 9, floor - .1),
            onPress: () {
              solved = true;
              water!.floodTo(floor + .15, speed: .55);
            },
          );
          pieces.addAll([v, pedal!]);
          resets.add(() {
            water!.setLevel(floor + 2.98);
            water!.current = 0;
            pedal!.reset();
          });
          completed.add(() {
            water!.setLevel(floor + .15);
            water!.current = .7;
            v.gone = true;
          });
        }
      case PuzzleKind.drain:
        water = WaterBody(
          left: x + 12,
          right: x + 24,
          surface: floor - 1.6,
          bottom: floor + .05,
          player: stage.player,
        );
        roof(x + 13, x + 24);
        pedal = FootPedal(
          hinge: Vector2(x + 9, floor - .1),
          onPress: () {
            solved = true;
            water!.floodTo(floor - .02, speed: .8);
            stage.cue('gate', at: Vector2(x + 12, floor));
          },
        );
        pieces.addAll([water!, pedal!]);
        resets.add(() {
          water!.setLevel(floor - 1.6);
          pedal!.reset();
        });
        completed.add(() {
          water!.setLevel(floor - .02);
          pedal!.pressed = true;
        });
      case PuzzleKind.lift:
      case PuzzleKind.returnLoop:
        final returning = kind == PuzzleKind.returnLoop;
        lift = LiftPlatform(
          position: Vector2(x + 18.4, floor - .12),
          rise: 3.16,
        );
        counterweight = Counterweight(
          position: Vector2(x + 15.6, floor - 6.1),
          massKg: 65,
          rise: 0,
          drop: 3.16,
        );
        final chest = PhysicsCrate(
          position: Vector2(x + 19.15, floor - .74),
          size: Vector2.all(1),
          massKg: 50,
        );
        crates.add(chest);
        pieces.addAll([
          lift!,
          counterweight!,
          Pulley(a: lift!, b: counterweight!, wheelY: floor - 7.4),
          chest,
          StoneBlock(
            left: x + 20,
            right: x + (returning ? 21.8 : 31),
            top: floor - 3.4,
            bottom: floor - 2.8,
          ),
          StoneBlock(
            left: x + (returning ? 32 : 23.5),
            right: x + (returning ? 33 : 31),
            top: floor - (returning ? 8 : 2.8),
            bottom: floor + (returning ? -1.04 : .05),
          ),
        ]);
        resets.add(() {
          lift!.resetToStart();
          lift!.free();
          counterweight!.resetToStart();
          counterweight!.free();
        });
        completed.add(() {
          lift!.restoreTravel(-lift!.rise);
          counterweight!.restoreTravel(counterweight!.drop);
        });
        if (returning) {
          // The weighted lift reaches a blind upper gallery. Its control
          // drains the route beneath it, so he must return to the courtyard
          // and push the same unloaded chest through the low passage.
          water = WaterBody(
            left: x + 21.8,
            right: x + 36,
            surface: floor - 1.6,
            bottom: floor + .05,
            player: stage.player,
          );
          pedal = FootPedal(
            hinge: Vector2(x + 28.5, floor - 3.4),
            onPress: () {
              solved = true;
              water!.floodTo(floor - .02, speed: .8);
              window?.open();
              stage.cue('gate', at: Vector2(x + 28, floor - 3.4));
            },
          );
          pieces.addAll([
            StoneBlock(
              left: x + 21.8,
              right: x + 36,
              top: floor - 3.4,
              bottom: floor - 1.04,
            ),
            water!,
            pedal!,
            _SluiceLink(x, floor, () => solved),
            StoneBlock(
              left: x + 39,
              right: x + 39.6,
              top: floor - .35,
              bottom: floor + .1,
            ),
          ]);
          if (withWatcher) {
            windowAt(x + 40, x + 46, open: false);
            final vampire = Vampire(x: x + 43, groundY: floor);
            hunterStart = vampire.x;
            hunter = Stalker(
              vampire,
              stage: stage,
              ground: (_) => floor,
              left: x + 40,
              right: x + 46,
            );
            pieces.add(vampire);
          }
          resets.add(() {
            water!.setLevel(floor - 1.6);
            pedal!.reset();
            window?.shut();
          });
          completed.add(() {
            solved = true;
            water!.setLevel(floor - .02);
            pedal!.pressed = true;
            chest.restoreAt(Vector2(x + 38.4, floor - .5));
            window?.open();
          });
        }
      case PuzzleKind.seesaw:
        pieces.add(
          Seesaw(
            pivot: Vector2(x + 16.5, floor + .4),
            length: 5.6,
            postBottom: floor + 3,
            tilt: .22,
          ),
        );
      case PuzzleKind.weight:
        final pan = this.pan = WeighPan(
          floorAt: Vector2(x + 15.1, floor),
          width: 2.1,
          drop: 2.3,
        );
        final gate = this.gate = Portcullis(
          position: Vector2(x + 25, floor - 1.4),
          height: 2.8,
          rise: 2.3,
        );
        crate(x + 10, mass: 42);
        roof(x + 30, x + 36);
        pieces.addAll([pan, gate, Pulley(a: pan, b: gate, wheelY: floor - 4)]);
        resets.addAll([
          () {
            pan.free();
            pan.resetToStart();
          },
          () {
            gate.free();
            gate.resetToStart();
          },
        ]);
        completed.add(() {
          pan.restoreTravel(pan.drop);
          gate.restoreTravel(-gate.rise);
        });
      case PuzzleKind.patrol:
        patrol();
      case PuzzleKind.lantern:
        patrol(lantern: true);
      case PuzzleKind.pendulum:
        final p = Pendulum(
          pivot: Vector2(x + 17.5, floor - (6 * math.cos(.56) - .1)),
          length: 6,
          amplitude: .56,
          plate: 1.4,
        );
        pieces.add(p);
        resets.add(p.reset);
        roof(x + 27, x + 33);
      case PuzzleKind.cages:
        for (final at in [x + 15.3, x + 18.5]) {
          final cage = HangingCage(
            anchor: Vector2(at, floor - 4.5),
            chainLength: 4.1,
            height: 1.5,
            width: 2.2,
          );
          pieces.add(cage);
          cages.add(cage);
        }
      case PuzzleKind.oil:
        final v = Vampire(x: x + 23, groundY: floor);
        hunterStart = v.x;
        hunter = Stalker(
          v,
          stage: stage,
          ground: (_) => floor,
          left: x + 17,
          right: x + 27,
          patrolA: x + 21,
          patrolB: x + 26,
        );
        lamp = OilLamp(
          anchor: Vector2(x + 16, floor - 4),
          chain: 1.5,
          floorY: floor,
          spreadTo: x + 28,
          burnSeconds: 14,
        );
        pedal = FootPedal(
          hinge: Vector2(x + 9, floor - .1),
          onPress: () {
            solved = true;
            lamp!.drop();
          },
        );
        pieces.addAll([v, lamp!, pedal!]);
        resets.add(() {
          lamp!.rehang();
          pedal!.reset();
        });
        completed.add(() {
          v.gone = true;
        });
      case PuzzleKind.traps:
        crate(x + 4.5);
        for (final at in [9.0, 13.5, 19.6, 29.0, 32.2]) {
          final trap = BearTrap(x: x + at, groundY: floor, stage: stage);
          traps.add(trap);
          pieces.add(trap);
          resets.add(trap.reset);
        }
        pieces.add(
          StoneBlock(
            left: x + 20.3,
            right: x + 25,
            top: floor - 2.7,
            bottom: floor + .1,
          ),
        );
        completed.add(() {
          for (final trap in traps) {
            trap.sprung = true;
          }
        });
      case PuzzleKind.plateGate:
        crate(x + 5);
        crate(x + 15);
        final plate = this.plate = PressurePlate(
          left: x + 10.3,
          right: x + 11.7,
          groundY: floor,
          stage: stage,
        );
        final door = this.door = framedGate(x + 20)..shut = true;
        pieces.addAll([
          plate,
          door,
          StoneBlock(
            left: x + 24.5,
            right: x + 30,
            top: floor - 2.7,
            bottom: floor + .1,
          ),
        ]);
        resets.add(() => door.shut = true);
        completed.add(() {
          solved = true;
          door.shut = false;
        });
      case PuzzleKind.bridge:
        final bridge = this.bridge = RopeBridge(
          from: Vector2(x + 12, floor),
          to: Vector2(x + 20, floor),
          planks: 12,
          sag: .03,
        );
        pieces.add(bridge);
        resets.add(() {
          bridge.reset();
          bridgeFuse = null;
        });
      case PuzzleKind.chase:
        final v = Vampire(x: x - 4, groundY: floor)..gone = true;
        hunterStart = x - 1;
        chaser = Pursuer(v, stage: stage, speed: 2.95);
        final door = this.door = framedGate(x + 27);
        final plate = this.plate = PressurePlate(
          left: x + 29,
          right: x + 30.4,
          groundY: floor,
          stage: stage,
        );
        pieces.addAll([
          v,
          // A fallen trunk across the way.
          StoneBlock(
            left: x + 12.6,
            right: x + 13.5,
            top: floor - .9,
            bottom: floor + .1,
          ),
          door,
          plate,
        ]);
        resets.add(() {
          chaser!.stop();
          v.gone = true;
          chaseStarted = false;
          door.shut = false;
        });
        completed.add(() {
          solved = true;
          v.gone = true;
          door.shut = true;
        });
      case PuzzleKind.rockfall:
        final stones = this.stones = RockFall(
          from: Vector2(x + 32, floor - 3.75),
          every: 3.6,
          count: 4,
          firstAfter: .6,
          speed: 3.4,
          rounding: .2,
          deadly: 1.5,
        );
        pieces.addAll([
          // A low sill the stones fetch up against; he steps over it.
          StoneBlock(
            left: x + 3,
            right: x + 3.5,
            top: floor - .45,
            bottom: floor + .1,
          ),
          stones,
        ]);
        resets.add(stones.reset);
        completed.add(stones.stop);
      case PuzzleKind.bats:
        final flock = bats = BatFlock(
          roost: Vector2(x + 30, floor - 7),
          count: 16,
          seed: x.round(),
        );
        pieces.add(flock);
        resets.add(() => batClock = 1);
      case PuzzleKind.spikes:
        pieces.add(StakeRow(left: x + 22, right: x + 22.9, groundY: floor));
      case PuzzleKind.barrel:
        final cask = barrel = RollingBarrel(
          position: Vector2(x + 9.6, floor - 1.6 - .42),
          settleIn: Rect.fromLTRB(x + 22.6, floor - 1, x + 24, floor),
        );
        final plate = this.plate = PressurePlate(
          left: x + 22.6,
          right: x + 24,
          groundY: floor,
          stage: stage,
        );
        final door = this.door = framedGate(x + 28)..shut = true;
        pieces.addAll([
          cask,
          plate,
          // A sill past the plate: the cask fetches up against it there.
          StoneBlock(
            left: x + 24,
            right: x + 24.45,
            top: floor - .5,
            bottom: floor + .1,
          ),
          door,
        ]);
        resets.addAll([cask.resetToStart, () => door.shut = true]);
        completed.add(() {
          solved = true;
          door.shut = false;
          cask.restoreAt(Vector2(x + 23.55, floor - .42));
          cask
            ..settled = true
            ..body.type = BodyType.static;
        });
      case PuzzleKind.zipline:
        final line = zip = ZipLine(
          from: Vector2(x + 10.4, floor - 4.6),
          to: Vector2(x + 26.2, floor - 3.6),
          groundFrom: floor - 1.2,
          groundTo: floor,
        );
        pieces.addAll([
          // The platform the line is strung from.
          StoneBlock(
            left: x + 8,
            right: x + 11.6,
            top: floor - 1.2,
            bottom: floor + .1,
          ),
          line,
          line.handle,
        ]);
        resets.add(line.handle.reset);
      case PuzzleKind.logBridge:
      case PuzzleKind.bookcase:
        final tree = trunk = kind == PuzzleKind.bookcase
            ? TallBookcase(x: x + 16 - .66, floorY: floor, height: 4.8)
            : DeadTrunk(x: x + 16 - .66, floorY: floor);
        crates.add(tree);
        pieces.addAll([
          tree,
          // A kerb of rock at the edge: its foot stops there and it turns
          // over instead of sliding in.
          StoneBlock(
            left: x + 15.7,
            right: x + 16,
            top: floor - .12,
            bottom: floor + .05,
          ),
        ]);
        completed.add(() {
          if (!tree.isReady) return;
          tree.body
            ..setTransform(
              Vector2(x + 17.75, floor - .3),
              Rot.fromAngle(math.pi / 2),
            )
            ..linearVelocity = Vector2.zero()
            ..angularVelocity = 0
            ..type = BodyType.static;
          tree.wedged = true;
        });
      case PuzzleKind.wolves:
        for (var i = 0; i < 2; i++) {
          final wolf = Wolf(x: x - 5 - i * 1.3, groundY: floor)..gone = true;
          pack.add(
            Pursuer(
              wolf,
              stage: stage,
              speed: i == 0 ? 3.9 : 3.7,
              catchReach: .7,
              climb: .8,
            ),
          );
          pieces.add(wolf);
        }
        pieces.addAll([
          // A fallen log, then the rock: a step, and its top.
          StoneBlock(
            left: x + 8,
            right: x + 8.7,
            top: floor - .6,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 15,
            right: x + 17,
            top: floor - 1.1,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 17,
            right: x + 31,
            top: floor - 2.3,
            bottom: floor + .1,
          ),
        ]);
        resets.add(() {
          chaseStarted = false;
          for (final hunter in pack) {
            hunter.stop();
            hunter.vampire.gone = true;
          }
        });
        completed.add(() {
          solved = true;
          for (final hunter in pack) {
            hunter.vampire.gone = true;
          }
        });
      case PuzzleKind.crows:
        final v = Vampire(x: x + 26, groundY: floor)..gone = true;
        chaser = Pursuer(v, stage: stage, speed: 2.9);
        final flock = crows = CrowFlock(
          perches: [
            for (final at in const [11.0, 12.1, 13.9, 15.0])
              Vector2(x + at, floor),
          ],
          stage: stage,
          onFlush: () {},
        );
        pieces.addAll([_Grave(x + 26, floor), v, flock]);
        resets.add(() {
          flock.reset();
          chaser!.stop();
          v.gone = true;
          chaseStarted = false;
        });
        completed.add(() {
          solved = true;
          v.gone = true;
        });
      case PuzzleKind.pullCrate:
        pieces.addAll([
          StoneBlock(
            left: x + 4.5,
            right: x + 8,
            top: floor - 1.15,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 21,
            right: x + 27,
            top: floor - 2.7,
            bottom: floor + .1,
          ),
        ]);
        // Light enough to drag back: the pull is weaker than a push.
        final box = crate(x + 8.52, mass: 14);
        completed.add(() => box.restoreAt(Vector2(x + 20.5, floor - .5)));
      case PuzzleKind.fireflies:
        const at = [8.0, 11.4, 14.8, 18.4, 21.8, 25.2];
        for (final a in at) {
          final trap = BearTrap(x: x + a, groundY: floor, stage: stage);
          traps.add(trap);
          pieces.add(trap);
          resets.add(trap.reset);
        }
        final guide = fireflies = FireflyGuide(
          left: x + 4,
          right: x + 30,
          floor: floor,
          stops: [for (final a in at) x + a],
          stage: stage,
        );
        pieces.add(guide);
        resets.add(guide.reset);
        completed.add(() {
          for (final trap in traps) {
            trap.sprung = true;
          }
        });
      case PuzzleKind.bog:
        final mud = bog = Bog(
          left: x + 8,
          right: x + 27,
          floor: floor,
          stage: stage,
        );
        pieces.add(mud);
        for (final at in const [13.2, 19.6]) {
          pieces.add(
            StoneBlock(
              left: x + at,
              right: x + at + 1,
              top: floor - .42,
              bottom: floor + .1,
            ),
          );
        }
        resets.add(mud.reset);
      case PuzzleKind.ropeClimb:
        final line = SwingRope(
          anchor: Vector2(x + 16.5, floor - 6.6),
          length: 6,
          support: RopeSupport.ring,
        );
        ropes.add(line);
        pieces.addAll([
          line,
          StoneBlock(
            left: x + 17.7,
            right: x + 28,
            top: floor - 3.8,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 28,
            right: x + 30.5,
            top: floor - 1.9,
            bottom: floor + .1,
          ),
        ]);
      case PuzzleKind.cageLift:
        final lift = cage = CageLift(
          x: x + 15.8,
          bottom: floor - .05,
          top: floor - 3.65,
        );
        final pull = cord = PullCord(
          anchor: Vector2(x + 15.3, floor - 7.6),
          length: 5.9,
          onPulled: lift.rise,
        );
        pieces.addAll([
          lift,
          pull,
          StoneBlock(
            left: x + 16.95,
            right: x + 28,
            top: floor - 3.6,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 28,
            right: x + 30.5,
            top: floor - 1.8,
            bottom: floor + .1,
          ),
        ]);
        resets.addAll([lift.reset, pull.reset]);
        completed.add(lift.restoreRaised);
      case PuzzleKind.drawbridge:
        final bridge = drawbridge = Drawbridge(
          hinge: Vector2(x + 15, floor),
          length: 5.3,
        );
        final pull = cord = PullCord(
          anchor: Vector2(x + 13.6, floor - 4.5),
          length: 3.6,
          onPulled: bridge.lower,
        );
        pieces.addAll([bridge, pull]);
        resets.addAll([bridge.raise, pull.reset]);
        completed.add(bridge.lower);
      case PuzzleKind.levers:
        for (var i = 0; i < 3; i++) {
          final double at = x + 8 + i * 2.6;
          final pull = PullCord(
            anchor: Vector2(at, floor - 4.6),
            length: 3.5,
            onPulled: () => pulls.add(i),
          );
          cords.add(pull);
          pieces.addAll([
            pull,
            Sign(at: Vector2(at - .55, floor - 2.6), marks: [i]),
          ]);
        }
        final door = this.door = framedGate(x + 20)..shut = true;
        pieces.addAll([
          door,
          Sign(at: Vector2(x + 16.3, floor - 3.6), marks: leverOrder),
        ]);
        resets.add(() {
          pulls.clear();
          for (final c in cords) {
            c.reset();
          }
          door.shut = true;
        });
        completed.add(() {
          solved = true;
          door.shut = false;
        });
      case PuzzleKind.twoRopes:
        for (final at in const [14.8, 17.6]) {
          final line = SwingRope(
            anchor: Vector2(x + at, floor - 4.6),
            length: 3.7,
            support: RopeSupport.ring,
          );
          ropes.add(line);
          pieces.add(line);
        }
      case PuzzleKind.stalactites:
        final row = teeth = StalactiteRow(
          xs: [
            for (final a in const [11.0, 13.6, 16.5, 19.4, 22.1, 25.0, 27.8])
              x + a,
          ],
          ceiling: floor - 4.2,
          floor: floor,
          stage: stage,
        );
        pieces.addAll([
          StoneBlock(
            left: x + 8,
            right: x + 31,
            top: floor - 6,
            bottom: floor - 4.2,
            seed: x.round(),
          ),
          StoneBlock(
            left: x + 17.4,
            right: x + 17.9,
            top: floor - .5,
            bottom: floor + .1,
          ),
          row,
        ]);
        resets.add(row.reset);
      case PuzzleKind.sluice:
        final pool = water = WaterBody(
          left: x + 12,
          right: x + 22,
          surface: floor - 1.6,
          bottom: floor + .05,
          player: stage.player,
        );
        final door = this.door = framedGate(x + 28)..shut = true;
        pedal = FootPedal(
          hinge: Vector2(x + 9, floor - .1),
          onPress: () {
            pool.floodTo(floor - .02, speed: .8);
            stage.cue('gate', at: Vector2(x + 12, floor));
          },
        );
        // On the far side of the channel: reached only across its bed.
        pedal2 = FootPedal(
          hinge: Vector2(x + 23.4, floor - .1),
          onPress: () {
            solved = true;
            door.shut = false;
            pool.floodTo(floor - 1.6, speed: .45);
            stage.cue('gate', at: Vector2(x + 28, floor), shake: .3);
            stage.cue('rumble', weight: .7, at: Vector2(x + 13, floor));
          },
        );
        pieces.addAll([pool, pedal!, pedal2!, door]);
        resets.add(() {
          pool.setLevel(floor - 1.6);
          pedal!.reset();
          pedal2!.reset();
          door.shut = true;
        });
        completed.add(() {
          pool.setLevel(floor - 1.6);
          pedal!.pressed = true;
          pedal2!.pressed = true;
          door.shut = false;
        });
      case PuzzleKind.logFloat:
      case PuzzleKind.sinkingRaft:
        final onBank = kind == PuzzleKind.logFloat;
        final raft = FloatingLog(
          position: onBank
              ? Vector2(x + 11.2, floor - .3)
              : Vector2(x + 15.5, floor - .15),
          length: 2.8,
          diameter: .6,
          massKg: 24,
        );
        pieces.add(raft);
        crates.add(raft);
        resets.add(() => raftTime = 0);
      case PuzzleKind.floatCrate:
        final pool = water = WaterBody(
          left: x + 11,
          right: x + 14,
          surface: floor - .02,
          bottom: floor + .05,
          player: stage.player,
        );
        crate(x + 12.5, size: 1.2, mass: 14);
        pedal = FootPedal(
          hinge: Vector2(x + 9, floor - 2.3),
          onPress: () {
            solved = true;
            pool.floodTo(floor - 2, speed: .6);
            stage.cue('gate', at: Vector2(x + 11, floor));
          },
        );
        pieces.addAll([
          StoneBlock(
            left: x + 4,
            right: x + 6,
            top: floor - 1.1,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 6,
            right: x + 11,
            top: floor - 2.2,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 14,
            right: x + 24,
            top: floor - 3.4,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 24,
            right: x + 26,
            top: floor - 1.7,
            bottom: floor + .1,
          ),
          pool,
          pedal!,
        ]);
        resets.add(() {
          pool.setLevel(floor - .02);
          pedal!.reset();
        });
        completed.add(() {
          pool.setLevel(floor - 2);
          pedal!.pressed = true;
        });
      case PuzzleKind.collapse:
        final fall = collapse = Collapse(
          from: x + 2,
          to: x + 32,
          ceiling: floor - 3.4,
          floor: floor,
          stage: stage,
        );
        pieces.addAll([
          StoneBlock(
            left: x + 2,
            right: x + 32,
            top: floor - 5.5,
            bottom: floor - 3.4,
            seed: x.round(),
          ),
          for (final at in const [12.0, 20.0])
            StoneBlock(
              left: x + at,
              right: x + at + .6,
              top: floor - .5,
              bottom: floor + .1,
            ),
          fall,
        ]);
        resets.add(fall.reset);
      case PuzzleKind.crusher:
      case PuzzleKind.coffinHands:
      case PuzzleKind.fireJets:
        final row = timed = TimedHazardRow(
          xs: [
            for (final a
                in kind == PuzzleKind.coffinHands
                    ? const [11.0, 14.5, 18.0, 21.5, 25.0]
                    : const [12.0, 15.5, 19.0, 22.5])
              x + a,
          ],
          floor: floor,
          stage: stage,
          style: switch (kind) {
            PuzzleKind.crusher => HazardStyle.crusher,
            PuzzleKind.coffinHands => HazardStyle.hands,
            _ => HazardStyle.flame,
          },
          period: kind == PuzzleKind.crusher ? 3.4 : 3.0,
          ceiling: floor - 4.6,
        );
        if (kind == PuzzleKind.crusher) {
          pieces.add(
            StoneBlock(
              left: x + 9,
              right: x + 26,
              top: floor - 6.2,
              bottom: floor - 4.6,
              seed: x.round(),
            ),
          );
        }
        pieces.add(row);
        resets.add(row.reset);
      case PuzzleKind.twoCrates:
        final a = crate(x + 9);
        final b = crate(x + 13);
        pieces.addAll([
          StoneBlock(
            left: x + 23.2,
            right: x + 30,
            top: floor - 2.6,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 30,
            right: x + 32,
            top: floor - 1.3,
            bottom: floor + .1,
          ),
        ]);
        resets.add(() {
          for (final c in [a, b]) {
            if (c.isReady) c.body.type = BodyType.dynamic;
            c.resetToStart();
          }
        });
        completed.add(() {
          b.restoreAt(Vector2(x + 22.6, floor + .5));
          if (b.isReady) b.body.type = BodyType.static;
          a.restoreAt(Vector2(x + 22.65, floor - .5));
        });
      case PuzzleKind.sleeper:
        final v = Vampire(x: x + 20, groundY: floor, facing: -1)..eyes = .1;
        chaser = Pursuer(v, stage: stage, speed: 3.0);
        pieces.add(v);
        resets.add(() {
          chaser!.stop();
          chaseStarted = false;
          v
            ..revive()
            ..x = x + 20
            ..groundY = floor
            ..facing = -1
            ..eyes = .1;
        });
      case PuzzleKind.heavyLight:
        crate(x + 6, mass: 20);
        crate(x + 8.2, mass: 9);
        final plate = this.plate = PressurePlate(
          left: x + 12,
          right: x + 13.4,
          groundY: floor,
          stage: stage,
          minMass: 16,
        );
        final door = this.door = framedGate(x + 18)..shut = true;
        pieces.addAll([
          plate,
          door,
          StoneBlock(
            left: x + 23,
            right: x + 29,
            top: floor - 2.7,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 29,
            right: x + 31,
            top: floor - 1.3,
            bottom: floor + .1,
          ),
        ]);
        resets.add(() {
          door.shut = true;
          heavyLocked = false;
          heavyRest = 0;
          if (crates[0].isReady) crates[0].body.type = BodyType.dynamic;
          crates[0].resetToStart();
        });
        completed.add(() {
          solved = true;
          door.shut = false;
          heavyLocked = true;
          crates[0].restoreAt(Vector2(x + 12.7, floor - .5));
          if (crates[0].isReady) crates[0].body.type = BodyType.static;
          crates[1].restoreAt(Vector2(x + 22.5, floor - .5));
        });
      case PuzzleKind.fallingFloor:
        final floorboards = planks = CrumblingPlanks(
          left: x + 12,
          right: x + 24,
          top: floor,
          stage: stage,
          count: 12,
        );
        pieces.add(floorboards);
        resets.add(floorboards.reset);
      case PuzzleKind.boulder:
        final stone = barrel = RollingBarrel(
          position: Vector2(x + 10.2, floor - 1.8 - .7),
          radius: .7,
          massKg: 40,
          // Come to rest in the hollow past the boards, it stays there.
          settleIn: Rect.fromLTRB(x + 27.5, floor - 2, x + 30, floor + 1.5),
          settleAt: Vector2(x + 28.72, floor + .55),
        );
        final wall = boards = BreakableWall(
          left: x + 25.4,
          right: x + 25.9,
          top: floor - 3.2,
          bottom: floor + .1,
        );
        pieces.addAll([stone, wall]);
        resets.addAll([stone.resetToStart, wall.reset]);
        completed.add(() {
          wall.shatter();
          stone.restoreAt(Vector2(x + 28.72, floor + 1.4 - .7));
        });
      case PuzzleKind.barrelRun:
        for (var i = 0; i < 3; i++) {
          final cask = RollingBarrel(
            position: Vector2(x + 31 + i, floor - 40),
            parked: true,
          );
          casks.add(cask);
          pieces.add(cask);
        }
        resets.add(() {
          barrelClock = 0;
          for (final (i, c) in casks.indexed) {
            c.restoreAt(Vector2(x + 31 + i, floor - 40));
            if (c.isReady) c.body.type = BodyType.static;
          }
        });
      case PuzzleKind.floodRise:
        final pool = water = WaterBody(
          left: x + 4,
          right: x + 21,
          surface: floor - .02,
          bottom: floor + .05,
          player: stage.player,
        );
        pieces.addAll([
          for (final (l, r, h) in const [
            (9.0, 12.0, 1.0),
            (12.0, 15.0, 2.0),
            (15.0, 18.0, 3.0),
            (18.0, 30.0, 4.1),
            (30.0, 32.0, 2.0),
          ])
            StoneBlock(
              left: x + l,
              right: x + r,
              top: floor - h,
              bottom: floor + .1,
            ),
          pool,
        ]);
        resets.add(() {
          floodStarted = false;
          pool.setLevel(floor - .02);
        });
        completed.add(() {
          floodStarted = true;
          pool.setLevel(floor - 3.9);
        });
      case PuzzleKind.fallingStairs:
        final steps = planks = CrumblingPlanks(
          left: x + 10,
          right: x + 22,
          top: floor - .25,
          stage: stage,
          count: 12,
          rise: .33,
        );
        pieces.addAll([
          steps,
          StoneBlock(
            left: x + 22,
            right: x + 30,
            top: floor - 4.2,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 30,
            right: x + 32,
            top: floor - 2.1,
            bottom: floor + .1,
          ),
        ]);
        resets.add(steps.reset);
      case PuzzleKind.timedDoor:
        final plate = this.plate = PressurePlate(
          left: x + 8,
          right: x + 9.4,
          groundY: floor,
          stage: stage,
        );
        final door = this.door = framedGate(x + 21)..shut = true;
        pieces.addAll([
          plate,
          door,
          StoneBlock(
            left: x + 15,
            right: x + 15.6,
            top: floor - .5,
            bottom: floor + .1,
          ),
        ]);
        resets.add(() {
          doorTimer = 0;
          door.shut = true;
        });
        completed.add(() {
          solved = true;
          door.shut = false;
        });
      case PuzzleKind.bell:
        final v = Vampire(x: x + 22, groundY: floor)..patrol(x + 19, x + 25);
        chaser = Pursuer(v, stage: stage, speed: 3.0);
        final pull = cord = PullCord(
          anchor: Vector2(x + 5, floor - 4.6),
          length: 3.5,
          onPulled: () => stage.cue('bell', at: Vector2(x + 3.2, floor - 3)),
        );
        final cover = Rect.fromLTRB(x + 7, floor - 1.5, x + 9.6, floor + .2);
        stage.hidingPlaces.add(cover);
        pieces.addAll([v, pull, _Bell(x + 3.2, floor - 3.4), _Cover(cover)]);
        resets.add(() {
          pull.reset();
          bellState = 0;
          chaseStarted = false;
          chaser!.stop();
          v
            ..revive()
            ..x = x + 22
            ..groundY = floor
            ..facing = -1
            ..patrol(x + 19, x + 25);
        });
        completed.add(() => v.gone = true);
      case PuzzleKind.moonWindow:
        final v = Vampire(x: x + 24, groundY: floor);
        hunterStart = v.x;
        hunter = Stalker(
          v,
          stage: stage,
          ground: (_) => floor,
          left: x + 20.3,
          right: x + 27.7,
          wake: 5,
        );
        windowAt(x + 20, x + 28, open: false);
        final pull = cord = PullCord(
          anchor: Vector2(x + 12, floor - 4.6),
          length: 3.5,
          onPulled: () => window!.open(),
        );
        pieces.addAll([v, pull]);
        resets.addAll([pull.reset, () => window!.shut()]);
        completed.add(() => window!.open());
      case PuzzleKind.watchEye:
        final watcher = eye = WatchEye(
          at: Vector2(x + 18, floor - 4.4),
          left: x + 7,
          right: x + 29,
          stage: stage,
        );
        pieces.add(watcher);
        resets.add(watcher.reset);
      case PuzzleKind.chandelier:
        final v = Vampire(x: x + 22, groundY: floor, facing: -1);
        hunterStart = v.x;
        hunter = Stalker(
          v,
          stage: stage,
          ground: (_) => floor,
          left: x + 14,
          right: x + 30,
          wake: 5.5,
        );
        final lamp = chandelierAbove = FallingChandelier(
          x: x + 22,
          hangY: floor - 4.6,
          floor: floor,
          stage: stage,
          onLanded: () {
            if ((v.x - (x + 22)).abs() < 1.6 && !v.gone) {
              v.gone = true;
              stage.cue('shriek', at: Vector2(x + 22, floor - 1));
            }
          },
        );
        final pull = cord = PullCord(
          anchor: Vector2(x + 14, floor - 4.6),
          length: 3.5,
          onPulled: lamp.drop,
        );
        pieces.addAll([v, lamp, pull]);
        resets.addAll([lamp.reset, pull.reset]);
        completed.add(lamp.restoreDown);
      case PuzzleKind.fireChase:
        final fire = collapse = Collapse(
          from: x + 2,
          to: x + 32,
          ceiling: floor - 3,
          floor: floor,
          stage: stage,
          speed: 2.6,
          flames: true,
        );
        pieces.addAll([
          for (final at in const [12.0, 20.0])
            StoneBlock(
              left: x + at,
              right: x + at + .6,
              top: floor - .5,
              bottom: floor + .1,
            ),
          fire,
        ]);
        resets.add(fire.reset);
      case PuzzleKind.bellGate:
        final v = Vampire(x: x - 4, groundY: floor)..gone = true;
        chaser = Pursuer(v, stage: stage, speed: 2.7);
        final door = this.door = framedGate(x + 18)..shut = true;
        final pull = cord = PullCord(
          anchor: Vector2(x + 10, floor - 4.6),
          length: 3.5,
          onPulled: () {
            gateDelay = 1.6;
            stage.cue('bell', at: Vector2(x + 10, floor - 4));
          },
        );
        final plate = this.plate = PressurePlate(
          left: x + 20.3,
          right: x + 21.7,
          groundY: floor,
          stage: stage,
        );
        pieces.addAll([v, door, pull, plate]);
        resets.add(() {
          gateDelay = -1;
          pull.reset();
          chaser!.stop();
          chaseStarted = false;
          v.gone = true;
          door.shut = true;
        });
        completed.add(() {
          solved = true;
          v.gone = true;
          door.shut = true;
        });
      case PuzzleKind.tripwire:
        final trap = arrows = ArrowTrap(
          wires: [x + 11, x + 19.5],
          slotX: x + 26,
          floor: floor,
          stage: stage,
        );
        roof(x + 17, x + 22.5);
        pieces.add(trap);
        resets.add(trap.reset);
      case PuzzleKind.twoPlates:
        crate(x + 6);
        final a = plate = PressurePlate(
          left: x + 10.3,
          right: x + 11.7,
          groundY: floor,
          stage: stage,
        );
        final b = plate2 = PressurePlate(
          left: x + 16.4,
          right: x + 17.8,
          groundY: floor,
          stage: stage,
        );
        final door = this.door = framedGate(x + 20.5)..shut = true;
        pieces.addAll([a, b, door]);
        resets.add(() {
          doorTimer = 0;
          door.shut = true;
        });
        completed.add(() {
          solved = true;
          door.shut = false;
        });
      case PuzzleKind.leapRope:
        final line = SwingRope(
          anchor: Vector2(x + 15.3, floor - 6.2),
          length: 4.2,
          support: RopeSupport.ring,
        );
        ropes.add(line);
        pieces.addAll([
          StoneBlock(
            left: x + 6,
            right: x + 8,
            top: floor - 1,
            bottom: floor + .1,
          ),
          StoneBlock(
            left: x + 8,
            right: x + 13,
            top: floor - 2,
            bottom: floor + .1,
          ),
          line,
        ]);
      case PuzzleKind.burningRope:
        final line = BurningRope(
          anchor: Vector2(x + 17.8, floor - 4.5),
          length: 3.6,
        );
        ropes.add(line);
        pieces.add(line);
        resets.add(line.reset);
      case PuzzleKind.boulderChase:
        final ball = collapse = Collapse(
          from: x + 1,
          to: x + 34,
          ceiling: floor - 4,
          floor: floor,
          stage: stage,
          speed: 2.75,
          boulder: true,
        );
        pieces.addAll([
          for (final at in const [13.0, 22.0])
            StoneBlock(
              left: x + at,
              right: x + at + .6,
              top: floor - .5,
              bottom: floor + .1,
            ),
          ball,
        ]);
        resets.add(ball.reset);
      case PuzzleKind.movingPlatform:
        final deck = ferry = MovingPlatform(
          from: Vector2(x + 14.2, floor - .15),
          to: Vector2(x + 20.8, floor - .15),
          size: Vector2(2.2, .3),
          speed: 1.4,
        );
        pieces.add(deck);
      case PuzzleKind.hammer:
        final gear = Gear(
          centre: Vector2(x + 18, floor + .35),
          radius: .9,
          speed: .65,
          torque: 100,
        );
        pieces.addAll([
          gear,
          StrikingHammer(
            axle: Vector2(x + 22, floor - 1.7),
            arm: 1.65,
            gear: gear,
            arms: 2,
          ),
        ]);
        crate(x + 12, mass: 38);
        resets.add(gear.free);
    }
  }
}

class PuzzleRoute extends Component {
  PuzzleRoute(this.stage, this.rooms);
  final Stage stage;
  final List<PuzzleRoom> rooms;
  @override
  void update(double dt) {
    super.update(dt);
    for (final room in rooms) {
      if (room.movingCoverIndex != null) {
        final at = room.crates.first.body.position;
        stage.hidingPlaces[room.movingCoverIndex!] = Rect.fromLTRB(
          at.x - 2.4,
          room.floor - 1.2,
          at.x - .8,
          room.floor + .1,
        );
      }
      if (room.kind == PuzzleKind.floodTrap &&
          room.hunter != null &&
          room.water!.level < room.floor + .7) {
        room.hunter!.vampire.drown();
      }
      // The crossing current starts at the boarding lip, so a raft cannot
      // drift out of reach while earlier puzzles are being solved.
      if (room.rafting && room.water!.level <= room.floor + .2) {
        room.water!.current = stage.player.body.position.x > room.x + 13.5
            ? (room.kind == PuzzleKind.sinkingRaft ? 1.3 : .7)
            : 0;
      }
      room.hunter?.update(dt);
      _runNewRooms(room, dt);
    }
  }

  void _runNewRooms(PuzzleRoom room, double dt) {
    final boy = stage.player;
    if (!boy.isMounted) return;
    final double local = boy.body.position.x - room.x;
    switch (room.kind) {
      case PuzzleKind.plateGate:
        // Open only while weighed down; once he is up the far wall it no
        // longer matters.
        if (local > 25) room.solved = true;
        room.door!.shut = !room.solved && !room.plate!.pressed;
      case PuzzleKind.bridge:
        final bridge = room.bridge!;
        if (bridge.snapped) break;
        final double? fuse = room.bridgeFuse;
        if (fuse == null) {
          if (!boy.isDead && local > 12.4 && local < 19.6) {
            room.bridgeFuse = 3.0;
            stage.cue('creak', at: Vector2(room.x + 16, room.floor));
          }
        } else {
          room.bridgeFuse = fuse - dt;
          if (fuse - dt <= 0) bridge.snap();
        }
      case PuzzleKind.chase:
        final chaser = room.chaser!;
        final v = chaser.vampire;
        if (!room.solved && !room.chaseStarted && !boy.isDead && local > 4.5) {
          room.chaseStarted = true;
          v
            ..revive()
            ..x = room.x - 1
            ..groundY = room.floor
            ..facing = 1
            ..eyes = 1;
          chaser.start();
          stage.cue('shriek', at: Vector2(room.x - 1, room.floor));
        }
        if (!room.solved && room.plate!.pressed) {
          // Dropped behind him: shut out, the vampire goes back.
          room.solved = true;
          room.door!.shut = true;
          stage.cue('gate', at: Vector2(room.x + 27, room.floor), shake: .3);
        }
        if (room.solved && chaser.active) {
          chaser.stop();
          if (!v.gone) v.walkTo(room.x - 8);
        }
        if (room.solved && !v.gone && v.x < room.x + 2) v.gone = true;
        chaser.update(dt);
      case PuzzleKind.rockfall:
        final stones = room.stones!;
        final bool between = !boy.isDead && local > 5 && local < 31;
        if (between && !stones.active) stones.active = true;
        if (!boy.isDead && local >= 31 && stones.active) stones.stop();
      case PuzzleKind.bats:
        final flock = room.bats!;
        if (local > 23) room.solved = true;
        if (!room.solved && !boy.isDead && local > 2) {
          room.batClock -= dt;
          if (room.batClock <= 0) {
            room.batClock = 9;
            final double f = room.floor;
            flock.swarm([
              Vector2(room.x + 30, f - 5),
              Vector2(room.x + 22, f - .95),
              Vector2(room.x + 14, f - .95),
              Vector2(room.x + 10, f - 6),
            ]);
          }
        }
        // Low among them is the end of him.
        if (!boy.isDead && flock.awake) {
          final Vector2 c = boy.body.position;
          for (final bat in flock.bats) {
            final Vector2 b = bat.position;
            if ((b.x - c.x).abs() < .3 && b.y > c.y - .75 && b.y < c.y + .6) {
              boy.die();
              break;
            }
          }
        }
      case PuzzleKind.barrel:
        if (local > 30) room.solved = true;
        // The cask lodged on the plate holds it down for good.
        room.door!.shut =
            !room.solved && !room.plate!.pressed && !room.barrel!.settled;
      case PuzzleKind.wolves:
        final double feet = boy.body.position.y + GameConfig.playerHeight / 2;
        if (!room.solved && !room.chaseStarted && !boy.isDead && local > 4.5) {
          room.chaseStarted = true;
          for (final (i, hunter) in room.pack.indexed) {
            hunter.vampire
              ..revive()
              ..x = room.x - 5 - i * 1.3
              ..groundY = room.floor
              ..facing = 1;
            hunter.start();
          }
          stage.cue('rumble', weight: .6, at: Vector2(room.x - 4, room.floor));
        }
        // On the rock, out of reach: they give up, and go back.
        if (!room.solved &&
            !boy.isDead &&
            local > 17.2 &&
            feet < room.floor - 2) {
          room.solved = true;
        }
        for (final hunter in room.pack) {
          final wolf = hunter.vampire;
          if (room.solved && hunter.active && !boy.isDead) {
            hunter.stop();
            wolf.walkTo(room.x - 12);
          }
          if (room.solved && !wolf.gone && wolf.x < room.x - 3) {
            wolf.gone = true;
          }
          hunter.update(dt);
        }
      case PuzzleKind.levers:
        if (room.solved) break;
        final order = PuzzleRoom.leverOrder;
        final pulls = room.pulls;
        var right = pulls.length <= order.length;
        for (var i = 0; i < pulls.length && right; i++) {
          right = pulls[i] == order[i];
        }
        if (right && pulls.length == order.length) {
          room.solved = true;
          room.door!.shut = false;
          stage.cue('gate', at: Vector2(room.x + 20, room.floor), shake: .3);
        } else if (!right && !boy.isOnRope) {
          // Wrong: every cord back up, and begin again.
          pulls.clear();
          for (final c in room.cords) {
            c.reset();
          }
          stage.cue('gear', at: Vector2(room.x + 10, room.floor - 3));
        }
      case PuzzleKind.sinkingRaft:
        final raft = room.crates.first;
        final Vector2 at = raft.body.position;
        final double feet = boy.body.position.y + GameConfig.playerHeight / 2;
        final bool aboard =
            !boy.isDead &&
            (boy.body.position.x - at.x).abs() < 1.5 &&
            feet < at.y &&
            feet > at.y - .8;
        if (aboard || room.raftTime > 0) room.raftTime += dt;
        if (room.raftTime > 2.2 && raft.isReady) {
          // Waterlogged: it goes down under him.
          final double k = math.min(1.6, (room.raftTime - 2.2) * .55);
          raft.body.applyForce(
            Vector2(
              0,
              raft.body.mass * GameConfig.gravityMetersPerSecondSquared * k,
            ),
          );
        }
      case PuzzleKind.sleeper:
        final hunter = room.chaser!;
        final v = hunter.vampire;
        final double near = (boy.body.position.x - v.x).abs();
        final bool loud =
            !boy.isLow || boy.velocity.x.abs() > 1.2 || !boy.isOnGround;
        if (!room.chaseStarted && !boy.isDead && near < 5.5 && loud) {
          // Woken.
          room.chaseStarted = true;
          v.eyes = 1;
          stage.cue('shriek', at: Vector2(v.x, room.floor - 1.4));
          hunter.start();
        }
        hunter.update(dt);
      case PuzzleKind.twoCrates:
        // A crate gone down into the pit lodges there square, a floor
        // flush with the ground for the other to go over.
        for (final c in room.crates) {
          if (!c.isReady || c.body.type == BodyType.static) continue;
          final Vector2 at = c.body.position;
          if (at.y > room.floor - .45 &&
              at.x > room.x + 21.9 &&
              at.x < room.x + 23.4) {
            c.body
              ..setTransform(
                Vector2(room.x + 22.6, room.floor + .5),
                Rot.fromAngle(0),
              )
              ..type = BodyType.static;
            stage.cue('wood', at: at);
          }
        }
      case PuzzleKind.heavyLight:
        if (local > 23.5) room.solved = true;
        final heavy = room.crates.first;
        if (!room.heavyLocked && heavy.isReady) {
          // Left lying on the plate, it settles into its slot and stays.
          final double hx = heavy.body.position.x - room.x;
          room.heavyRest =
              hx > 12.15 && hx < 13.25 && heavy.body.linearVelocity.length < .2
              ? room.heavyRest + dt
              : 0;
          if (room.heavyRest > .4) {
            room.heavyLocked = true;
            heavy.body.type = BodyType.static;
            stage.cue('gear', at: heavy.body.position);
          }
        }
        room.door!.shut =
            !room.solved && !room.plate!.pressed && !room.heavyLocked;
      case PuzzleKind.boulder:
        final stone = room.barrel!;
        final wall = room.boards!;
        if (!wall.broken && stone.isReady) {
          final Vector2 v = stone.body.linearVelocity;
          if (stone.body.position.x + stone.radius > wall.left - .15 &&
              v.x > 1) {
            wall.shatter();
            // Spent on the boards: it rolls on slowly into the hollow beyond.
            stone.body
              ..linearVelocity = v * .2
              ..angularVelocity = stone.body.angularVelocity * .2;
          }
        }
      case PuzzleKind.barrelRun:
        if (local > 26) room.solved = true;
        if (!room.solved && !boy.isDead && local > 2) {
          room.barrelClock -= dt;
          if (room.barrelClock <= 0) {
            room.barrelClock = 3.3;
            final cask = room.casks[room.nextBarrel++ % room.casks.length];
            if (cask.isReady) {
              cask.body.type = BodyType.dynamic;
              cask.restoreAt(Vector2(room.x + 30, room.floor - 3 - .42));
              cask.body
                ..linearVelocity = Vector2(-2.6, 0)
                ..angularVelocity = -6;
              stage.cue(
                'wood',
                weight: .6,
                at: Vector2(room.x + 30, room.floor - 3),
              );
            }
          }
        }
        // Down past the foot of the slope: back up out of the way.
        for (final (i, c) in room.casks.indexed) {
          if (c.isReady &&
              c.body.type == BodyType.dynamic &&
              c.body.position.x < room.x + 2) {
            c.restoreAt(Vector2(room.x + 31 + i, room.floor - 40));
            c.body.type = BodyType.static;
          }
        }
      case PuzzleKind.floodRise:
        if (!room.floodStarted && !boy.isDead && local > 6.5) {
          room.floodStarted = true;
          room.water!.floodTo(room.floor - 3.9, speed: .42);
          stage.cue('rumble', at: Vector2(room.x + 4, room.floor), shake: .4);
          stage.cue('splash', at: Vector2(room.x + 5, room.floor - 3));
        }
      case PuzzleKind.bell:
        final hunter = room.chaser!;
        final v = hunter.vampire;
        final double bellX = room.x + 4;
        switch (room.bellState) {
          case 0:
            if (room.cord!.pulled && !room.chaseStarted) {
              room.bellState = 1;
              v
                ..walkSpeed = 1.8
                ..walkTo(bellX);
            }
          case 1:
            if ((v.x - bellX).abs() < .1) {
              room.bellState = 2;
              room.bellTimer = 5;
            }
          case 2:
            room.bellTimer -= dt;
            if (room.bellTimer <= 0) {
              room.bellState = 3;
              v
                ..walkSpeed = 1.1
                ..walkTo(room.x + 22);
            }
          case 3:
            if ((v.x - (room.x + 22)).abs() < .1) {
              room.bellState = 0;
              v.patrol(room.x + 19, room.x + 25);
            }
        }
        // In the open in front of him, he sees the boy, and comes.
        final double d = boy.body.position.x - v.x;
        if (!room.chaseStarted &&
            !boy.isDead &&
            !v.gone &&
            !stage.playerHidden &&
            d.abs() < 4.5 &&
            d.sign == v.facing.sign) {
          room.chaseStarted = true;
          stage.cue('shriek', at: Vector2(v.x, room.floor - 1.4));
          hunter.start();
        }
        hunter.update(dt);
      case PuzzleKind.bellGate:
        final hunter = room.chaser!;
        final v = hunter.vampire;
        if (room.gateDelay > 0) {
          room.gateDelay -= dt;
          if (room.gateDelay <= 0 && !room.solved) {
            room.door!.shut = false;
            stage.cue('gate', at: Vector2(room.x + 18, room.floor));
          }
        }
        if (room.cord!.pulled && !room.chaseStarted && !boy.isDead) {
          // The bell has called him.
          room.chaseStarted = true;
          v
            ..revive()
            ..x = room.x - 3
            ..groundY = room.floor
            ..facing = 1
            ..eyes = 1;
          hunter.start();
          stage.cue('shriek', at: Vector2(room.x - 3, room.floor - 1));
        }
        if (!room.solved && room.plate!.pressed) {
          room.solved = true;
          room.door!.shut = true;
          stage.cue('gate', at: Vector2(room.x + 18, room.floor), shake: .3);
        }
        if (room.solved && hunter.active) {
          hunter.stop();
          if (!v.gone) v.walkTo(room.x - 8);
        }
        if (room.solved && !v.gone && v.x < room.x + 2) v.gone = true;
        hunter.update(dt);
      case PuzzleKind.twoPlates:
        if (local > 22) room.solved = true;
        if (room.plate!.pressed && room.plate2!.pressed) {
          room.doorTimer = 1.6;
        } else if (room.doorTimer > 0) {
          room.doorTimer -= dt;
        }
        room.door!.shut = !room.solved && room.doorTimer <= 0;
      case PuzzleKind.timedDoor:
        if (local > 22) room.solved = true;
        if (room.plate!.pressed) {
          room.doorTimer = 4.4;
        } else if (room.doorTimer > 0) {
          room.doorTimer -= dt;
          if (room.doorTimer <= 0 && !room.solved) {
            stage.cue('gate', at: Vector2(room.x + 21, room.floor), shake: .3);
          }
        }
        room.door!.shut = !room.solved && room.doorTimer <= 0;
      case PuzzleKind.collapse:
      case PuzzleKind.fireChase:
      case PuzzleKind.boulderChase:
        if (!room.solved && !boy.isDead && local > 5) room.collapse!.start();
        if (local > 32) room.solved = true;
      case PuzzleKind.crows:
        final hunter = room.chaser!;
        final v = hunter.vampire;
        if (local > 21) room.solved = true;
        if (room.crows!.flushed && !room.chaseStarted && !boy.isDead) {
          room.chaseStarted = true;
          v
            ..revive()
            ..x = room.x + 26
            ..groundY = room.floor
            ..facing = -1
            ..eyes = 1
            ..riseFrom(1.6);
          stage.cue('shriek', at: Vector2(room.x + 26, room.floor - 1));
        }
        if (room.chaseStarted && !hunter.active && v.risen && !boy.isDead) {
          hunter.start();
        }
        hunter.update(dt);
      default:
    }
  }

  void restoreAt(double x) {
    for (final room in rooms) {
      if (room.end >= x) room.restore();
      if (room.end < x) {
        for (final restore in room.completed) {
          restore();
        }
        if (room.hunter != null) room.hunter!.vampire.gone = true;
      }
    }
  }
}

/// The posts of a gate's frame, standing either side of the way.
class _GatePosts extends Component implements HasFootprint {
  _GatePosts(this.at, this.floor) : super(priority: -3);
  final double at, floor;

  @override
  Rect get footprint => Rect.fromLTRB(at - 1.05, floor - 4.2, at + 1.05, floor);

  static final Paint _stone = Paint()..color = const Color(0xFF060606);

  @override
  void render(Canvas canvas) {
    for (final side in const [-1.0, 1.0]) {
      canvas.drawRect(
        Rect.fromLTRB(
          at + side * .65 - (side < 0 ? .4 : 0),
          floor - 4.2,
          at + side * .65 + (side > 0 ? .4 : 0),
          floor + .05,
        ),
        _stone,
      );
    }
  }
}

class _Cover extends Component implements HasFootprint {
  _Cover(this.bounds) : super(priority: -2);
  final Rect bounds;

  @override
  Rect get footprint => bounds;
  @override
  void render(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(bounds, const Radius.circular(.2)),
      Paint()..color = const Color(0xff020303),
    );
    canvas.drawLine(
      bounds.topLeft,
      bounds.topRight,
      Paint()
        ..color = const Color(0x506a6b69)
        ..strokeWidth = .06,
    );
  }
}

/// A bell hung from a bracket in the wall.
class _Bell extends Component implements HasFootprint {
  _Bell(this.x, this.y) : super(priority: -2);
  final double x, y;

  @override
  Rect get footprint => Rect.fromLTRB(x - .5, y - .6, x + .5, y + .7);

  static final Paint _iron = Paint()..color = const Color(0xFF070707);

  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTRB(x - .6, y - .65, x + .1, y - .55), _iron);
    canvas.drawPath(
      Path()
        ..moveTo(x - .12, y - .55)
        ..quadraticBezierTo(x - .3, y + .1, x - .45, y + .55)
        ..lineTo(x + .45, y + .55)
        ..quadraticBezierTo(x + .3, y + .1, x + .12, y - .55)
        ..close(),
      _iron,
    );
    canvas.drawCircle(Offset(x, y + .62), .09, _iron);
  }
}

/// A grave: a mound and a leaning stone, where something sleeps.
class _Grave extends Component implements HasFootprint {
  _Grave(this.at, this.floor) : super(priority: -2);
  final double at, floor;

  @override
  Rect get footprint => Rect.fromLTRB(at - 1.2, floor - 1.1, at + 1.2, floor);

  static final Paint _earth = Paint()..color = const Color(0xFF050505);

  @override
  void render(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(at - 1.2, floor + .05)
        ..quadraticBezierTo(at - .2, floor - .38, at + 1.0, floor + .05)
        ..close(),
      _earth,
    );
    canvas.save();
    canvas.translate(at + .85, floor);
    canvas.rotate(.12);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        const Rect.fromLTRB(-.22, -1.05, .22, .05),
        topLeft: const Radius.circular(.2),
        topRight: const Radius.circular(.2),
      ),
      _earth,
    );
    canvas.restore();
  }
}

/// A visible connection from the upper control to the lower drain.
class _SluiceLink extends Component {
  _SluiceLink(this.x, this.floor, this.open) : super(priority: 1);
  final double x, floor;
  final bool Function() open;
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = .07;

  @override
  void render(Canvas canvas) {
    _paint.color = open() ? const Color(0xff777b79) : const Color(0xff414543);
    canvas.drawPath(
      Path()
        ..moveTo(x + 28.5, floor - 3.4)
        ..lineTo(x + 28.5, floor - 1.2)
        ..lineTo(x + 35, floor - 1.2)
        ..lineTo(x + 35, floor - .25),
      _paint,
    );
    final valve = Offset(x + 28.5, floor - 2.2);
    canvas.drawCircle(valve, .24, _paint);
    final spoke = open() ? const Offset(0, .2) : const Offset(.2, 0);
    canvas.drawLine(valve - spoke, valve + spoke, _paint);
  }
}
