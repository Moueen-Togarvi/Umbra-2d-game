import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../physics/collision_layers.dart';
import '../render/culling.dart';
import '../render/grass.dart';

/// How a piece of ground is drawn. The physics is the same box either way.
enum GroundStyle {
  /// A mass of earth: solid black with a slightly uneven top edge.
  earth,

  /// A fallen log: a rounded trunk with bark, broken branch stubs and a
  /// sawn or snapped end.
  log,

  /// A wall at the edge of the level. Drawn plain; it is off screen anyway.
  wall,
}

/// A solid, immovable slab: floors, walls, ledges and fallen logs.
///
/// This is a **static** body. Static bodies have infinite mass, are never moved
/// by the solver, and do not collide with each other — which makes them
/// essentially free to simulate. Level geometry should almost always be static.
///
/// The collision box is a perfect rectangle, so the walking surface is flat
/// and steady. The *drawing* is not: a log is a rounded trunk whose top runs
/// along the box's top, so feet land exactly on the bark.
class Ground extends BodyComponent with OffScreenCulling {
  Ground({
    required Vector2 center,
    required Vector2 size,
    this.style = GroundStyle.earth,
    this.wind,
    this.logDiameter,
    this.groundBelow,
  }) : _size = size.clone(),
       super(
         paint: Paint()..color = const Color(0xFF070707),
         renderBody: false,
         bodyDef: BodyDef(type: BodyType.static, position: center.clone()),
         shapeSpecs: [
           ShapeSpec(
             // Half-extents, as always in Box2D.
             Polygon.box(size.x / 2, size.y / 2),
             ShapeDef(
               filter: Filter(categoryBits: CollisionLayers.terrain),
               material: SurfaceMaterial(friction: 0.7),
               // The player's foot sensor can only detect shapes that have
               // opted in to sensor events.
               enableSensorEvents: true,
             ),
           ),
         ],
       ) {
    // `this` is not available in an initialiser list, so the userData is
    // attached here, before the body is ever created.
    bodyDef!.userData = this;
  }

  /// Builds a slab from its edges rather than its centre, which is how level
  /// geometry is naturally described: "floor from x=0 to x=5, top at y=6".
  factory Ground.slab({
    required double left,
    required double right,
    required double top,
    required double thickness,
    GroundStyle style = GroundStyle.earth,
    GrassWind? wind,
    double? logDiameter,
    double Function(double x)? groundBelow,
  }) {
    return Ground(
      center: Vector2((left + right) / 2, top + thickness / 2),
      size: Vector2(right - left, thickness),
      style: style,
      wind: wind,
      logDiameter: logDiameter,
      groundBelow: groundBelow,
    );
  }

  /// A log lying on sloping ground, resting on its highest point: its
  /// [logDiameter] (the trunk as drawn) and the drawn ground under it,
  /// world y at world x. The collision box reaches down into that ground,
  /// so nothing can get under the log, and a mound of soil is drawn into
  /// the space between the trunk and the ground, so no light shows there.
  factory Ground.restingLog({
    required double left,
    required double right,
    required double diameter,
    required double Function(double x) groundBelow,
  }) {
    var highest = double.infinity, lowest = double.negativeInfinity;
    for (double x = left; x <= right + 1e-9; x += 0.05) {
      final double y = groundBelow(x);
      highest = math.min(highest, y);
      lowest = math.max(lowest, y);
    }
    // Settled a few centimetres into the soil where it touches.
    final double top = highest + 0.03 - diameter;
    return Ground.slab(
      left: left,
      right: right,
      top: top,
      thickness: lowest + 0.05 - top,
      style: GroundStyle.log,
      logDiameter: diameter,
      groundBelow: groundBelow,
    );
  }

  final Vector2 _size;
  final GroundStyle style;

  /// The collision box's size, metres.
  Vector2 get size => _size;

  /// The trunk's thickness as drawn, if a log; the collision box may reach
  /// further down, into the ground under it.
  final double? logDiameter;

  /// The drawn ground under a log, world y at world x.
  final double Function(double x)? groundBelow;

  /// When set, an earth slab grows grass along its top in this wind.
  final GrassWind? wind;

  /// The silhouette, built once. Body-local metres, origin at the centre.
  late final Path _outline = _buildOutline();

  /// The silhouette as drawn, body-local, for tests.
  @visibleForTesting
  Path get outline => _outline;

