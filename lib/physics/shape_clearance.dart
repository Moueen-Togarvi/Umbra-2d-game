import 'dart:math' as math;
import 'package:flame_forge2d/flame_forge2d.dart';

/// Closed chain bodies expose their filled region for placement queries;
/// Box2D chain segments themselves only describe the boundary.
abstract interface class SolidOutline {
  List<Vector2> get solidOutline;
}

/// Narrow-phase clearance for the player's upright capsule. Broad-phase AABBs
/// alone reject safe positions beside tilted crates and padded chain edges.
/// Box2D still handles all contact response; this only validates mantle targets.
bool capsuleOverlapsShape(
  Shape shape,
  Vector2 centre,
  double width,
  double height, {
  double skin = .025,
}) {
  final radius = math.max(.001, width / 2 - skin);
  final halfAxis = math.max(0.0, (height - width) / 2);
  final a = centre - Vector2(0, halfAxis), b = centre + Vector2(0, halfAxis);
  final body = shape.body;
  final region = body.userData;
  if (region is SolidOutline &&
      pointInsideOutline(body.localPoint(centre), region.solidOutline)) {
    return true;
  }
  final geometry = shape.geometry;
  switch (geometry) {
    case Circle():
      return _pointSegment(body.worldPoint(geometry.center), a, b) <
          math.pow(radius + geometry.radius, 2);
    case Capsule():
      return _segments(
            a,
            b,
            body.worldPoint(geometry.center1),
            body.worldPoint(geometry.center2),
          ) <
          math.pow(radius + geometry.radius, 2);
    case Segment():
      return _segments(
            a,
            b,
            body.worldPoint(geometry.point1),
            body.worldPoint(geometry.point2),
          ) <
          radius * radius;
    case Polygon():
      if (shape.testPoint(a) || shape.testPoint(b) || shape.testPoint(centre)) {
        return true;
      }
      // Read-back polygon geometry always contains its convex-hull vertices.
      final points = geometry.points!
          .map(body.worldPoint)
          .toList(growable: false);
      final squared = math.pow(radius + geometry.radius, 2);
      for (var i = 0; i < points.length; i++) {
        if (_segments(a, b, points[i], points[(i + 1) % points.length]) <
            squared) {
          return true;
        }
      }
      return false;
  }
}

double _pointSegment(Vector2 p, Vector2 a, Vector2 b) {
  final ab = b - a;
  final t = ab.length2 < 1e-12
      ? 0.0
      : ((p - a).dot(ab) / ab.length2).clamp(0.0, 1.0);
  return (p - (a + ab * t)).length2;
}

double _cross(Vector2 a, Vector2 b) => a.x * b.y - a.y * b.x;

double _segments(Vector2 a, Vector2 b, Vector2 c, Vector2 d) {
  final ab = b - a, cd = d - c;
  final determinant = _cross(ab, cd);
  if (determinant.abs() > 1e-12) {
    final t = _cross(c - a, cd) / determinant;
    final u = _cross(c - a, ab) / determinant;
    if (t >= 0 && t <= 1 && u >= 0 && u <= 1) return 0;
  }
  return math.min(
    math.min(_pointSegment(a, c, d), _pointSegment(b, c, d)),
    math.min(_pointSegment(c, a, b), _pointSegment(d, a, b)),
  );
}

bool pointInsideOutline(Vector2 point, List<Vector2> vertices) {
  var inside = false;
  for (var i = 0, j = vertices.length - 1; i < vertices.length; j = i++) {
    final a = vertices[i], b = vertices[j];
    if ((a.y > point.y) != (b.y > point.y) &&
        point.x < (b.x - a.x) * (point.y - a.y) / (b.y - a.y) + a.x) {
      inside = !inside;
    }
  }
  return inside;
}
