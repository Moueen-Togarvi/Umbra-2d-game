import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';
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
class Ground extends BodyComponent {
  Ground({
    required Vector2 center,
    required Vector2 size,
    this.style = GroundStyle.earth,
    this.wind,
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
  }) {
    return Ground(
      center: Vector2((left + right) / 2, top + thickness / 2),
      size: Vector2(right - left, thickness),
      style: style,
      wind: wind,
    );
  }

  final Vector2 _size;
  final GroundStyle style;

  /// When set, an earth slab grows grass along its top in this wind.
  final GrassWind? wind;

  /// The silhouette, built once. Body-local metres, origin at the centre.
  late final Path _outline = _buildOutline();

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

  /// A trunk lying on its side. The bark along the top follows the
  /// collision top within a centimetre; the underside bulges and the ends
  /// are broken off, with a few snapped branches sticking up and out.
  Path _log(double hw, double hh, math.Random random) {
    final Path path = Path();
    final double r = hh;
    // Top edge: bark ridges.
    path.moveTo(-hw + r * 0.6, -hh);
    final int steps = math.max(6, (_size.x / 0.05).round());
    for (var i = 1; i <= steps; i++) {
      final double x = -hw + r * 0.6 + i / steps * (_size.x - r * 1.2);
      path.lineTo(x, -hh + 0.004 + random.nextDouble() * 0.008);
    }
    // Right end: a snapped stump with splinters.
    path
      ..lineTo(hw - r * 0.15, -hh * 0.75)
      ..lineTo(hw + 0.03, -hh * 0.55)
      ..lineTo(hw - 0.02, -hh * 0.2)
      ..lineTo(hw + 0.05, hh * 0.05)
      ..lineTo(hw - 0.01, hh * 0.4)
      ..quadraticBezierTo(hw - r * 0.1, hh * 1.02, hw - r * 0.7, hh);
    // Underside: slightly bellied.
    path.quadraticBezierTo(0, hh * 1.12, -hw + r * 0.7, hh);
    // Left end: a rounder sawn face.
    path.quadraticBezierTo(-hw - r * 0.08, hh * 0.6, -hw, 0);
    path.quadraticBezierTo(-hw - r * 0.02, -hh * 0.75, -hw + r * 0.6, -hh);
    path.close();

    // Broken branches: a snapped limb rising out and away near each end,
    // where it cannot stand in the middle of the walking surface, and stubs
    // hanging from the underside.
    for (final end in const [-1.0, 1.0]) {
      if (random.nextDouble() < 0.25) continue;
      final double x = end * (hw - r * (1.2 + random.nextDouble()));
      final double angle = end * (0.55 + random.nextDouble() * 0.35);
      final double length = 0.12 + random.nextDouble() * 0.16;
      final double width = 0.025 + random.nextDouble() * 0.015;
      final double tipX = x + math.sin(angle) * length;
      final double tipY = -hh * 0.5 - math.cos(angle) * length;
      path
        ..moveTo(x - width, -hh * 0.3)
        ..lineTo(tipX - width * 0.2, tipY)
        ..lineTo(tipX + width * 0.2, tipY + 0.02)
        ..lineTo(x + width, -hh * 0.3)
        ..close();
    }
    final int stubs = math.max(1, (_size.x / 0.9).round());
    for (var i = 0; i < stubs; i++) {
      final double x =
          -hw + (i + 0.3 + random.nextDouble() * 0.4) / stubs * _size.x;
      final double length = 0.08 + random.nextDouble() * 0.16;
      final double lean = (random.nextDouble() - 0.5) * 0.6;
      final double width = 0.025 + random.nextDouble() * 0.02;
      path
        ..moveTo(x - width, hh * 0.5)
        ..lineTo(x + lean * length - width * 0.2, hh + length)
        ..lineTo(x + lean * length + width * 0.2, hh + length)
        ..lineTo(x + width, hh * 0.5)
        ..close();
    }
    return path;
  }

  /// The earth top edge's offset below the collision top at body-local x.
  static double _crumbs(double x) =>
      0.006 + 0.006 * math.sin(x * 11.3) + 0.004 * math.sin(x * 29.1 + 1.3);

  @override
  void render(Canvas canvas) {
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
