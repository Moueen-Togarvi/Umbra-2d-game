import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../physics/collision_layers.dart';
import '../render/culling.dart';
import 'player.dart';

/// A pit of sharpened stakes. Touching the stakes kills the boy: the body
/// goes limp and falls onto them, and the death sequence takes it from there.
///
/// The stakes are a **sensor**: a shape that takes part in collision
/// *detection* but not in collision *response*, so the engine reports the
/// touch without the stakes holding him up. Below their points a solid
/// floor catches the limp body, so it comes to rest among the stakes rather
/// than falling out of the world.
class Hazard extends BodyComponent with ContactCallbacks, OffScreenCulling {
  Hazard({required Vector2 center, required Vector2 size, this.stakes = true})
    : _size = size.clone(),
      super(
        paint: Paint()..color = Palette.silhouette,
        renderBody: false,
        bodyDef: BodyDef(type: BodyType.static, position: center.clone()),
        shapeSpecs: [
          if (!stakes)
            ShapeSpec(
              Polygon.box(size.x / 2, size.y / 2),
              ShapeDef(
                isSensor: true,
                filter: Filter(
                  categoryBits: CollisionLayers.sensor,
                  maskBits: CollisionLayers.player | CollisionLayers.ragdoll,
                ),
              ),
            ),
          // The floor the stakes stand in, a little below their points.
          ShapeSpec(
            Polygon.offsetBox(
              size.x / 2,
              size.y / 2 - stakeHeight / 2,
              center: Vector2(0, stakeHeight / 2),
            ),
            ShapeDef(
              filter: Filter(categoryBits: CollisionLayers.terrain),
              material: SurfaceMaterial(friction: 0.9),
            ),
          ),
        ],
      ) {
    // Because this userData is a ContactCallbacks, BodyComponent automatically
    // switches on the contact and sensor event flags for the shapes above —
    // that convenience only applies when the callbacks are attached before the
    // body is built, which is why this happens here.
    bodyDef!.userData = this;
  }

  /// How far the stakes stand above the pit floor.
  static const double stakeHeight = 0.55;

  /// Hunters' stakes in the floor; without, a plain drop onto rock that
  /// kills by its depth alone.
  final bool stakes;

  final Vector2 _size;

  /// The stakes and the floor, built once in body-local metres.
  late final Path _stakes;
  final List<List<Vector2>> _stakeHulls = [];
  final Path _glints = Path();

  @override
  Body createBody() {
    final result = super.createBody();
    _stakes = _buildStakes();
    if (stakes) {
      for (final hull in _stakeHulls) {
        result.createShape(
          Polygon(hull),
          ShapeDef(
            isSensor: true,
            enableSensorEvents: true,
            filter: Filter(
              categoryBits: CollisionLayers.sensor,
              maskBits: CollisionLayers.player | CollisionLayers.ragdoll,
            ),
          ),
        );
      }
    }
    return result;
  }

  late final Path _floor = _buildFloor();

  double get _hw => _size.x / 2;
  double get _hh => _size.y / 2;

  /// The top of the floor the stakes stand in.
  double get _base => -_hh + stakeHeight;

  /// The level of the pit's lips, body-local.
  double get _lip => -_hh - GameConfig.pitDepth;

  /// Sharpened poles driven into the floor by hand: thick, uneven, leaning
  /// every way, a few snapped short, two crossed.
  Path _buildStakes() {
    final path = Path();
    final random = math.Random((_size.x * 1000).round());
    final xs = <double>[];
    for (
      double x = -_hw + 0.07 + random.nextDouble() * 0.05;
      x < _hw - 0.05;
      x += 0.13 + random.nextDouble() * 0.09
    ) {
      xs.add(x);
    }
    // Two neighbours lean into each other and cross.
    final int crossed = xs.length > 3 ? 1 + random.nextInt(xs.length - 2) : -1;
    for (var i = 0; i < xs.length; i++) {
      final double x = xs[i];
      final bool broken = random.nextDouble() < 0.22;
      final double height = broken
          ? 0.18 + random.nextDouble() * 0.2
          : 0.38 + random.nextDouble() * 0.42;
      double lean = (random.nextDouble() - 0.5) * 0.4;
      if (i == crossed) lean = 0.42;
      if (i == crossed + 1) lean = -0.42;
      final double width = 0.06 + random.nextDouble() * 0.03;
      _stake(path, x, height, lean, width, broken, random);
    }
    return path;
  }