  Path _buildOutline() {
    final double hw = _size.x / 2;
    final double hh = _size.y / 2;
    final random = math.Random((_size.x * 731 + _size.y * 53).round());
    switch (style) {
      case GroundStyle.wall:
        return Path()..addRect(Rect.fromLTRB(-hw, -hh, hw, hh));

      case GroundStyle.earth:
        // A bank of packed earth: crumbly top edge, and sides that bulge
        // and crumble rather than standing as clean walls.
        final Path earth = Path()..moveTo(-hw + 0.06, hh);
        for (var i = 0; i <= 12; i++) {
          final double t = i / 12;
          final double y = hh - t * _size.y;
          final double bulge =
              math.sin(t * math.pi) * 0.05 + (random.nextDouble() - 0.5) * 0.03;
          earth.lineTo(-hw - bulge + (1 - t) * 0.06, y);
        }
        final int steps = math.max(8, (_size.x / 0.04).round());
        for (var i = 0; i <= steps; i++) {
          final double x = -hw + i / steps * _size.x;
          earth.lineTo(x, -hh + _crumbs(x));
        }
        for (var i = 0; i <= 12; i++) {
          final double t = i / 12;
          final double y = -hh + t * _size.y;
          final double bulge =
              math.sin(t * math.pi) * 0.05 + (random.nextDouble() - 0.5) * 0.03;
          earth.lineTo(hw + bulge - t * 0.06, y);
        }
        return earth..close();

      case GroundStyle.log:
        return _log(hw, hh, random);
    }
  }

  /// A trunk lying on its side, resting in the soil. The bark along the top
  /// follows the collision top within a centimetre, so feet land on it. It
  /// tapers from a thick end, flared where the roots tore out of the ground,
  /// to a thin end snapped off in splinters; a couple of broken branches
  /// stick up and out near the ends. Under it, a mound of soil fills down
  /// to the ground.
  Path _log(double hw, double hh, math.Random random) {
    final Path path = Path();
    // Branches, roots, tufts and soil: each its own shape, merged with the
    // trunk at the end, so where they overlap it they add to it instead of
    // cutting holes in it.
    final extras = <Path>[];
    final double diameter = logDiameter ?? _size.y;
    final double top = -hh;
    // Which end is the thick, rooted one.
    final double rootEnd = random.nextBool() ? 1 : -1;
    double radius(double x) {
      final double t = (x * rootEnd / hw + 1) / 2; // 0 thin end, 1 root end
      return diameter / 2 * (0.82 + 0.18 * t);
    }

    double bottomAt(double x) =>
        top +
        2 * radius(x) +
        0.012 * math.sin(x * 11.7 + 2.1) +
        0.008 * math.sin(x * 29.3);

    // The top of the trunk, left to right, rounding down a little at each
    // end the way a log's top does.
    final double r0 = radius(-hw), r1 = radius(hw);
    final double from = -hw + r0 * 0.55, to = hw - r1 * 0.55;
    path.moveTo(from, top + 0.03);
    final int steps = math.max(8, (_size.x / 0.05).round());
    for (var i = 1; i <= steps; i++) {
      final double x = from + i / steps * (to - from);
      final double end = math.min(x - from, to - x);
      final double round = end < 0.12 ? 0.03 * math.pow(1 - end / 0.12, 2) : 0;
      path.lineTo(x, top + 0.003 + random.nextDouble() * 0.007 + round);
    }
    // The right end.
    _logEnd(
      path,
      extras,
      hw,
      top,
      bottomAt(hw),
      r1,
      rootEnd > 0 ? 1 : -1,
      1,
      random,
    );
    // The underside, right to left, bumpy.
    for (var i = steps; i >= 0; i--) {
      final double x = -hw + r0 * 0.6 + i / steps * (_size.x - (r0 + r1) * 0.6);
      path.lineTo(x, bottomAt(x));
    }
    // The left end.
    _logEnd(
      path,
      extras,
      -hw,
      top,
      bottomAt(-hw),
      r0,
      rootEnd < 0 ? 1 : -1,
      -1,
      random,
    );
    path.close();

    // Tufts of grass and moss grown on the bark.
    for (var i = 0; i < 2 + random.nextInt(3); i++) {
      final double x = from + 0.1 + random.nextDouble() * (to - from - 0.2);
      for (var b = 0; b < 4; b++) {
        final double bx = x + (b - 1.5) * 0.012;
        final double h = 0.025 + random.nextDouble() * 0.045;
        final double lean = (random.nextDouble() - 0.5) * 0.04;
        extras.add(
          Path()
            ..moveTo(bx - 0.005, top + 0.008)
            ..lineTo(bx + lean, top - h)
            ..lineTo(bx + 0.005, top + 0.008)
            ..close(),
        );
      }
    }

    // Broken branches rising out and away near the ends, clear of the
    // middle where he walks.
    for (final end in const [-1.0, 1.0]) {
      if (random.nextDouble() < 0.3) continue;
      final double x =
          end * (hw - diameter * (0.8 + random.nextDouble() * 0.7));
      final double angle = end * (0.5 + random.nextDouble() * 0.4);
      final double length = 0.12 + random.nextDouble() * 0.14;
      final double width = 0.022 + random.nextDouble() * 0.014;
      final double baseY = top + diameter * 0.18;
      final double tipX = x + math.sin(angle) * length;
      final double tipY = baseY - math.cos(angle) * length;
      extras.add(
        Path()
          ..moveTo(x - width, baseY)
          ..lineTo(tipX - width * 0.25, tipY)
          ..lineTo(tipX + width * 0.3, tipY + 0.015)
          ..lineTo(x + width, baseY + 0.01)
          ..close(),
      );
    }

    // The soil it lies in: from just under the trunk down into the ground,
    // across its whole length, mounded a little past each end.
    final groundBelow = this.groundBelow;
    if (groundBelow != null) {
      final double cx = body.position.x, cy = body.position.y;
      final soil = Path();
      final double from = -hw - 0.08, to = hw + 0.08;
      soil.moveTo(from, groundBelow(cx + from) - cy + 0.03);
      for (double x = from; x <= to + 1e-9; x += 0.04) {
        final double inside = x.abs() <= hw - 0.05 ? 1 : 0;
        final double under = inside > 0
            ? bottomAt(x) - 0.03
            : groundBelow(cx + x) - cy - 0.025;
        soil.lineTo(x, under);
      }
      for (double x = to; x >= from - 1e-9; x -= 0.04) {
        soil.lineTo(x, groundBelow(cx + x) - cy + 0.05);
      }
      soil.close();
      extras.add(soil);
    }
    var log = path;
    for (final extra in extras) {
      log = Path.combine(PathOperation.union, log, extra);
    }
    return log;
  }

