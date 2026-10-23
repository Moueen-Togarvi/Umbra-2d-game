import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show BodyType, Forge2DGame;

import '../world/footprint.dart';

/// The way out at a chapter's end: a gate of the place's own kind (timber
/// at the forest's edge, a cave's stone arch, a castle's portcullis) with
/// the moon cut in it, standing on the ground across the path. He walks
/// through it, and the chapter is over.
class ChapterExitGate extends Component implements HasFootprint {
  ChapterExitGate({
    required this.design,
    required this.x,
    required this.groundAt,
  }) : height = _heights[design] ?? 3.4,
       super(priority: -3);

  /// Which of the fifteen gates (ch01 … ch15, baked by
  /// tools/bake_exit_gates.py).
  final String design;

  /// Where it stands, its middle, world metres.
  final double x;
  final double Function(double x) groundAt;

  /// How tall it is meant to stand, metres; less under a low roof.
  double height;

  static const _heights = {
    'ch01': 3.3, 'ch02': 3.5, 'ch03': 3.2, 'ch04': 3.4, 'ch05': 3.7, //
    'ch06': 3.4, 'ch07': 3.2, 'ch08': 3.7, 'ch09': 3.8, 'ch10': 3.6,
    'ch11': 3.0, 'ch12': 3.2, 'ch13': 4.0, 'ch14': 3.4, 'ch15': 3.2,
  };

  /// The gate for each chapter, by its campaign id: the original fifteen
  /// keep their own, the rest take the one most like their place.
  static const designFor = {
    'home': 'ch01',
    'old_orchard': 'ch15',
    'hunters_road': 'ch02',
    'graveyard': 'ch05',
    'forest': 'ch02',
    'cage': 'ch03',
    'chainworks': 'ch03',
    'caves': 'ch04',
    'sluice_tunnels': 'ch06',
    'drowned_quarry': 'ch04',
    'crypt': 'ch05',
    'coffin_gallery': 'ch08',
    'bone_pit': 'ch06',
    'floodworks': 'ch12',
    'lower_castle': 'ch07',
    'chase': 'ch07',
    'servants_passage': 'ch11',
    'halls': 'ch08',
    'shadow_gallery': 'ch09',
    'chandeliers': 'ch09',
    'organ_loft': 'ch08',
    'clock_tower': 'ch10',
    'bell_foundry': 'ch10',
    'watchers_walk': 'ch13',
    'children': 'ch11',
    'abandoned_ward': 'ch06',
    'drainways': 'ch04',
    'mill': 'ch12',
    'broken_aqueduct': 'ch12',
    'black_reservoir': 'ch14',
    'furnace_passage': 'ch07',
    'outer_ramparts': 'ch13',
    'great_gate': 'ch13',
    'moat': 'ch14',
    'storm': 'ch14',
    'shattered_coast': 'ch14',
    'last_watch': 'ch01',
    'eastern_woods': 'ch02',
    'homeward_road': 'ch15',
    'dawn': 'ch15',
  };

  Image? _art;
  double _width = 0, _base = 0;
  bool _placed = false;

  @override
  Rect get footprint =>
      Rect.fromLTRB(x - 1.8, groundAt(x) - height, x + 1.8, groundAt(x));

  @override
  void onLoad() {
    // Not waited for: the chapter starts as it would without it, and the
    // gate is stood up once its picture is in (long before he gets there).
    Flame.images
        .load('exits/$design.webp')
        .then<void>(
          (art) => _art = art,
          // Missing art (a bare test binding): nothing to draw.
          onError: (Object _) {},
        );
  }

  /// Stood on the ground once the world is there to stand on: the higher
  /// of its two feet set on the ground (the other sunk a little, never
  /// floating), and no taller than the room under any roof above.
  void _place() {
    final Image? art = _art;
    if (art == null) return;
    final game = findGame();
    if (game is! Forge2DGame) return;
    final physics = game.world.physicsWorld;
    // What he walks on there: the floor of the place, or a slab laid on it.
    double surfaceAt(double at) {
      double floor = groundAt(at);
      physics.castRay(Vector2(at, floor - 1.2), Vector2(0, 2.4), (hit) {
        if (hit.shape.isSensor ||
            hit.shape.body.type != BodyType.static ||
            hit.normal.y > -.5) {
          return -1;
        }
        floor = math.min(floor, hit.point.y);
        return hit.fraction;
      });
      return floor;
    }

    double ground = surfaceAt(x);
    {
      physics.castRay(Vector2(x, ground - .15), Vector2(0, -height - 1), (hit) {
        if (hit.shape.isSensor ||
            hit.shape.body.type != BodyType.static ||
            hit.normal.y < .5) {
          return -1;
        }
        final double room = ground - hit.point.y - .2;
        if (room < height) height = math.max(1.9, room);
        return 1;
      });
    }
    _width = height * art.width / art.height;
    for (final foot in [x - _width * .36, x + _width * .36]) {
      ground = math.max(ground, surfaceAt(foot));
    }
    _base = ground + .035;
    _placed = true;
  }

  @override
  void update(double dt) {
    if (!_placed && _art != null) _place();
  }

  static final Paint _paint = Paint()
    ..filterQuality = FilterQuality.medium
    // A shade darker than painted: it stands in the dark with the rest.
    ..colorFilter = const ColorFilter.mode(
      Color(0xFF9A9A9A),
      BlendMode.modulate,
    );

  @override
  void render(Canvas canvas) {
    final Image? art = _art;
    if (art == null || !_placed) return;
    canvas.drawImageRect(
      art,
      Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
      Rect.fromLTRB(x - _width / 2, _base - height, x + _width / 2, _base),
      _paint,
    );
  }
}
