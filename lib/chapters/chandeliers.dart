import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/castle_props.dart';
import '../entities/ground.dart';
import '../entities/hazard.dart';
import '../render/fog_backdrop.dart';
import '../render/fog_layer.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import '../story/cutscene.dart';
import '../story/hunters.dart';
import '../story/vampire.dart';
import 'chapter.dart';

/// Chapter nine, The Chandeliers.
///
/// The great ballroom. Its floor has fallen in; what is left of it stands
/// in islands over the dark, and the chandeliers still hang from the vault
/// on their long ropes, lit: he swings from one to the next. Up the stairs
/// to the musicians' gallery. Beyond it the floor is broken by a pit too
/// wide to jump, and in it two of them wait for him, under a great unlit
/// chandelier. A cord hangs from the gallery's end; his weight on it lets
/// the chandelier's rope run: it comes down on them, and its ring, wider
/// than the pit, catches on both edges and makes his bridge. Last,
/// the keeper again, out of the dark behind him, and one more chandelier,
/// hung over the edge of the last gap, its cord the only way across.
///
/// ```
///  0  16–31.4 three chandeliers over the fallen floor  32–41 stairs
///  41–49 gallery (cord 48)  55–57.4 the pit  62 the keeper
///  72–73.8 hole  80 table  85.5 the last chandelier  88–91.4 the gap
///  124 out
/// ```
class ChandeliersChapter extends Chapter {
  ChandeliersChapter({required super.intent});

  @override
  int get number => 9;
  @override
  String get title => 'The Chandeliers';
  @override
  double get width => 130;
  @override
  MoodTrack get moods => const MoodTrack(Mood.castle);
  @override
  List<FogLayerSpec>? get backdropSpecs => FogBackdrop.hallSpecs;
  @override
  bool get grassy => false;

  static const double floor = 7.0;
  static const double gallery = 4.0;
  static const double danceLeft = 55.0, danceRight = 57.4, danceFloor = 9.0;
  static const double holeLeft = 72, holeRight = 73.8;
  static const double gapLeft = 88, gapRight = 91.4;
  static const double galleryRight = 49;

  @override
  List<List<double>> get profile => const [
    [0, floor, 8, floor, 16, floor],
    [19.4, floor, 22.0, floor],
    [25.4, floor, 28.0, floor],
    [
      31.4, floor, 32, floor, 41, gallery, galleryRight, gallery, //
      galleryRight + 0.3, floor, danceLeft, floor,
    ],
    [danceRight, floor, holeLeft, floor],
    [holeRight, floor, gapLeft, floor],
    [gapRight, floor, 130, floor],
  ];

  @override
  List<double> get checkpointXs => const [12, 32.5, 47, 62, 82, 94];

  @override
  Vector2 get spawn => Vector2(3, floor - GameConfig.playerHeight / 2);

  @override
  double get exitX => 124;

  @override
  List<String> get art => const [
    'part3/ch9_far_chandelier.png',
    'part3/ch9_far_chandelier_far.png',
    'part3/ch9_gallery.png',
    'part3/ch9_gallery_far.png',
    'part3/ch9_grand_stair.png',
    'part3/ch9_grand_stair_far.png',
    'part3/ch9_pipe_organ.png',
    'part3/ch9_pipe_organ_far.png',
    'part3/ch9_throne.png',
    'part3/ch8_banners.png',
  ];

  final List<ChandelierRope> swings = [];
  late final HungChandelier great, last;
  late final PullCord greatCord, lastCord;
  final List<Vampire> guards = [
    Vampire(x: 55.7, groundY: danceFloor, facing: -1),
    Vampire(x: 56.8, groundY: danceFloor, facing: -1),
  ];
  final List<Stalker> _guarding = [];
  final Vampire keeper = Vampire(x: 61, groundY: floor, facing: 1);
  late final Pursuer pursuer = Pursuer(keeper, stage: this);
  bool chasing = false;
  double _restart = 0;
  double _atGap = 0;

  double _ground(double x) =>
      x > danceLeft && x < danceRight ? danceFloor : floor;

  @override
  List<Component> buildPit(int index, double left, double right, double lip) {
    if (left == danceLeft) {
      // The pit where they wait: a stone floor two metres down.
      return [
        Ground.slab(
          left: left - 0.1,
          right: right + 0.1,
          top: danceFloor,
          thickness: height + 2 - danceFloor,
        ),
      ];
    }
    // The ballroom's floor fell into the dark cellars: no stakes, a drop.
    return [
      Hazard.zone(
        left: left,
        right: right,
        top: lip + GameConfig.pitDepth + 1,
        bottom: height,
        stakes: false,
      ),
    ];
  }