  /// One end of a log at [x] (local), from [top] to [bottom]: a root end
  /// ([rooted] 1) flares into torn roots reaching into the soil; a broken
  /// end is splintered. [side] is +1 for the right end, −1 for the left;
  /// the right end is drawn top to bottom, the left bottom to top.
  void _logEnd(
    Path path,
    List<Path> extras,
    double x,
    double top,
    double bottom,
    double radius,
    double rooted,
    double side,
    math.Random random,
  ) {
    final points = <Offset>[];
    if (rooted > 0) {
      // The root plate of a tree torn out of the ground: a ragged disc of
      // roots and earth standing a little above the trunk, wider than it.
      final double r = radius;
      points
        ..add(Offset(x - side * r * 0.5, top + 0.002))
        ..add(Offset(x - side * r * 0.2, top - r * 0.22))
        ..add(Offset(x - side * r * 0.05, top - r * 0.5))
        ..add(Offset(x + side * r * 0.12, top - r * 0.38))
        ..add(Offset(x + side * r * 0.18, top - r * 0.6))
        ..add(Offset(x + side * r * 0.3, top - r * 0.2))
        ..add(Offset(x + side * r * 0.42, top + r * 0.3))
        ..add(Offset(x + side * r * 0.38, top + r * 0.9))
        ..add(Offset(x + side * r * 0.46, top + r * 1.4))
        ..add(Offset(x + side * r * 0.3, bottom + 0.06))
        ..add(Offset(x + side * r * 0.05, bottom + 0.06));
    } else {
      // Snapped off: splinters sticking out of a jagged break.
      points
        ..add(Offset(x - side * radius * 0.4, top + 0.004))
        ..add(Offset(x + side * 0.05, top + radius * 0.25))
        ..add(Offset(x - side * 0.01, top + radius * 0.6))
        ..add(Offset(x + side * 0.07, top + radius * 0.95))
        ..add(Offset(x + side * 0.0, top + radius * 1.3))
        ..add(Offset(x + side * 0.04, top + radius * 1.65))
        ..add(Offset(x - side * radius * 0.3, bottom));
    }
    final ordered = side > 0 ? points : points.reversed.toList();
    for (final point in ordered) {
      path.lineTo(point.dx, point.dy);
    }
    if (rooted > 0) {
      // Torn roots, as their own shapes, sticking out of the root plate in
      // every direction but into the trunk.
      for (var i = 0; i < 6; i++) {
        final double y0 = top + radius * (-0.4 + i * 0.36);
        final double length = 0.08 + random.nextDouble() * 0.16;
        final double angle = 0.3 + random.nextDouble() * 2.2;
        final double w = 0.012 + random.nextDouble() * 0.012;
        final double x0 = x + side * radius * 0.1;
        extras.add(
          Path()
            ..moveTo(x0, y0 - w)
            ..lineTo(
              x0 + side * math.sin(angle) * length,
              y0 + math.cos(angle) * length * 0.6,
            )
            ..lineTo(x0, y0 + w)
            ..close(),
        );
      }
    }
  }

  /// The earth top edge's offset below the collision top at body-local x.
  static double _crumbs(double x) =>
      0.006 + 0.006 * math.sin(x * 11.3) + 0.004 * math.sin(x * 29.1 + 1.3);

  /// What the drawing covers, world metres.
  late final Rect _bounds = _outline.getBounds().shift(
    Offset(body.position.x, body.position.y),
  );

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(_bounds)) return;
    canvas.drawPath(_outline, paint);
    final GrassWind? wind = this.wind;
    if (wind == null || style != GroundStyle.earth) return;
    final double hw = _size.x / 2;
    final double cx = body.position.x;
    final double top = body.position.y - _size.y / 2;
    // Built fresh each frame: the web renderer records drawn paths by
    // reference, so a path must not be changed once it has been drawn.
    final grass = Path();
    GrassPainter.addBlades(
      grass,
      left: cx - hw + 0.02,
      right: cx + hw - 0.02,
      surface: (x) => top + _crumbs(x - cx),
      style: GrassStyle.back,
      wind: wind,
    );
    canvas.save();
    canvas.translate(-cx, -body.position.y);
    canvas.drawPath(grass, paint);
    canvas.restore();
  }
}
