import 'dart:math' as math;

import 'package:flame/game.dart' show Vector2;

/// Earth shelves and banks separated by pits. Collision, drawing and foot
/// placement all read the same sampled surface.
class Terrain {
  Terrain(List<List<Vector2>> profile)
    : segments = [for (final controls in profile) TerrainSegment(controls)];

  /// Left to right. The gap between two segments is a pit.
  final List<TerrainSegment> segments;

  /// The stretch of ground under [x], or null over a pit.
  TerrainSegment? segmentAt(double x) {
    for (final segment in segments) {
      if (x >= segment.left && x <= segment.right) {
        return segment;
      }
    }
    return null;
  }

  /// Height of the surface at [x] (y down, so smaller is higher), or null
  /// over a pit.
  double? heightAt(double x) => segmentAt(x)?.heightAt(x);

  /// Gradient dy/dx of the surface at [x]; 0 over a pit. Negative means the
  /// ground rises to the right, because y points down.
  double slopeAt(double x) => segmentAt(x)?.slopeAt(x) ?? 0;
}

/// One unbroken stretch of ground between two pits (or the level's ends).
class TerrainSegment {
  TerrainSegment(this.controls)
    : assert(controls.length >= 2),
      surface = _sample(controls);

  /// The hand-placed points, left to right.
  final List<Vector2> controls;

  /// Collision vertices, including every hand-placed point. Drawing and
  /// surface queries use these exact vertices too.
  final List<Vector2> surface;

  /// Fine enough for a small capsule to cross the banks without catching
  /// on visible corners.
  static const double sampleStep = 0.12;

  double get left => controls.first.x;
  double get right => controls.last.x;

  /// Height at [x], clamped to the segment's ends.
  double heightAt(double x) {
    final int i = _surfaceIndex(x);
    final Vector2 a = surface[i];
    final Vector2 b = surface[i + 1];
    final double t = ((x - a.x) / (b.x - a.x)).clamp(0.0, 1.0);
    return a.y + (b.y - a.y) * t;
  }

  /// Gradient of the collision edge beneath [x].
  double slopeAt(double x) {
    final int i = _surfaceIndex(x);
    final Vector2 a = surface[i];
    final Vector2 b = surface[i + 1];
    return (b.y - a.y) / (b.x - a.x);
  }

  int _surfaceIndex(double x) {
    var low = 0;
    var high = surface.length - 2;
    while (low < high) {
      final int middle = (low + high) ~/ 2;
      if (x > surface[middle + 1].x) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  // Shape-preserving Hermite slopes keep a flat shelf flat and a bank
  // between its control heights, instead of creating a hump at every join.
  double _tangent(int i) {
    if (i == 0 || i == controls.length - 1) {
      return 0;
    }
    final double before = controls[i].x - controls[i - 1].x;
    final double after = controls[i + 1].x - controls[i].x;
    final double incoming = (controls[i].y - controls[i - 1].y) / before;
    final double outgoing = (controls[i + 1].y - controls[i].y) / after;
    if (incoming * outgoing <= 0) return 0;
    final double w1 = 2 * after + before;
    final double w2 = after + 2 * before;
    return (w1 + w2) / (w1 / incoming + w2 / outgoing);
  }

  double _hermite(double x, int i) {
    final Vector2 p0 = controls[i];
    final Vector2 p1 = controls[i + 1];
    final double h = p1.x - p0.x;
    final double t = ((x - p0.x) / h).clamp(0.0, 1.0);
    final double m0 = _tangent(i) * h;
    final double m1 = _tangent(i + 1) * h;
    final double t2 = t * t;
    final double t3 = t2 * t;
    return (2 * t3 - 3 * t2 + 1) * p0.y +
        (t3 - 2 * t2 + t) * m0 +
        (-2 * t3 + 3 * t2) * p1.y +
        (t3 - t2) * m1;
  }

  static List<Vector2> _sample(List<Vector2> controls) {
    final segment = TerrainSegment._raw(controls);
    final points = <Vector2>[controls.first.clone()];
    for (var i = 0; i < controls.length - 1; i++) {
      final Vector2 a = controls[i];
      final Vector2 b = controls[i + 1];
      final int count = ((b.x - a.x) / sampleStep).ceil();
      for (var k = 1; k <= count; k++) {
        final double t = k / count;
        final double x = a.x + (b.x - a.x) * t;
        // A little settled earth variation is part of collision too. It
        // fades at the joins and leaves intentionally level shelves level.
        final double envelope = math.pow(math.sin(math.pi * t), 2).toDouble();
        final double earth = a.y == b.y
            ? 0
            : envelope *
                  (0.018 * math.sin(x * 2.3) + 0.009 * math.sin(x * 4.4 + 1.1));
        points.add(Vector2(x, segment._hermite(x, i) + earth));
      }
    }
    return points;
  }

  /// A segment with no sampled surface, used only to run the curve while
  /// sampling it.
  TerrainSegment._raw(this.controls) : surface = const [];
}
