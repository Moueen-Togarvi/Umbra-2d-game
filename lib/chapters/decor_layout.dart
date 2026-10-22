import 'dart:math' as math;

import 'package:flame/components.dart' show Component;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../entities/hill_ground.dart';
import '../entities/player.dart';
import '../render/scenery.dart';
import '../render/white_blossom_tree.dart';
import '../world/footprint.dart';
import 'chapter.dart';

/// Settles the trees and other standing decoration of [chapter] on the
/// ground, each on a clear piece of it: not in front of a crate, a block,
/// a wall, a window's shutters, a hiding place or another tree, not under a
/// low roof, not over a pit, and with its foot sunk into the lowest ground
/// under it so no light shows beneath.
///
/// Runs once everything in the chapter ([all], its rooms' pieces too) has
/// loaded, so their bodies exist.
void arrangeSurfaceDecor(Chapter chapter, Iterable<Component> all) {
  final pieces = all.toList();
  // What else takes up the room a tree needs, as spans of x.
  final busy = <(double, double)>[];
  void block(double left, double right, double top, double bottom) {
    // The outline of the whole place is not a thing standing in it.
    if (right - left > chapter.width * 0.6) return;
    final double ground = chapter.groundAt((left + right) / 2);
    // The floor itself, and what is wholly above a tree's crown, are not
    // in its way.
    if (top >= ground - 0.2 || bottom < ground - _crown) return;
    busy.add((left, right));
  }

  for (final body in pieces.whereType<BodyComponent>()) {
    if (body is HillGround || body is Player) continue;
    if (!body.isLoaded || !body.body.isValid) continue;
    for (final shape in body.body.shapes) {
      final box = shape.aabb;
      block(
        box.lowerBound.x,
        box.upperBound.x,
        box.lowerBound.y,
        box.upperBound.y,
      );
    }
  }
  // What is drawn without a body: shutters, cell fronts, drains, covers.
  for (final thing in pieces.whereType<HasFootprint>()) {
    final box = thing.footprint;
    block(box.left, box.right, box.top, box.bottom);
  }
  // Near props hung from above (cages, chains, lamps) are in the way of a
  // crown as much as anything standing.
  for (final prop in pieces.whereType<SceneryProp>()) {
    if (!prop.standsOnPath || _onGround(chapter, prop)) continue;
    final rect = prop.rectFor(Vector2(prop.x, prop.baseY));
    block(rect.left, rect.right, rect.top, rect.bottom);
  }
  for (final cover in chapter.hidingPlaces) {
    if (cover.isEmpty) continue;
    block(cover.left, cover.right, cover.top, cover.bottom);
  }
  // Decoration standing on the ground, widest first so it gets the space.
  final decor = <_Decor>[
    for (final tree in pieces.whereType<WhiteBlossomTree>())
      _Decor(
        () => tree.position.x,
        tree.size.x * 1.0,
        (x, y) => tree.position.setValues(x, y),
        tree.removeFromParent,
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
          prop.removeFromParent,
        ),
  ]..sort((a, b) => b.width.compareTo(a.width));

  const double margin = 0.9;
  bool clear(double left, double right) {
    for (final (l, r) in busy) {
      if (right + margin > l && left - margin < r) return false;
    }
    final segment = chapter.terrain.segmentAt(left - 0.3);
    if (segment == null ||
        !identical(segment, chapter.terrain.segmentAt(right + 0.3))) {
      return false;
    }
    // Level under the trunk, and no step under the crown: a tree on the
    // edge of a stair stands half hidden behind it.
    double spread(double from, double to) {
      var low = double.infinity, high = -double.infinity;
      for (var x = from; x <= to; x += 0.5) {
        final double g = chapter.groundAt(x);
        low = math.min(low, g);
        high = math.max(high, g);
      }
      return high - low;
    }

    final double mid = (left + right) / 2;
    return spread(mid - 0.6, mid + 0.6) < 0.25 && spread(left, right) < 1.0;
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
    // Nowhere clear: better no tree there than one stood in front of
    // something.
    if (spot == null) {
      item.drop();
      continue;
    }
    final double x = spot;
    // The foot in the lowest ground under the trunk.
    final double trunk = math.min(half, 0.35);
    final double foot = [
      chapter.groundAt(x - trunk),
      chapter.groundAt(x),
      chapter.groundAt(x + trunk),
    ].reduce(math.max);
    item.place(x, foot + 0.12);
    busy.add((x - half, x + half));
  }
}

/// How far above the ground the tallest tree's crown reaches, metres.
const double _crown = 5.2;

/// Whether [prop] stands on the ground (rather than hanging from a roof).
bool _onGround(Chapter chapter, SceneryProp prop) {
  if (chapter.terrain.segmentAt(prop.x) == null) return false;
  return (prop.baseY - chapter.groundAt(prop.x)).abs() < 0.8;
}

class _Decor {
  _Decor(this.x, this.width, this.place, this.drop);
  final double Function() x;
  final double width;
  final void Function(double x, double y) place;
  final void Function() drop;
}
