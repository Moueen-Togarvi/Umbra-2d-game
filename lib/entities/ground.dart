import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart' show FlameGame;
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
  }) {
    return Ground(
      center: Vector2((left + right) / 2, top + thickness / 2),
      size: Vector2(right - left, thickness),
      style: style,
    );
  }

  final Vector2 _size;
  final GroundStyle style;

  /// The silhouette, built once. Body-local metres, origin at the centre.
  late final Path _outline = _buildOutline();

  /// Seconds elapsed, for the wind in the grass. A static body never moves,
  /// so this is the only reason it has an update at all.
  double _time = 0;

  /// The camera, for culling grass that is off screen. Every slab draws its
  /// grass in dozens of slices; without this a 64 m level issues a few
  /// hundred draw calls a frame for grass nobody can see.
  CameraComponent? _camera;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  Image? _grass;
  final Paint _grassPaint = Paint()..filterQuality = FilterQuality.low;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    if (style == GroundStyle.earth &&
        Flame.images.containsKey('props/grass_tall.png')) {
      _grass = Flame.images.fromCache('props/grass_tall.png');
    }
    final game = findGame();
    if (game is FlameGame) {
      _camera = game.camera;
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
    canvas.drawPath(_outline, paint);

    final Image? grass = _grass;
    if (grass == null) {
      return;
    }
    // Wild grass along the top edge, its roots buried in the slab. Clipped
    // to the slab's width, slightly overhanging so a pit's lip has a few
    // blades leaning out over the drop.
    const double grassHeight = 0.62;
    const double overhang = 0.08;
    final double hw = _size.x / 2;
    final double top = -_size.y / 2;
    final double scale = grassHeight / grass.height;
    final double tileW = grass.width * scale;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        -hw - overhang,
        top - grassHeight - 0.3,
        hw + overhang,
        top + 1,
      ),
    );

    // The grass is drawn in narrow vertical slices, each sheared from its
    // root by its own amount, so a gust can travel along the field: the
    // shear is a couple of slow waves in world x and time. Shearing about
    // the root keeps the roots planted and moves only the tips, which is
    // what wind does to grass.
    const double sliceW = 0.45;
    final int slicesPerTile = (tileW / sliceW).ceil();
    final double srcSliceW = grass.width / slicesPerTile;
    final double drawSliceW = tileW / slicesPerTile;
    final double worldLeft = body.position.x - hw;

    // Only the slices the camera can see, in body-local x.
    final Rect? visible = _camera?.visibleWorldRect;
    final double visLeft = visible == null
        ? -hw - overhang
        : visible.left - body.position.x - sliceW;
    final double visRight = visible == null
        ? hw + overhang
        : visible.right - body.position.x + sliceW;

    // Offset the tiling by the slab's world position so two slabs never show
    // the same blade at the same screen x.
    double x = -hw - (body.position.x * 0.37) % tileW;
    while (x < hw + overhang) {
      for (var i = 0; i < slicesPerTile; i++) {
        final double sx = x + i * drawSliceW;
        if (sx + drawSliceW < -hw - overhang || sx > hw + overhang) continue;
        if (sx + drawSliceW < visLeft || sx > visRight) continue;
        // Each slice is rooted on its own bit of hill, buried a little, so
        // no fog can show between the roots and a dip in the outline.
        final double root = _surfaceAt(sx + drawSliceW / 2) + 0.12;
        final double wx = worldLeft + hw + sx; // world x of this slice
        final double gust =
            math.sin(_time * 1.1 - wx * 0.45) * 0.10 +
            math.sin(_time * 2.3 - wx * 1.7 + 1.0) * 0.045 +
            math.sin(_time * 0.37 + wx * 0.2) * 0.05;
        final double lean = 0.10 + gust; // a prevailing breeze, plus gusts
        canvas.save();
        canvas.translate(sx, root);
        canvas.skew(-lean, 0);
        canvas.drawImageRect(
          grass,
          Rect.fromLTWH(i * srcSliceW, 0, srcSliceW, grass.height.toDouble()),
          Rect.fromLTWH(0, -grassHeight, drawSliceW + 0.004, grassHeight),
          _grassPaint,
        );
        canvas.restore();
      }
      x += tileW;
    }
    canvas.restore();
  }
}
