import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/palette.dart';

/// How a piece of ground is drawn. The physics is the same box either way.
enum GroundStyle {
  /// A mass of earth: solid black with a rough, grassy top edge.
  earth,

  /// A fallen log or branch: a rounded, slightly tapered bar with a few tufts.
  log,

  /// A wall at the edge of the level. Drawn plain; it is off screen anyway.
  wall,
}

/// A solid, immovable slab: floors, walls and ledges.
///
/// This is a **static** body. Static bodies have infinite mass, are never moved
/// by the solver, and do not collide with each other — which makes them
/// essentially free to simulate. Level geometry should almost always be static.
///
/// The collision box is a perfect rectangle. The *drawing* is not: the top
/// edge wanders up and down by a few centimetres and carries a strip of grass,
/// which is what stops a floor from reading as a black bar. The wander is
/// small enough that the feet never visibly float or sink.
class Ground extends BodyComponent {
  Ground({
    required Vector2 center,
    required Vector2 size,
    this.style = GroundStyle.earth,
    this.groundBelow,
  }) : _size = size.clone(),
       super(
         paint: Paint()..color = Palette.silhouette,
         renderBody: false,
         bodyDef: BodyDef(type: BodyType.static, position: center.clone()),
         shapeSpecs: [
           ShapeSpec(
             // Half-extents, as always in Box2D.
             Polygon.box(size.x / 2, size.y / 2),
             ShapeDef(
               // The player's foot sensor can only detect shapes that have
               // opted in to sensor events. Leaving this out is the single
               // most common reason a ground check "just doesn't work".
               enableSensorEvents: true,
             ),
           ),
         ],
       ) {
    // `this` is not available in an initialiser list, so the userData is
    // attached here, before the body is ever created. The foot sensor
    // identifies what it has landed on by looking at userData, and a slab
    // with none is invisible to it.
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
    double? groundBelow,
  }) {
    return Ground(
      center: Vector2((left + right) / 2, top + thickness / 2),
      size: Vector2(right - left, thickness),
      style: style,
      groundBelow: groundBelow,
    );
  }

  final Vector2 _size;
  final GroundStyle style;

  /// World y of the ground surface underneath a [GroundStyle.log], so the
  /// log can be drawn resting on a mound of earth rather than floating. Purely
  /// visual: the physics body is still just the log.
  final double? groundBelow;

  /// The silhouette, built once. Body-local metres, origin at the centre.
  late final Path _outline = _buildOutline();
  Image? _grass;
  final Paint _grassPaint = Paint()..filterQuality = FilterQuality.low;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (style == GroundStyle.earth &&
        Flame.images.containsKey('props/grass_fine.png')) {
      _grass = Flame.images.fromCache('props/grass_fine.png');
    }
  }

  Path _buildOutline() {
    final double hw = _size.x / 2;
    final double hh = _size.y / 2;
    switch (style) {
      case GroundStyle.wall:
        return Path()..addRect(Rect.fromLTRB(-hw, -hh, hw, hh));

      case GroundStyle.log:
        // A bar with rounded ends, fatter at one end, with a couple of stubs
        // of broken branch so it is not just a pill.
        final Path log = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTRB(-hw, -hh, hw, hh),
              Radius.circular(hh),
            ),
          )
          ..addOval(
            Rect.fromCircle(center: Offset(-hw + hh, 0), radius: hh * 1.25),
          )
          ..addOval(
            Rect.fromCenter(
              center: Offset(hw * 0.3, -hh * 0.9),
              width: hh * 1.6,
              height: hh * 1.2,
            ),
          )
          ..addOval(
            Rect.fromCenter(
              center: Offset(-hw * 0.45, -hh * 1.1),
              width: hh * 1.1,
              height: hh * 1.6,
            ),
          );
        return log;

      case GroundStyle.earth:
        // Walk along the top edge with a couple of sine waves, seeded from the
        // slab's width so neighbouring slabs do not repeat the same bumps.
        final Path earth = Path()..moveTo(-hw, hh);
        earth.lineTo(-hw, -hh);
        final double seed = _size.x * 3.7 + _size.y;
        final int steps = math.max(8, (_size.x * 4).round());
        for (var i = 0; i <= steps; i++) {
          final double t = i / steps;
          final double x = -hw + t * _size.x;
          // Long, low swells: a hillside, not a rock face.
          final double wobble =
              math.sin(x * 0.9 + seed) * 0.10 +
              math.sin(x * 2.3 + seed * 0.7) * 0.04 +
              math.sin(x * 7.0 + seed * 1.3) * 0.008;
          // Pinch the ends down a little so pit edges look worn.
          final double edge = math.min(1.0, math.min(t, 1 - t) * 8);
          earth.lineTo(x, -hh - wobble * edge + 0.02 * (1 - edge));
        }
        earth.lineTo(hw, hh);
        earth.close();
        return earth;
    }
  }

  /// Height of the top edge at body-local [x]: the same wobble the outline
  /// is built from. Only meaningful for [GroundStyle.earth].
  double _surfaceAt(double x) {
    final double hw = _size.x / 2;
    final double hh = _size.y / 2;
    final double seed = _size.x * 3.7 + _size.y;
    final double t = ((x + hw) / _size.x).clamp(0.0, 1.0);
    final double wobble =
        math.sin(x * 0.9 + seed) * 0.10 +
        math.sin(x * 2.3 + seed * 0.7) * 0.04 +
        math.sin(x * 7.0 + seed * 1.3) * 0.008;
    final double edge = math.min(1.0, math.min(t, 1 - t) * 8);
    return -hh - wobble * edge + 0.02 * (1 - edge);
  }

  @override
  void render(Canvas canvas) {
    // A log lies on a heap of earth that reaches down to the ground, so it
    // reads as part of the terrain rather than as a bar hanging in the fog.
    // The heap is drawn narrower than the log and never wider, so the player
    // meets the log's physics edge before ever overlapping the drawing.
    final double? ground = groundBelow;
    if (style == GroundStyle.log && ground != null) {
      final double hw = _size.x / 2;
      final double bottom = ground - body.position.y + 0.3;
      final Path mound = Path()
        ..moveTo(-hw * 0.85, 0)
        ..lineTo(hw * 0.85, 0)
        ..lineTo(hw * 0.7, bottom)
        ..lineTo(-hw * 0.7, bottom)
        ..close();
      canvas.drawPath(mound, paint);
    }

    canvas.drawPath(_outline, paint);

    final Image? grass = _grass;
    if (grass == null) {
      return;
    }
    // A low fuzz of grass along the top edge, its roots buried in the slab.
    // Short: at this scale the reference ground is a soft dark line with a
    // fine fringe, not a hedge. Clipped to the slab's width, slightly
    // overhanging so a pit's lip has a few blades leaning out over the drop.
    const double grassHeight = 0.22;
    const double overhang = 0.06;
    final double hw = _size.x / 2;
    final double top = -_size.y / 2;
    final double scale = grassHeight / grass.height;
    final double tileW = grass.width * scale;
    final Rect src = Rect.fromLTWH(
      0,
      0,
      grass.width.toDouble(),
      grass.height.toDouble(),
    );
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        -hw - overhang,
        top - grassHeight - 0.15,
        hw + overhang,
        top + 1,
      ),
    );
    // Offset the tiling by the slab's world position so two slabs never show
    // the same blade at the same screen x.
    double x = -hw - (body.position.x * 0.37) % tileW;
    while (x < hw + overhang) {
      // Follow the hill: sample the outline's height at the tile's centre so
      // the fringe rides the swells instead of cutting straight across them.
      final double y = _surfaceAt(x + tileW / 2);
      canvas.drawImageRect(
        grass,
        src,
        Rect.fromLTWH(x, y - grassHeight + 0.06, tileW, grassHeight),
        _grassPaint,
      );
      x += tileW;
    }
    canvas.restore();
  }
}