  void _stake(
    Path path,
    double x,
    double height,
    double lean,
    double width,
    bool broken,
    math.Random random,
  ) {
    // Built upright, then leaned about its foot.
    final double c = math.cos(lean), s = math.sin(lean);
    Offset at(double across, double up) =>
        Offset(x + across * c + up * s, _base + 0.04 - (up * c - across * s));
    final double w = width / 2;
    final tip = broken ? height : height + 0.05;
    final points = <Offset>[
      at(-w, -0.04),
      at(-w, height * 0.62),
      at(-w * 0.55, height * 0.86),
      at(broken ? w * 0.7 : 0, tip),
      at(w, height * (broken ? 0.90 : 0.62)),
      at(w, -0.04),
    ];
    _stakeHulls.add([for (final point in points) Vector2(point.dx, point.dy)]);
    path.addPolygon(points, true);
    // One worn face catches the fog light; the pole stays a solid silhouette.
    final a = at(-w * 0.55, height * 0.60);
    final b = at(-w * 0.3, height * 0.88);
    _glints
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy);
  }

  /// The floor: trodden mud with lumps, stones half sunk in it and a few
  /// broken sticks lying across it. It reaches under the banks either side.
  Path _buildFloor() {
    final random = math.Random((_size.x * 311).round());
    final double left = -_hw - 0.25, right = _hw + 0.25;
    final path = Path()..moveTo(left, _hh);
    for (double x = left; x <= right; x += 0.05) {
      final double lump =
          0.025 * math.sin(x * 9.1 + 1.3) + (random.nextDouble() - 0.5) * 0.02;
      path.lineTo(x, _base + 0.02 + lump);
    }
    path
      ..lineTo(right, _hh)
      ..close();
    for (var i = 0; i < 4; i++) {
      final double r = 0.025 + random.nextDouble() * 0.035;
      path.addOval(
        Rect.fromCircle(
          center: Offset(
            left + 0.1 + random.nextDouble() * (right - left - 0.2),
            _base + 0.03,
          ),
          radius: r,
        ),
      );
    }
    for (var i = 0; i < 2; i++) {
      final double length = 0.3 + random.nextDouble() * 0.3;
      final double angle = (random.nextDouble() - 0.5) * 0.5;
      final double cx = left + 0.2 + random.nextDouble() * (right - left - 0.4);
      final double dx = math.cos(angle) * length / 2;
      final double dy = math.sin(angle) * length / 2;
      const double t = 0.014;
      path
        ..moveTo(cx - dx - t * math.sin(angle), _base + 0.01 - dy + t)
        ..lineTo(cx + dx - t * math.sin(angle), _base + 0.01 + dy + t)
        ..lineTo(cx + dx, _base - 0.015 + dy)
        ..lineTo(cx - dx, _base - 0.015 - dy)
        ..close();
    }
    return path;
  }

  final Paint _shadowPaint = Paint();
  final Paint _edgePaint = Paint()
    ..color = const Color(0x505D6263)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.014;

  @override
  void render(Canvas canvas) {
    final centre = body.position;
    if (!isOnScreen(
      Rect.fromLTRB(
        centre.x - _hw - 0.3,
        centre.y + _lip,
        centre.x + _hw + 0.3,
        centre.y + _hh,
      ),
    )) {
      return;
    }
    // The drop: fog at the lip, darkening with depth into the pit, but
    // never so dark that the broken walls, the roots or the black stakes
    // stop standing out against it. It reaches under the undercut banks.
    final double wide = _hw + 0.2;
    _shadowPaint.shader = Gradient.linear(
      Offset(0, _lip),
      Offset(0, _base),
      const [
        Color(0x00000000),
        Color(0x2A000000),
        Color(0x5E000000),
        Color(0x80000000),
      ],
      const [0.0, 0.4, 0.8, 1.0],
    );
    canvas.drawRect(
      Rect.fromLTRB(-wide, _lip, wide, _base + 0.05),
      _shadowPaint,
    );
    if (stakes) {
      canvas.drawPath(_stakes, paint);
      canvas.drawPath(_glints, _edgePaint);
    }
    canvas.drawPath(_floor, paint);
  }

  /// Builds a hazard from its edges, matching the way ground slabs are
  /// described in the level.
  factory Hazard.zone({
    required double left,
    required double right,
    required double top,
    required double bottom,
    bool stakes = true,
  }) {
    return Hazard(
      center: Vector2((left + right) / 2, (top + bottom) / 2),
      size: Vector2(right - left, bottom - top),
      stakes: stakes,
    );
  }

  @override
  void beginContact(Object other, Contact contact) {
    // `other` is the userData of whatever touched us: the capsule, or a
    // limb of the ragdoll, both of which carry the Player.
    if (other is Player) {
      other.die(cause: stakes ? DeathCause.spikes : DeathCause.fall);
    }
  }
}