  @override
  Future<void> furnish(List<Component> pieces) async {
    pieces.add(LightLayer());
    // --- The vault ----------------------------------------------------------
    pieces.add(
      StoneBlock(left: -3, top: -8, right: 133, bottom: -2.2, seed: 61),
    );

    // --- Art ---------------------------------------------------------------
    pieces.addAll([
      SceneryProp(
        'part3/ch9_grand_stair.png',
        x: 6,
        baseY: 7.6,
        height: 6.5,
        depth: 0.6,
      ),
      for (final x in const [30.0, 74.0, 112.0])
        SceneryProp(
          'part3/ch9_gallery.png',
          x: x,
          baseY: 7.6,
          height: 7.0,
          depth: 0.5,
        ),
      SceneryProp(
        'part3/ch9_pipe_organ.png',
        x: 54,
        baseY: 7.6,
        height: 9.0,
        depth: 0.62,
      ),
      for (final (double x, double y) in const [
        (14.0, -1.0),
        (40.0, -1.4),
        (68.0, -1.0),
        (100.0, -1.2),
      ])
        SceneryProp(
          'part3/ch9_far_chandelier.png',
          x: x,
          baseY: y + 3.6,
          height: 3.6,
          depth: 0.55,
        ),
      SceneryProp(
        'part3/ch9_throne.png',
        x: 116,
        baseY: floor + 0.1,
        height: 3.2,
        depth: 0.92,
        fog: 0.12,
        priority: -32,
      ),
      for (final x in const [42.0, 96.0])
        SceneryProp(
          'part3/ch8_banners.png',
          x: x,
          baseY: 2.6,
          height: 3.0,
          depth: 0.9,
          fog: 0.12,
          priority: -35,
        ),
    ]);

    // --- The stair up to the gallery, and its balustrade --------------------
    pieces.addAll([
      Staircase(
        from: Vector2(32, floor),
        to: Vector2(41, gallery),
        surface: groundAt,
      ),
      Balustrade(left: 41.3, right: galleryRight - 0.2, floorY: gallery),
    ]);

    // --- Over the fallen floor, on the chandeliers --------------------------
    for (final x in const [17.8, 23.8, 29.8]) {
      swings.add(ChandelierRope(anchor: Vector2(x, floor - 4.5), length: 3.6));
    }
    pieces.addAll(swings);

    // --- The gallery and the dance floor ------------------------------------
    great = HungChandelier(
      anchor: Vector2((danceLeft + danceRight) / 2, -2.2),
      ropeLength: 1.6,
      width: 2.9,
      lit: false,
    );
    greatCord = PullCord(
      anchor: Vector2(galleryRight - 1.0, gallery - 4.5),
      length: 3.6,
      onPulled: great.release,
    );
    for (final guard in guards) {
      _guarding.add(
        Stalker(
          guard,
          stage: this,
          ground: _ground,
          // They keep to their pit.
          left: danceLeft + 0.3,
          right: danceRight - 0.3,
          wake: 9,
        ),
      );
    }
    pieces.addAll([great, greatCord, ...guards]);

    // --- The last chandelier and the gap ------------------------------------
    last = HungChandelier(
      anchor: Vector2(gapLeft - 1.2, -2.2),
      ropeLength: 1.8,
      width: 2.6,
    );
    lastCord = PullCord(
      anchor: Vector2(gapLeft + 1.8, floor - 4.5),
      length: 3.6,
      onPulled: last.release,
    );
    pieces.addAll([
      CastleTable(left: 80, right: 82.2, floorY: floor),
      last,
      lastCord,
      keeper..gone = true,
    ]);
  }

  @override
  void begin() {
    onReach(65, () => play(_keeper()));
  }

  /// Out of the dark behind him: the keeper, dropping from the gallery.
  Cutscene _keeper() => Cutscene([
    Do((_) {
      keeper
        ..revive()
        ..x = 61.2
        ..groundY = floor
        ..facing = 1
        ..eyes = 1
        ..dropFrom(3.4);
      player.forceLookBack = true;
    }),
    Look(Vector2(63, 5.2)),
    Wait(1.2),
    Do((_) {
      player.forceLookBack = false;
      _startChase();
    }),
    Look(null),
  ]);

  void _startChase() {
    chasing = true;
    pursuer.start();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!player.isMounted) return;
    for (final hunt in _guarding) {
      hunt.update(dt);
    }
    if (_restart > 0) {
      _restart -= dt;
      if (_restart <= 0) _startChase();
    }
    if (chasing) pursuer.update(dt);
    // What a falling chandelier comes down on.
    for (final chandelier in [great, last]) {
      if (!chandelier.crushing) continue;
      for (final v in [...guards, keeper]) {
        if (v.gone) continue;
        if ((v.x - chandelier.body.position.x).abs() <
                chandelier.width * 0.45 &&
            chandelier.bottom > v.groundY - Vampire.height) {
          v.crush();
          if (v == keeper) pursuer.stop();
        }
      }
    }
    // Stopped at the last gap: he reaches across a while, then goes.
    if (chasing && pursuer.blocked && player.body.position.x > gapRight) {
      _atGap += dt;
      if (_atGap > 3.5) {
        chasing = false;
        pursuer.stop();
        keeper
          ..reachGoal = 0
          ..walkTo(62);
      }
    }
    if (!chasing && keeper.mode == VampireMode.walk && keeper.x < 72) {
      keeper.gone = true;
    }
  }

  @override
  void onRespawned() {
    final double at = checkpoints.activeCheckpoint.x;
    if (at < danceRight) {
      great.rehang();
      greatCord.reset();
      for (var i = 0; i < guards.length; i++) {
        _guarding[i].reset(i == 0 ? 55.7 : 56.8);
        guards[i].facing = -1;
      }
    }
    _atGap = 0;
    if (at < gapLeft) {
      last.rehang();
      lastCord.reset();
    }
    if (at >= 62 && at < gapLeft && (chasing || pursuer.caught)) {
      final double from = at - 8;
      keeper
        ..revive()
        ..x = from
        ..groundY = _ground(from)
        ..facing = 1
        ..eyes = 1;
      chasing = false;
      pursuer.stop();
      _restart = 1.2;
    } else if (at >= gapLeft) {
      chasing = false;
      pursuer.stop();
      keeper.gone = true;
    }
  }
}
