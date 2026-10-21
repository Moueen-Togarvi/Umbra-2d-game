import 'dart:math' as math;

import 'package:flame/components.dart' show Component;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../entities/ground.dart';
import '../entities/hill_ground.dart';
import '../entities/player.dart';
import '../render/scenery.dart';
import '../render/white_blossom_tree.dart';
import 'chapter.dart';

/// Settles the trees and other standing decoration of [chapter] on the
/// ground, each on a clear piece of it: not in front of a crate, a block,
/// a log or another tree, not over a pit, and with its foot sunk into the
/// lowest ground under it so no light shows beneath.
///
/// Runs once [pieces] have loaded (bodies exist, art is in).
void arrangeSurfaceDecor(Chapter chapter, List<Component> pieces) {
  // What else stands on the ground, as spans of x.
  final busy = <(double, double)>[];
  for (final body in pieces.whereType<BodyComponent>()) {
    if (body is HillGround || body is Player) continue;
    if (body is Ground && body.style == GroundStyle.wall) continue;
    if (!body.isLoaded || !body.body.isValid) continue;
    for (final shape in body.body.shapes) {
      final box = shape.aabb;
      // Very tall things are the ends of the world, not props.
      if (box.upperBound.y - box.lowerBound.y > 8) continue;
      busy.add((box.lowerBound.x, box.upperBound.x));
    }
  }
  // Decoration standing on the ground, widest first so it gets the space.
  final decor = <_Decor>[
    for (final tree in pieces.whereType<WhiteBlossomTree>())
      _Decor(
        () => tree.position.x,
        tree.size.x * 1.0,
        (x, y) => tree.position.setValues(x, y),
      ),
    for (final prop in pieces.whereType<SceneryProp>())
      if (prop.standsOnPath && _onGround(chapter, prop))
        _Decor(
          () => prop.x,
          prop.rectFor(Vector2(prop.x, prop.baseY)).width * 0.95,
          (x, y) {
            prop.x = x;
            prop.baseY = y;
          },
        ),
  ]..sort((a, b) => b.width.compareTo(a.width));

  const double margin = 0.6;
  bool clear(double left, double right) {
    for (final (l, r) in busy) {
      if (right + margin > l && left - margin < r) return false;
    }
    final segment = chapter.terrain.segmentAt(left - 0.3);
    return segment != null &&
        identical(segment, chapter.terrain.segmentAt(right + 0.3));
  }

  for (final item in decor) {
    final double half = item.width / 2;
    final double from = item.x();
    double? spot;
    for (var step = 0; step <= 160 && spot == null; step++) {
      for (final side in step == 0 ? const [1.0] : const [1.0, -1.0]) {
        final double x = from + side * step * 0.25;
        if (x - half < 1 || x + half > chapter.width - 1) continue;
        if (clear(x - half, x + half)) {
          spot = x;
          break;
        }
      }
    }
    // Nowhere clear nearby: left where it was, but still on the ground.
    final double x = spot ?? from;
    // The foot in the lowest ground under the trunk.
    final double trunk = math.min(half, 0.35);
    final double foot = [
      chapter.groundAt(x - trunk),
      chapter.groundAt(x),
      chapter.groundAt(x + trunk),
    ].reduce(math.max);
    item.place(x, foot + 0.12);
    if (spot != null) busy.add((x - half, x + half));
  }
}

/// Whether [prop] stands on the ground (rather than hanging from a roof).
bool _onGround(Chapter chapter, SceneryProp prop) {
  if (chapter.terrain.segmentAt(prop.x) == null) return false;
  return (prop.baseY - chapter.groundAt(prop.x)).abs() < 0.8;
}

class _Decor {
  _Decor(this.x, this.width, this.place);
  final double Function() x;
  final double width;
  final void Function(double x, double y) place;
}
