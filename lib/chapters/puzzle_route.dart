import 'dart:ui';
import 'dart:math' as math;
import 'package:flame/components.dart';
import '../world/footprint.dart';
import '../entities/ground.dart';
import '../entities/home_props.dart';
import '../entities/physics_props.dart';
import '../entities/castle_props.dart';
import '../entities/cave_props.dart';
import '../entities/clock_props.dart';
import '../entities/dungeon_props.dart';
import '../entities/water_props.dart';
import '../physics/water.dart';
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
    PuzzleKind.raft || PuzzleKind.floodTrap => (x + 14, x + 22),
    PuzzleKind.pendulum => (x + 13.5, x + 21.5),
    PuzzleKind.cages => (x + 14, x + 20),
    PuzzleKind.weight => (x + 14, x + 16.2),
    PuzzleKind.seesaw => (x + 14, x + 19),
    _ => null,
  };
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
    if (kind == PuzzleKind.raft || kind == PuzzleKind.floodTrap) {
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
      if ((room.kind == PuzzleKind.raft || room.kind == PuzzleKind.floodTrap) &&
          room.water!.level <= room.floor + .2) {
        room.water!.current = stage.player.body.position.x > room.x + 13.5
            ? .7
            : 0;
      }
      room.hunter?.update(dt);
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
