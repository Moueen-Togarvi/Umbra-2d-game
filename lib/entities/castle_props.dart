import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../world/footprint.dart';
import '../config/game_config.dart';
import '../config/palette.dart';
import '../physics/collision_layers.dart';
import '../render/culling.dart';
import '../render/light.dart';
import '../world/stage.dart';
import 'home_props.dart';
import 'physics_props.dart';
import 'player.dart';

const Color _iron = Color(0xFF050505);
const Color _wood = Color(0xFF080706);
const Color _seam = Color(0x1CD8D0C0);

// ---------------------------------------------------------------------------
// Things on ropes over pulleys
// ---------------------------------------------------------------------------

/// Something hung on a rope that slides up and down a guide: a gate in
/// its slot, a weighing pan, a lift, a counterweight. A real dynamic body
/// held upright on a vertical prismatic joint between [rise] above and
/// [drop] below where it starts; what moves it is its weight, the rope
/// ([Pulley]) and whatever stands on it.
abstract class Hoisted extends BodyComponent with OffScreenCulling {
  Hoisted({
    required Vector2 position,
    required Vector2 size,
    required this.massKg,
    required this.rise,
    required this.drop,
    this.startLift = 0,
  }) : start = position.clone(),
       size = size.clone(),
       super(renderBody: false);

  /// Where its centre is at rest, and its outline.
  final Vector2 start, size;
  final double massKg;

  /// How far it can go up and down from [start].
  final double rise, drop;

  /// It begins this far above [start].
  final double startLift;

  late final Body _base;
  late PrismaticJoint guide;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;

  /// How far below its start it is now (above is negative).
  double get travel => isReady ? body.position.y - start.y : -startLift;

  /// The top of what can be stood on, relative to its centre.
  double get deck => -size.y / 2;

  /// Where its rope is tied on, world metres.
  Vector2 get ropeEnd => body.position + Vector2(0, -size.y / 2);

  /// Adds its collision shapes to [b].
  void shapes(Body b);

  /// It meets the stone round its slot as well as the boy and what he
  /// moves (and the boy's feet find it as ground), so it is laid out to
  /// run clear of the stone.
  ShapeDef shapeDef({double friction = 0.9, bool collides = true}) => ShapeDef(
    density: 10,
    filter: CollisionLayers.propFilter(collides: collides),
    material: SurfaceMaterial(friction: friction),
    enableSensorEvents: true,
    enableHitEvents: true,
  );

  @override
  Body createBody() {
    _base = world.createBody(BodyDef(position: start));
    final b = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: start - Vector2(0, startLift),
        fixedRotation: true,
        linearDamping: 0.05,
        userData: this,
        isBullet: true,
      ),
    );
    shapes(b);
    b.massData = MassData(
      mass: massKg,
      center: b.localCenterOfMass,
      rotationalInertia: 1,
    );
    guide = world.physicsWorld.createPrismaticJoint(
      PrismaticJointDef(
        bodyA: _base,
        bodyB: b,
        localAxisA: Vector2(0, 1),
        enableLimit: true,
        lowerTranslation: -rise,
        upperTranslation: drop,
      ),
    );
    _ready = true;
    return b;
  }

  /// Holds it where it is now: a latch, a pin.
  void hold() {
    if (!isReady) return;
    final double t = travel;
    guide.setLimits(lower: t, upper: t);
  }

  /// Lets it run on its rope again.
  void free() {
    if (!isReady) return;
    guide.setLimits(lower: -rise, upper: drop);
    // Held a long while it has gone to sleep, and a joint's new limits do
    // not wake it.
    body.isAwake = true;
  }

  /// Authored checkpoint pose, held so a restored mechanism cannot collapse.
  void restoreTravel(double offset) {
    if (!isReady) return;
    final t = offset.clamp(-rise, drop);
    body
      ..setTransform(start + Vector2(0, t), const Rot.identity())
      ..linearVelocity = Vector2.zero();
    guide.setLimits(lower: t, upper: t);
  }

  /// Back where it started, at rest.
  void resetToStart() {
    if (!isReady) return;
    body
      ..setTransform(start - Vector2(0, startLift), const Rot.identity())
      ..linearVelocity = Vector2.zero();
  }

  @override
  void onRemove() {
    if (_ready && _base.isValid) world.destroyBody(_base);
    super.onRemove();
  }
}

/// A rope from one [Hoisted] up over two wheels and down to another: as one
/// goes down the other comes up.
///
/// Box2D has no pulley, so the rope is applied after each step: if the
/// rope would stretch, an impulse along it takes the slack out of both
/// sides in proportion to their masses, exactly as a taut rope would (an
/// Atwood machine). Whatever stands on either side (the boy, a crate)
/// rides with it and counts in its mass; the rope only pulls, so a side
/// resting on its stop lets the rope go slack. A brake in the wheel
/// keeps it from running faster than [maxSpeed].
class Pulley extends Component with OffScreenCulling {
  Pulley({
    required this.a,
    required this.b,
    required this.wheelY,
    this.maxSpeed = 1.6,
    this.wheelRadius = 0.22,
  });

  final Hoisted a, b;
  final double wheelY, maxSpeed, wheelRadius;

  double? _length;

  /// How long more each side, having just struck the top of its travel
  /// on the way up, is kept from bouncing back off it; and how fast each
  /// was last sent.
  double _knockA = 0, _knockB = 0, _sentA = 0, _sentB = 0;

  /// The wheels' turn, radians.
  double turned = 0;

  /// Mass on each side last step, with what rides on it.
  double massA = 0, massB = 0;

  static final QueryFilter _riders = QueryFilter(
    categoryBits: CollisionLayers.all,
    maskBits: CollisionLayers.prop | CollisionLayers.player,
  );

  /// Bodies standing on [h], and their masses.
  List<Body> _ridersOf(Hoisted h) {
    final double top = h.body.position.y + h.deck;
    final double hw = h.size.x / 2;
    final double x = h.body.position.x;
    final shapes = h.body.world.overlapAabb(
      Aabb(Vector2(x - hw, top - 0.06), Vector2(x + hw, top + 0.06)),
      filter: _riders,
    );
    final found = <Body>{};
    for (final s in shapes) {
      if (!s.isValid || s.isSensor) continue;
      final Body r = s.body;
      if (r == h.body || r.type != BodyType.dynamic) continue;
      // Resting on it: its underside on the deck, moving as the deck does.
      // (Not one still falling onto it, leaving it, or standing beside it.)
      // Its middle over the deck: one tipping off the edge is not carried.
      if ((r.position.x - x).abs() > hw) continue;
      final double bottom = s.aabb.upperBound.y;
      // (Box2D's boxes carry a small margin.)
      if ((bottom - top).abs() > 0.15) continue;
      if ((r.linearVelocity.y - h.body.linearVelocity.y).abs() > 0.6) continue;
      found.add(r);
    }
    return found.toList();
  }

  void _lift(Hoisted h, List<Body> riders, double by) {
    if (by <= 0) return;
    for (final body in [h.body, ...riders]) {
      body.setTransform(
        body.position - Vector2(0, by),
        Rot.fromAngle(body.angle),
      );
    }
  }

  void _apply(Hoisted h, List<Body> riders, double v) {
    h.body.linearVelocity = Vector2(0, v);
    for (final r in riders) {
      final Vector2 rv = r.linearVelocity;
      r.linearVelocity = Vector2(rv.x, v);
    }
  }

  @override
  void update(double dt) {
    if (!a.isReady || !b.isReady || dt <= 0) return;
    final double ya = a.body.position.y, yb = b.body.position.y;
    // The rope as laid out, both sides where they were built: not as found
    // on the first step, by when the heavier side may already have fallen
    // a little while the bodies were still being made (a lift that then
    // stopped short of the floor it was built to reach).
    final double length = _length ??=
        a.start.y - a.startLift + b.start.y - b.startLift;
    final ra = _ridersOf(a), rb = _ridersOf(b);
    double ma = a.massKg, pa = a.massKg * a.body.linearVelocity.y;
    for (final r in ra) {
      ma += r.mass;
      pa += r.mass * r.linearVelocity.y;
    }
    double mb = b.massKg, pb = b.massKg * b.body.linearVelocity.y;
    for (final r in rb) {
      mb += r.mass;
      pb += r.mass * r.linearVelocity.y;
    }
    massA = ma;
    massB = mb;
    double va = pa / ma, vb = pb / mb;
    final bool aTop = a.travel <= -a.rise + 0.003;
    final bool bTop = b.travel <= -b.rise + 0.003;
    final bool taut = ya + yb >= length - 0.01;
    final double stretch = va + vb;
    if (taut && stretch > 0) {
      final double impulse = stretch / (1 / ma + 1 / mb);
      va -= impulse / ma;
      vb -= impulse / mb;
      // A side already at the top of its travel cannot be pulled higher:
      // its stop takes the pull, and with the rope taut both sides rest.
      if ((aTop && va < 0) || (bTop && vb < 0)) {
        va = 0;
        vb = 0;
      }
    }
    final double ia = aTop ? 0 : 1 / ma;
    final double ib = bTop ? 0 : 1 / mb;
    // A side that comes up into its stop at speed is not bounced back down
    // off it, and the whole rope with it: for a moment after the knock,
    // what would carry it away from the stop is taken by the stop, while
    // it is the lighter side (the heavier one goes down as it should).
    _knockA = aTop && _sentA < -0.3 ? 0.5 : math.max(0, _knockA - dt);
    _knockB = bTop && _sentB < -0.3 ? 0.5 : math.max(0, _knockB - dt);
    if (taut &&
        ((_knockA > 0 && va > 0 && ma < mb) ||
            (_knockB > 0 && vb > 0 && mb < ma))) {
      va = 0;
      vb = 0;
    }
    // The brake.
    final double fastest = math.max(va.abs(), vb.abs());
    if (fastest > maxSpeed) {
      va *= maxSpeed / fastest;
      vb *= maxSpeed / fastest;
    }
    if (taut || stretch > 0) {
      _apply(a, ra, va);
      _apply(b, rb, vb);
    }
    _sentA = va;
    _sentB = vb;
    // Anything the step let stretch is taken back the same way, and what
    // rides each side goes with it.
    final double over = ya + yb - length;
    if (over > 0.003 && ia + ib > 0) {
      _lift(a, ra, over * ia / (ia + ib));
      _lift(b, rb, over * ib / (ia + ib));
    }
    turned += va * dt / wheelRadius;
  }

  static final Paint _rope = Paint()
    ..color = const Color(0xFF141414)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.035
    ..strokeCap = StrokeCap.round;
  static final Paint _metal = Paint()..color = _iron;
  static final Paint _spoke = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.04;
  static final Paint _rim = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05;

  @override
  void render(Canvas canvas) {
    if (!a.isReady || !b.isReady) return;
    final Vector2 ea = a.ropeEnd, eb = b.ropeEnd;
    final double l = math.min(ea.x, eb.x) - 1, r = math.max(ea.x, eb.x) + 1;
    if (!isOnScreen(Rect.fromLTRB(l, wheelY - 1, r, math.max(ea.y, eb.y)))) {
      return;
    }
    final double side = (eb.x - ea.x).sign;
    final Offset wa = Offset(ea.x, wheelY), wb = Offset(eb.x, wheelY);
    // Down each side from the far edge of its wheel, and across the top.
    canvas.drawLine(Offset(ea.x, wheelY), Offset(ea.x, ea.y), _rope);
    canvas.drawLine(Offset(eb.x, wheelY), Offset(eb.x, eb.y), _rope);
    canvas.drawLine(
      wa + Offset(0, -wheelRadius),
      wb + Offset(0, -wheelRadius),
      _rope,
    );
    // The beam the wheels hang from, into the dark above.
    canvas.drawRect(
      Rect.fromLTRB(
        math.min(wa.dx, wb.dx) - 0.5,
        wheelY - wheelRadius - 0.42,
        math.max(wa.dx, wb.dx) + 0.5,
        wheelY - wheelRadius - 0.2,
      ),
      _metal,
    );
    for (final w in [wa, wb]) {
      canvas.drawLine(
        w,
        w + Offset(0, -wheelRadius - 0.25),
        _spoke..strokeWidth = 0.07,
      );
      _spoke.strokeWidth = 0.04;
      canvas.drawCircle(w, wheelRadius, _rim);
      for (var k = 0; k < 4; k++) {
        final double t = turned * side + k * math.pi / 4;
        canvas.drawLine(
          w - Offset(math.cos(t), math.sin(t)) * wheelRadius,
          w + Offset(math.cos(t), math.sin(t)) * wheelRadius,
          _spoke,
        );
      }
      canvas.drawCircle(w, 0.06, _metal);
    }
  }
}

/// An iron portcullis in its slot: heavy, barred, spiked at the foot.
///
/// On a [Pulley] it rises when the other side is heavier. On its own it
/// can be [hold]ed up by its latch and dropped with [release]; it falls
/// with its full weight and kills what is under it.
class Portcullis extends Hoisted {
  Portcullis({
    required super.position,
    required double height,
    super.massKg = 40,
    super.rise = 2.0,
    super.startLift = 0,
  }) : super(size: Vector2(0.28, height), drop: 0);

  bool _latched = false;

  @override
  void shapes(Body b) => b.createShape(
    Polygon.box(size.x / 2, size.y / 2),
    shapeDef(friction: 0.5),
  );

  @override
  Body createBody() {
    final Body b = super.createBody();
    if (startLift > 0) {
      _latched = true;
      guide.setLimits(lower: -startLift, upper: -startLift);
    }
    return b;
  }

  /// Whether it is down in its slot.
  bool get isShut => travel > -0.05;

  /// Lets a latched gate fall.
  void release() {
    if (!_latched) return;
    _latched = false;
    free();
  }

  /// Raised again on its latch (after a death undid the boy's work).
  void relatch() {
    if (!isReady) return;
    resetToStart();
    _latched = true;
    guide.setLimits(lower: -startLift, upper: -startLift);
  }

  Stage? _stage;
  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _stage = ancestors().whereType<Stage>().firstOrNull;
  }

  double _fall = 0;

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady) return;
    // Slammed home in its slot.
    final double v = body.linearVelocity.y;
    if (_fall > 2.0 && v < 0.5) {
      cue(
        'gate',
        weight: (_fall / 7).clamp(0.3, 1),
        at: body.position,
        shake: 0.45,
      );
    }
    _fall = v;
    // Coming down fast onto him.
    final Player? boy = _stage?.player;
    if (boy == null || !boy.isMounted || boy.isDead) return;
    if (body.linearVelocity.y < 2.5) return;
    final Vector2 p = boy.body.position;
    final double foot = body.position.y + size.y / 2;
    if ((p.x - body.position.x).abs() < GameConfig.playerWidth / 2 + 0.12 &&
        foot > p.y - GameConfig.playerHeight / 2 &&
        foot < p.y + GameConfig.playerHeight / 2) {
      boy.die(cause: DeathCause.crushing);
    }
  }

  static final Paint _bars = Paint()..color = _iron;

  @override
  void render(Canvas canvas) {
    final double hh = size.y / 2;
    const double hw = 0.42;
    final Vector2 c = body.position;
    if (!isOnScreen(Rect.fromLTRB(c.x - 1, c.y - hh - 1, c.x + 1, c.y + hh))) {
      return;
    }
    // A grid of flat bars, seen across the passage, spiked at the foot.
    for (final x in [-hw, -hw / 3, hw / 3, hw]) {
      canvas.drawRect(
        Rect.fromLTRB(x - 0.035, -hh, x + 0.035, hh - 0.08),
        _bars,
      );
      canvas.drawPath(
        Path()
          ..moveTo(x - 0.05, hh - 0.1)
          ..lineTo(x, hh + 0.04)
          ..lineTo(x + 0.05, hh - 0.1)
          ..close(),
        _bars,
      );
    }
    for (double y = -hh + 0.12; y < hh - 0.2; y += 0.42) {
      canvas.drawRect(Rect.fromLTRB(-hw - 0.05, y, hw + 0.05, y + 0.06), _bars);
      for (final x in [-hw, -hw / 3, hw / 3, hw]) {
        canvas.drawCircle(Offset(x, y + 0.03), 0.045, _bars);
      }
    }
  }
}

/// A wooden weighing pan on four chains, set flush in the floor over its
/// pit: weight in it pulls its rope, and what is on the other end rises.
class WeighPan extends Hoisted {
  WeighPan({
    required Vector2 floorAt,
    double width = 2.0,
    super.massKg = 8,
    required super.drop,
  }) : super(
         position: floorAt + Vector2(0, 0.15),
         size: Vector2(width, 0.3),
         rise: 0,
       );

  /// The chains meet this far above the pan.
  static const double hangs = 1.1;

  @override
  double get deck => -0.03;

  @override
  Vector2 get ropeEnd => body.position + Vector2(0, -hangs);

  @override
  void shapes(Body b) {
    // Only the boards: it runs straight down its pit, so what is in it
    // rides it without lips, and nothing stands proud of the floor.
    b.createShape(
      Polygon.offsetBox(size.x / 2, 0.12, center: Vector2(0, 0.09)),
      shapeDef(),
    );
  }

  static final Paint _woodPaint = Paint()..color = _wood;
  static final Paint _grain = Paint()..color = _seam;
  static final Paint _chain = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.025;

  @override
  void render(Canvas canvas) {
    final double hw = size.x / 2;
    final Vector2 c = body.position;
    if (!isOnScreen(
      Rect.fromLTRB(c.x - hw, c.y - hangs, c.x + hw, c.y + 0.3),
    )) {
      return;
    }
    for (final x in [-hw + 0.1, hw - 0.1]) {
      canvas.drawLine(Offset(x, -0.1), const Offset(0, -hangs), _chain);
    }
    canvas.drawCircle(const Offset(0, -hangs), 0.06, _woodPaint);
    canvas.drawRect(Rect.fromLTRB(-hw, -0.03, hw, 0.21), _woodPaint);
    for (final x in [-hw, hw - 0.1]) {
      canvas.drawRect(Rect.fromLTRB(x, -0.24, x + 0.1, 0.04), _woodPaint);
    }
    for (double x = -hw + 0.32; x < hw - 0.1; x += 0.32) {
      canvas.drawRect(Rect.fromLTRB(x, -0.02, x + 0.008, 0.2), _grain);
    }
  }
}

/// A lift: a heavy plank platform with a rail along one side, hung from
/// four ropes that meet high above it.
class LiftPlatform extends Hoisted {
  LiftPlatform({
    required super.position,
    double width = 2.8,
    super.massKg = 20,
    required super.rise,
    super.drop = 0,
    this.railLeft = true,
  }) : super(size: Vector2(width, 0.24));

  /// Which side the rail is on.
  final bool railLeft;

  /// The ropes meet this far above the deck.
  static const double hangs = 2.6;

  @override
  Vector2 get ropeEnd => body.position + Vector2(0, -hangs);

  @override
  void shapes(Body b) {
    final double hw = size.x / 2;
    final double rx = railLeft ? -hw + 0.05 : hw - 0.05;
    b
      ..createShape(Polygon.box(hw, size.y / 2), shapeDef())
      ..createShape(
        Polygon.offsetBox(0.05, 0.2, center: Vector2(rx, -size.y / 2 - 0.2)),
        shapeDef(),
      );
  }

  static final Paint _woodPaint = Paint()..color = _wood;
  static final Paint _grain = Paint()..color = _seam;
  static final Paint _rope = Paint()
    ..color = const Color(0xFF141414)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.028;

  @override
  void render(Canvas canvas) {
    final double hw = size.x / 2, hh = size.y / 2;
    final Vector2 c = body.position;
    if (!isOnScreen(
      Rect.fromLTRB(c.x - hw, c.y - hangs, c.x + hw, c.y + 0.4),
    )) {
      return;
    }
    for (final x in [-hw + 0.08, hw - 0.08]) {
      canvas.drawLine(Offset(x, -hh), const Offset(0, -hangs), _rope);
    }
    canvas.drawCircle(const Offset(0, -hangs), 0.07, _woodPaint);
    canvas.drawRect(Rect.fromLTRB(-hw, -hh, hw, hh), _woodPaint);
    // Cross-bracing under it, and the rail.
    canvas.drawPath(
      Path()
        ..moveTo(-hw + 0.1, hh)
        ..lineTo(0, hh + 0.28)
        ..lineTo(hw - 0.1, hh)
        ..lineTo(hw - 0.2, hh)
        ..lineTo(0, hh + 0.2)
        ..lineTo(-hw + 0.2, hh)
        ..close(),
      _woodPaint,
    );
    final double rx = railLeft ? -hw : hw - 0.1;
    canvas.drawRect(Rect.fromLTRB(rx, -hh - 0.42, rx + 0.1, -hh), _woodPaint);
    canvas.drawRect(
      Rect.fromLTRB(-hw + 0.1, -hh - 0.42, -hw + 0.1, -hh),
      _woodPaint,
    );
    for (double x = -hw + 0.35; x < hw - 0.1; x += 0.35) {
      canvas.drawRect(Rect.fromLTRB(x, -hh + 0.02, x + 0.008, hh), _grain);
    }
  }
}

/// An iron box of stones running in its own shaft: the other end of a
/// lift's rope. It touches nothing.
class Counterweight extends Hoisted {
  Counterweight({
    required super.position,
    required super.massKg,
    required super.rise,
    required super.drop,
  }) : super(size: Vector2(0.7, 1.0));

  @override
  void shapes(Body b) => b.createShape(
    Polygon.box(size.x / 2, size.y / 2),
    shapeDef(collides: false),
  );

  static final Paint _metal = Paint()..color = _iron;
  static final Paint _stone = Paint()..color = const Color(0x16D8D0C0);

  @override
  void render(Canvas canvas) {
    final double hw = size.x / 2, hh = size.y / 2;
    final Vector2 c = body.position;
    if (!isOnScreen(Rect.fromLTRB(c.x - hw, c.y - hh, c.x + hw, c.y + hh))) {
      return;
    }
    canvas.drawRect(Rect.fromLTRB(-hw, -hh, hw, hh), _metal);
    // Stones heaped in it, showing between the straps.
    for (var i = 0; i < 6; i++) {
      final double x = -hw + 0.12 + (i % 3) * 0.23;
      final double y = -hh + 0.2 + (i ~/ 3) * 0.35;
      canvas.drawOval(Rect.fromLTRB(x, y, x + 0.18, y + 0.12), _stone);
    }
    canvas.drawRect(Rect.fromLTRB(-hw, -0.04, hw, 0.04), _metal);
  }
}

// ---------------------------------------------------------------------------
// Furniture
// ---------------------------------------------------------------------------

/// A tall, narrow bookcase, heavy at the top with books. Walked into, it
/// tips over (its weight is too narrow at the foot to stand a push);
/// fallen, it is a long block to climb, or a bridge.
class TallBookcase extends PhysicsCrate {
  TallBookcase({
    required double x,
    required double floorY,
    double width = 0.7,
    double height = 3.0,
    super.massKg = 30,
  }) : super(
         position: Vector2(x, floorY - height / 2),
         size: Vector2(width, height),
         friction: 0.95,
       );

  /// Once it has come down flat across something and stopped, it is
  /// wedged: no longer a thing to push, only to walk over.
  bool wedged = false;
  double _still = 0;

  double _turning = 0;

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || wedged) return;
    // Its fall stopped short: it has hit.
    final double w = body.angularVelocity.abs();
    if (_turning > 1.2 && w < 0.5) {
      cue('wood', at: body.position, shake: 0.4);
    }
    _turning = w;
    final bool flat = (body.angle.abs() - math.pi / 2).abs() < 0.2;
    final bool resting =
        body.linearVelocity.length < 0.05 && body.angularVelocity.abs() < 0.05;
    _still = flat && resting ? _still + dt : 0;
    if (_still > 0.3) {
      wedged = true;
      body.type = BodyType.static;
    }
  }

  @override
  void resetToStart() {
    if (isReady && wedged) {
      wedged = false;
      body.type = BodyType.dynamic;
    }
    _still = 0;
    super.resetToStart();
  }

  static final Paint _woodPaint = Paint()..color = _wood;
  static final Paint _gap = Paint()..color = const Color(0x24BDBDBD);

  @override
  void render(Canvas canvas) {
    if (!isReady) return;
    final double hw = size.x / 2, hh = size.y / 2;
    // The case, a carved crown and feet.
    canvas.drawRect(Rect.fromLTRB(-hw, -hh + 0.12, hw, hh - 0.08), _woodPaint);
    canvas.drawPath(
      Path()
        ..moveTo(-hw - 0.06, -hh + 0.14)
        ..lineTo(-hw - 0.02, -hh + 0.02)
        ..quadraticBezierTo(0, -hh - 0.12, hw + 0.02, -hh + 0.02)
        ..lineTo(hw + 0.06, -hh + 0.14)
        ..close(),
      _woodPaint,
    );
    for (final x in [-hw + 0.04, hw - 0.12]) {
      canvas.drawRect(Rect.fromLTRB(x, hh - 0.1, x + 0.08, hh), _woodPaint);
    }
    // Its doors, barely there: a seam down the middle, panels, a keyhole.
    canvas.drawRect(Rect.fromLTRB(-0.006, -hh + 0.3, 0.006, hh - 0.2), _gap);
    for (final t in const [0.28, 0.62]) {
      final double y = -hh + size.y * t;
      canvas.drawRect(Rect.fromLTRB(-hw + 0.08, y, hw - 0.08, y + 0.008), _gap);
    }
    canvas.drawCircle(Offset(0.05, -hh + size.y * 0.5), 0.012, _gap);
    // A few books stacked on top, one leaning.
    canvas.drawRect(
      Rect.fromLTRB(-hw + 0.08, -hh - 0.14, -hw + 0.3, -hh + 0.02),
      _woodPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(hw - 0.3, -hh + 0.02)
        ..lineTo(hw - 0.22, -hh - 0.26)
        ..lineTo(hw - 0.16, -hh - 0.24)
        ..lineTo(hw - 0.22, -hh + 0.02)
        ..close(),
      _woodPaint,
    );
  }
}

/// A long, heavy table: a static block to climb or jump.
class CastleTable extends BodyComponent with OffScreenCulling {
  CastleTable({
    required this.left,
    required this.right,
    required this.floorY,
    this.height = 0.85,
  }) : super(renderBody: false);

  final double left, right, floorY, height;

  @override
  Body createBody() {
    final b = world.createBody(
      BodyDef(
        position: Vector2((left + right) / 2, floorY - height / 2),
        userData: this,
      ),
    );
    b.createShape(
      Polygon.box((right - left) / 2, height / 2),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.9),
      ),
    );
    return b;
  }

  static final Paint _woodPaint = Paint()..color = _wood;
  static final Paint _grain = Paint()..color = _seam;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(Rect.fromLTRB(left, floorY - height - 1, right, floorY))) {
      return;
    }
    final double hw = (right - left) / 2, hh = height / 2;
    canvas.drawRect(
      Rect.fromLTRB(-hw - 0.08, -hh, hw + 0.08, -hh + 0.12),
      _woodPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(-hw + 0.05, -hh + 0.1, hw - 0.05, -hh + 0.24),
      _woodPaint,
    );
    for (final x in [-hw + 0.1, hw - 0.22]) {
      canvas.drawRect(Rect.fromLTRB(x, -hh, x + 0.12, hh), _woodPaint);
    }
    // A stretcher between the legs, so the block reads as a table.
    canvas.drawRect(
      Rect.fromLTRB(-hw + 0.1, hh - 0.3, hw - 0.1, hh - 0.22),
      _woodPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(-hw - 0.05, -hh + 0.05, hw + 0.05, -hh + 0.058),
      _grain,
    );
    // A candlestick and a goblet on top.
    canvas.drawRect(
      Rect.fromLTRB(-hw * 0.4 - 0.02, -hh - 0.42, -hw * 0.4 + 0.02, -hh),
      _woodPaint,
    );
    canvas.drawRect(
      Rect.fromLTRB(-hw * 0.4 - 0.07, -hh - 0.04, -hw * 0.4 + 0.07, -hh),
      _woodPaint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(hw * 0.3 - 0.06, -hh - 0.2)
        ..lineTo(hw * 0.3 + 0.06, -hh - 0.2)
        ..lineTo(hw * 0.3 + 0.01, -hh - 0.1)
        ..lineTo(hw * 0.3 + 0.01, -hh - 0.02)
        ..lineTo(hw * 0.3 + 0.05, -hh)
        ..lineTo(hw * 0.3 - 0.05, -hh)
        ..lineTo(hw * 0.3 - 0.01, -hh - 0.02)
        ..lineTo(hw * 0.3 - 0.01, -hh - 0.1)
        ..close(),
      _woodPaint,
    );
  }
}

/// Dressed stone: a castle wall, a step, a ledge, the slab over a door.
/// Straight-edged blocks laid in courses, the mortar barely showing. Out in
/// the open ([Stage.grassy]) the same block is a rock instead: rounded,
/// split by a fissure or two, with grass on top.
class StoneBlock extends BodyComponent with OffScreenCulling {
  StoneBlock({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
    this.seed = 0,
    this.solid = true,
    super.priority,
  }) : super(renderBody: false);

  final double left, top, right, bottom;
  final int seed;

  /// False for stonework behind the play: a wall to see, not to touch.
  final bool solid;

  @override
  Body createBody() {
    final b = world.createBody(
      BodyDef(
        position: Vector2((left + right) / 2, (top + bottom) / 2),
        userData: this,
      ),
    );
    if (!solid) return b;
    b.createShape(
      Polygon.box((right - left) / 2, (bottom - top) / 2),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.9),
        enableSensorEvents: true,
      ),
    );
    return b;
  }

  static final Paint _stone = Paint()..color = const Color(0xFF070707);
  static final Paint _mortar = Paint()..color = const Color(0x14D8D0C0);
  static final Paint _worn = Paint()..color = const Color(0x08D8D0C0);
  static final Paint _crack = Paint()
    ..color = const Color(0x1AD8D0C0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.012;

  double get _hw => (right - left) / 2;
  double get _hh => (bottom - top) / 2;

  bool _rock = false;

  @override
  void onMount() {
    super.onMount();
    _rock = ancestors().whereType<Stage>().firstOrNull?.grassy ?? false;
  }

  /// A rock's outline: its corners worn round and its top a little uneven
  /// (never far from the flat top he walks on), grass along it, its sides
  /// bulging out and in.
  late final Path _rockOutline = () {
    final random = math.Random(seed * 17 + 5);
    final double hw = _hw, hh = _hh;
    final double round = math.min(0.28, math.min(hw, hh) * 0.45);
    final path = Path()..moveTo(-hw, -hh + round);
    path.quadraticBezierTo(-hw, -hh, -hw + round, -hh);
    double x = -hw + round;
    while (x < hw - round) {
      final double step = math.min(
        hw - round - x,
        0.3 + random.nextDouble() * 0.5,
      );
      final double r = random.nextDouble();
      if (r < 0.45 && step > 0.2) {
        // A clump of grass.
        final double bx = x + step * 0.5;
        for (var k = 0; k < 3; k++) {
          final double t = bx - 0.08 + k * 0.07;
          final double tall = 0.08 + random.nextDouble() * 0.12;
          final double lean = (random.nextDouble() - 0.4) * 0.08;
          path
            ..lineTo(t - 0.02, -hh)
            ..lineTo(t + lean, -hh - tall)
            ..lineTo(t + 0.02, -hh);
        }
      }
      x += step;
      // The top stays within a couple of centimetres of the flat.
      path.lineTo(x, -hh + random.nextDouble() * 0.025 - 0.008);
    }
    path
      ..lineTo(hw - round, -hh)
      ..quadraticBezierTo(hw, -hh, hw, -hh + round);
    for (double y = -hh + round; y < hh - 0.2;) {
      final double step = 0.25 + random.nextDouble() * 0.35;
      final double out = (random.nextDouble() - 0.35) * 0.05;
      path.quadraticBezierTo(hw + out * 2, y + step / 2, hw, y + step);
      y += step;
    }
    path.lineTo(hw, hh);
    path.lineTo(-hw, hh);
    for (double y = hh - 0.2; y > -hh + round;) {
      final double step = math.min(
        y - (-hh + round),
        0.25 + random.nextDouble() * 0.35,
      );
      final double out = (random.nextDouble() - 0.35) * 0.05;
      path.quadraticBezierTo(-hw - out * 2, y - step / 2, -hw, y - step);
      y -= step;
      if (step < 0.01) break;
    }
    return path..close();
  }();

  /// A rock's face: a fissure or two running down it, and a few paler
  /// planes where it has split.
  late final (Path, Path) _rockDetail = () {
    final faces = Path(), fissures = Path();
    final random = math.Random(seed * 11 + 9);
    final double hw = _hw, hh = _hh;
    final int count = 1 + (hw * 2 / 1.6).floor().clamp(0, 5);
    for (var i = 0; i < count; i++) {
      final double fx =
          -hw + (i + 0.3 + random.nextDouble() * 0.4) * (2 * hw) / count;
      double y = -hh + 0.06 + random.nextDouble() * 0.2;
      double x = fx;
      fissures.moveTo(x, y);
      final double end = math.min(
        hh - 0.05,
        y + 0.3 + random.nextDouble() * hh,
      );
      while (y < end) {
        y += 0.08 + random.nextDouble() * 0.12;
        x += (random.nextDouble() - 0.5) * 0.1;
        fissures.lineTo(x, math.min(y, end));
      }
      if (random.nextDouble() < 0.6 && hh > 0.4) {
        // Kept inside the rock's sides and off its top and bottom.
        final double py = -hh + 0.1 + random.nextDouble() * (hh * 1.2);
        final double pw = math.min(
          0.2 + random.nextDouble() * 0.35,
          hw - 0.08 - (fx + 0.04),
        );
        final double ph = math.min(
          0.18 + random.nextDouble() * 0.15,
          hh - 0.08 - py,
        );
        if (pw > 0.08 && ph > 0.08) {
          faces.addPolygon([
            Offset(fx + 0.04, py),
            Offset(fx + 0.04 + pw, py + 0.05),
            Offset(fx + 0.04 + pw * 0.8, py + ph),
            Offset(fx + 0.06, py + ph * 0.75),
          ], true);
        }
      }
    }
    return (faces, fissures);
  }();

  /// Its outline: straight where the collision is, but its top edge
  /// chipped, its sides a little uneven, a weed or two on top and, under a
  /// block that hangs over open air, the odd root or strand of moss.
  late final Path _outline = () {
    final random = math.Random(seed * 13 + 1);
    final double hw = _hw, hh = _hh;
    final path = Path()..moveTo(-hw, -hh + 0.04);
    // Along the top: chips taken out of it, weeds growing from it.
    double x = -hw;
    while (x < hw) {
      final double step = math.min(hw - x, 0.25 + random.nextDouble() * 0.6);
      final double r = random.nextDouble();
      if (r < 0.18 && step > 0.25) {
        // A chip out of the edge.
        final double d = 0.03 + random.nextDouble() * 0.07;
        path
          ..lineTo(x + step * 0.3, -hh)
          ..lineTo(x + step * 0.45, -hh + d)
          ..lineTo(x + step * 0.7, -hh + d * 0.6)
          ..lineTo(x + step * 0.85, -hh);
      } else if (r < 0.26 && hw > 1) {
        // A tuft of weeds.
        final double bx = x + step * 0.5;
        path
          ..lineTo(bx - 0.05, -hh)
          ..lineTo(bx - 0.09, -hh - 0.12 - random.nextDouble() * 0.08)
          ..lineTo(bx - 0.02, -hh - 0.02)
          ..lineTo(bx + 0.01, -hh - 0.16 - random.nextDouble() * 0.08)
          ..lineTo(bx + 0.04, -hh - 0.02)
          ..lineTo(bx + 0.1, -hh - 0.1)
          ..lineTo(bx + 0.06, -hh);
      }
      x += step;
      path.lineTo(x, -hh + (random.nextDouble() < 0.3 ? 0.012 : 0));
    }
    // Down the right side, a little rough.
    for (double y = -hh + 0.3; y < hh; y += 0.3 + random.nextDouble() * 0.4) {
      path.lineTo(hw - random.nextDouble() * 0.025, y);
    }
    path.lineTo(hw, hh);
    // Along the bottom, right to left: roots or moss hanging from it.
    x = hw;
    while (x > -hw) {
      final double step = math.min(x + hw, 0.4 + random.nextDouble() * 0.9);
      if (random.nextDouble() < 0.12 && hw > 1) {
        final double bx = x - step * 0.5;
        final double len = 0.15 + random.nextDouble() * 0.35;
        path
          ..lineTo(bx + 0.04, hh)
          ..quadraticBezierTo(bx + 0.02, hh + len * 0.6, bx - 0.01, hh + len)
          ..quadraticBezierTo(bx - 0.02, hh + len * 0.5, bx - 0.04, hh);
      }
      x -= step;
      path.lineTo(x, hh);
    }
    for (double y = hh - 0.3; y > -hh; y -= 0.3 + random.nextDouble() * 0.4) {
      path.lineTo(-hw + random.nextDouble() * 0.025, y);
    }
    return path..close();
  }();

  /// Courses of different heights, blocks of different lengths; a few
  /// faces a shade worn, a few cracked.
  late final (Path, Path, Path) _detail = () {
    final joints = Path(), worn = Path(), cracks = Path();
    final random = math.Random(seed * 7 + 3);
    final double hw = _hw, hh = _hh;
    double y = -hh;
    while (y < hh - 0.05) {
      final double course = 0.32 + random.nextDouble() * 0.24;
      final double bottomY = math.min(hh, y + course);
      if (bottomY < hh - 0.02) {
        joints.addRect(Rect.fromLTRB(-hw, bottomY, hw, bottomY + 0.012));
      }
      double x = -hw - random.nextDouble() * 0.6;
      while (x < hw) {
        final double len = 0.5 + random.nextDouble() * 0.8;
        final double l = math.max(-hw, x), r = math.min(hw, x + len);
        if (r - l > 0.1) {
          if (random.nextDouble() < 0.18) {
            worn.addRect(
              Rect.fromLTRB(l + 0.02, y + 0.02, r - 0.02, bottomY - 0.02),
            );
          }
          if (random.nextDouble() < 0.08) {
            final double cx = l + (r - l) * random.nextDouble();
            cracks
              ..moveTo(cx, y + 0.02)
              ..lineTo(cx + 0.05, y + (bottomY - y) * 0.4)
              ..lineTo(cx - 0.02, y + (bottomY - y) * 0.7)
              ..lineTo(cx + 0.03, bottomY - 0.02);
          }
        }
        x += len;
        if (x < hw - 0.05) {
          joints.addRect(Rect.fromLTRB(x, y, x + 0.012, bottomY));
        }
      }
      y = bottomY;
    }
    return (joints, worn, cracks);
  }();

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(Rect.fromLTRB(left, top - 0.3, right, bottom + 0.6))) {
      return;
    }
    if (_rock) {
      final (faces, fissures) = _rockDetail;
      canvas
        ..drawPath(_rockOutline, _stone)
        ..drawPath(faces, _worn)
        ..drawPath(fissures, _crack);
      return;
    }
    final (joints, worn, cracks) = _detail;
    canvas
      ..drawPath(_outline, _stone)
      ..drawPath(worn, _worn)
      ..drawPath(joints, _mortar)
      ..drawPath(cracks, _crack);
  }
}

// ---------------------------------------------------------------------------
// Light
// ---------------------------------------------------------------------------

/// Draws every light's glow, behind the world's silhouettes, so they stand
/// out black against it as everything does against the fog.
class LightLayer extends Component {
  LightLayer({super.priority = -36});

  Stage? _stage;

  @override
  Future<void> onLoad() async {
    _stage = ancestors().whereType<Stage>().firstOrNull;
  }

  @override
  void render(Canvas canvas) {
    final Stage? stage = _stage;
    if (stage == null) return;
    for (final light in stage.lights) {
      if (light is GlowingLight) light.paintLight(canvas);
    }
  }
}

/// A light that draws its own glow (in the [LightLayer]).
abstract interface class GlowingLight implements LightSource {
  void paintLight(Canvas canvas);
}

/// A tall window high in the wall, shuttered. Opened, the moon pours a
/// slanting shaft of light down to the floor, where the vampires will not
/// go.
///
/// The window's art is drawn by the chapter; this is its panes' rectangle,
/// the shutters over them, and the light.
class MoonWindow extends Component
    with StageLight
    implements GlowingLight, HasFootprint {
  MoonWindow({
    required this.paneLeft,
    required this.paneRight,
    required this.paneTop,
    required this.paneBottom,
    required this.floorY,
    this.slant = 0.3,
    bool open = false,
    super.priority = -30,
  }) : _open = open ? 1 : 0,
       _goal = open ? 1 : 0;

  final double paneLeft, paneRight, paneTop, paneBottom, floorY;

  /// How far the light moves sideways for each metre it falls.
  final double slant;

  double _open, _goal;
  double _time = 0;

  bool get isOpen => _open > 0.6;

  /// The pane, and its shutters swung out a pane's width either side.
  @override
  Rect get footprint => Rect.fromLTRB(
    paneLeft - (paneRight - paneLeft),
    paneTop,
    paneRight + (paneRight - paneLeft),
    paneBottom,
  );

  void open() => _goal = 1;

  /// Shut again (after a death undid the boy's work).
  void shut() {
    _goal = 0;
    _open = 0;
  }

  /// Where the light lies on the floor.
  (double, double) get floorSpan => (
    paneLeft + slant * (floorY - paneBottom),
    paneRight + slant * (floorY - paneTop),
  );

  (double, double) _spanAt(double y) => (
    y < paneBottom ? paneLeft : paneLeft + slant * (y - paneBottom),
    paneRight + slant * (y - paneTop),
  );

  @override
  bool lights(Vector2 p) {
    if (!isOpen || p.y < paneTop || p.y > floorY + 0.3) return false;
    final (double l, double r) = _spanAt(math.min(p.y, floorY));
    return p.x >= l && p.x <= r;
  }

  @override
  void update(double dt) {
    _time += dt;
    // The shutters swing back on their hinges, quick then slowing.
    _open += (_goal - _open) * math.min(1, dt * 2.6);
  }

  final Paint _beam = Paint();
  static final Paint _leaf = Paint()..color = _wood;
  static final Paint _strap = Paint()..color = _iron;
  final Paint _speck = Paint();

  /// Out in the open there is no window: the moon comes out from behind
  /// the cloud and its light falls through the trees. No panes, no
  /// shutters; only the shaft of light.
  bool get _sky => stage?.grassy ?? false;

  @override
  void paintLight(Canvas canvas) {
    final double a = _open * (0.92 + 0.08 * math.sin(_time * 0.7));
    if (a <= 0.01) return;
    final Color moon = Palette.moonLight;
    final (double fl, double fr) = floorSpan;
    if (!_sky) {
      // The sky in the panes.
      _beam
        ..shader = null
        ..color = moon.withValues(alpha: 0.55 * a);
      canvas.drawRect(
        Rect.fromLTRB(paneLeft, paneTop - 1.2, paneRight, paneBottom),
        _beam,
      );
    }
    final beam = Path()
      ..moveTo(paneLeft, paneTop)
      ..lineTo(paneRight, paneTop)
      ..lineTo(fr, floorY)
      ..lineTo(fl, floorY)
      ..lineTo(paneLeft, paneBottom)
      ..close();
    _beam
      ..color = const Color(0xFFFFFFFF)
      ..shader = Gradient.linear(Offset(0, paneTop), Offset(0, floorY), [
        moon.withValues(alpha: 0.30 * a),
        moon.withValues(alpha: 0.13 * a),
      ]);
    canvas.drawPath(beam, _beam);
    // A softer, wider beam around it, for the edges.
    canvas.drawPath(
      Path()
        ..moveTo(paneLeft - 0.25, paneTop)
        ..lineTo(paneRight + 0.25, paneTop)
        ..lineTo(fr + 0.45, floorY)
        ..lineTo(fl - 0.45, floorY)
        ..close(),
      _beam
        ..shader = Gradient.linear(Offset(0, paneTop), Offset(0, floorY), [
          moon.withValues(alpha: 0.08 * a),
          moon.withValues(alpha: 0.05 * a),
        ]),
    );
    // The pool on the floor.
    _beam.shader = Gradient.radial(
      Offset((fl + fr) / 2, floorY),
      (fr - fl) * 0.7,
      [moon.withValues(alpha: 0.32 * a), moon.withValues(alpha: 0)],
    );
    canvas.drawOval(
      Rect.fromLTRB(fl - 0.6, floorY - 0.5, fr + 0.6, floorY + 0.3),
      _beam,
    );
    _beam.shader = null;
    // Dust turning in it.
    for (var i = 0; i < 22; i++) {
      final double u = (i * 0.618034 + _time * 0.013 * (1 + i % 3)) % 1.0;
      final double v = (i * 0.414 + _time * 0.02 * (1 + i % 2)) % 1.0;
      final double y = paneTop + (floorY - paneTop) * v;
      final (double l, double r) = _spanAt(y);
      final double x = l + (r - l) * u;
      _speck.color = moon.withValues(alpha: 0.5 * a * math.sin(v * math.pi));
      canvas.drawCircle(Offset(x, y), 0.012, _speck);
    }
  }

  @override
  void render(Canvas canvas) {
    if (_sky) return;
    // The shutters over the panes (the panes' light is drawn behind the
    // window's stonework, in [paintLight], so it shows through its holes).
    final double w = paneRight - paneLeft;
    final double leaf = w / 2 * (1 - _open * 0.86);
    for (final side in [-1.0, 1.0]) {
      final double hinge = side < 0 ? paneLeft : paneRight;
      final double edge = hinge - side * leaf;
      // Swinging out towards us, the free edge rises and falls a little.
      final double skew = _open * 0.08;
      final leafPath = Path()
        ..moveTo(hinge, paneTop - 0.04)
        ..lineTo(edge, paneTop - 0.04 - skew)
        ..lineTo(edge, paneBottom + 0.04 + skew)
        ..lineTo(hinge, paneBottom + 0.04)
        ..close();
      canvas.drawPath(leafPath, _leaf);
      for (final t in [0.2, 0.8]) {
        final double y = paneTop + (paneBottom - paneTop) * t;
        canvas.drawRect(
          Rect.fromLTRB(
            math.min(hinge, edge),
            y - 0.03,
            math.max(hinge, edge),
            y + 0.03,
          ),
          _strap,
        );
      }
    }
  }
}

/// A cart with a lantern on a post: pushed or pulled like any cart, it
/// carries its pool of light with it. The lantern swings as it goes.
class LanternCart extends Cart with StageLight implements GlowingLight {
  LanternCart({required super.x, required super.groundY})
    : super(shafts: false);

  /// How far the light reaches around the flame.
  static const double radius = 2.5;

  static const double _post = 1.5;
  double _swing = 0, _swingSpeed = 0, _time = 0;
  double _lastVx = 0;

  /// The flame, world metres.
  Vector2 get flame {
    if (!isReady) return Vector2.zero();
    final Vector2 top = body.worldPoint(Vector2(0.5, -size.y / 2 - _post));
    return top + Vector2(math.sin(_swing), math.cos(_swing)) * 0.32;
  }

  @override
  bool lights(Vector2 p) => isReady && (p - flame).length < radius * 0.9;

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || dt <= 0) return;
    _time += dt;
    // A pendulum on the post's arm, kicked by the cart's acceleration.
    final double vx = body.linearVelocity.x;
    final double accel = (vx - _lastVx) / dt;
    _lastVx = vx;
    _swingSpeed +=
        (-GameConfig.gravityMetersPerSecondSquared / 0.32 * math.sin(_swing) -
            accel / 0.32 * math.cos(_swing)) *
        dt;
    _swingSpeed *= math.exp(-1.6 * dt);
    _swing += _swingSpeed * dt;
  }

  @override
  void paintLight(Canvas canvas) {
    if (!isReady) return;
    final double f = Glow.flicker(_time, 3);
    Glow.round(
      canvas,
      flame.toOffset(),
      radius * (1.15 + 0.03 * f),
      Palette.lampAmber,
      0.42 + 0.05 * f,
    );
  }

  static final Paint _metal = Paint()..color = _iron;
  static final Paint _cord = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.02;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (!isReady) return;
    // The post and its arm, in the cart's frame.
    final double top = -size.y / 2 - _post;
    canvas.drawRect(Rect.fromLTRB(0.46, top, 0.54, -size.y / 2), _metal);
    canvas.drawRect(Rect.fromLTRB(0.3, top, 0.7, top + 0.05), _metal);
    // The lantern hangs straight down in the world, whatever the cart.
    canvas.save();
    canvas.translate(0.5, top);
    canvas.rotate(-body.angle - _swing);
    canvas.drawLine(Offset.zero, const Offset(0, 0.18), _cord);
    canvas.drawPath(
      Path()
        ..moveTo(-0.07, 0.18)
        ..lineTo(0.07, 0.18)
        ..lineTo(0.1, 0.24)
        ..lineTo(0.08, 0.44)
        ..lineTo(-0.08, 0.44)
        ..lineTo(-0.1, 0.24)
        ..close(),
      _metal,
    );
    Glow.flame(
      canvas,
      const Offset(0, 0.4),
      0.12,
      Palette.lampAmber,
      Glow.flicker(_time, 3),
    );
    canvas.restore();
  }
}

/// A great iron chandelier hung on a rope from the vault, its candles lit.
/// [release] lets the rope go: it falls with its whole weight, crushes
/// what is under it, and lies where it lands.
class HungChandelier extends BodyComponent
    with OffScreenCulling, StageLight
    implements GlowingLight {
  HungChandelier({
    required this.anchor,
    required this.ropeLength,
    this.width = 2.6,
    this.massKg = 140,
    this.lit = true,
  }) : super(renderBody: false);

  final Vector2 anchor;
  final double ropeLength, width, massKg;
  bool lit;

  /// The art is this much taller than wide.
  static const double aspect = 708 / 550;
  double get height => width * aspect;

  DistanceJoint? _rope;
  late final Body _hook;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;
  bool get released => _rope == null;

  /// Set when it hits the floor.
  bool landed = false;

  /// Down and still: jammed where it fell, to be walked over.
  bool wedged = false;
  double _still = 0;
  double _time = 0;
  Image? _art;

  /// Where the candles' light reaches round its middle.
  double get radius => width * 1.0;

  @override
  bool lights(Vector2 p) =>
      lit && isReady && (p - body.position).length < radius * 0.9;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _art = await Flame.images.load('part3/ch9_far_chandelier.png');
    } catch (_) {
      // A bare test binding has no images.
    }
  }

  @override
  Body createBody() {
    _hook = world.createBody(BodyDef(position: anchor));
    final Vector2 at = anchor + Vector2(0, ropeLength + height / 2);
    final b = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: at,
        angularDamping: 0.6,
        userData: this,
        isBullet: true,
      ),
    );
    final double hw = width / 2, hh = height / 2;
    // The wide ring of arms, the narrow crown above, the boss below.
    b.createShape(
      Polygon([
        Vector2(-hw * 0.95, hh * 0.05),
        Vector2(hw * 0.95, hh * 0.05),
        Vector2(hw * 0.45, hh * 0.75),
        Vector2(-hw * 0.45, hh * 0.75),
      ]),
      ShapeDef(
        density: 10,
        filter: CollisionLayers.propFilter(),
        material: SurfaceMaterial(friction: 0.8),
        enableHitEvents: true,
        enableSensorEvents: true,
      ),
    );
    // Above the ring, a low hump (the upper tiers crumple when it lands),
    // gentle enough to walk over once it lies across something.
    b.createShape(
      Polygon([
        Vector2(-hw * 0.4, -hh * 0.2),
        Vector2(hw * 0.4, -hh * 0.2),
        Vector2(hw * 0.95, hh * 0.05),
        Vector2(-hw * 0.95, hh * 0.05),
      ]),
      ShapeDef(
        density: 10,
        filter: CollisionLayers.propFilter(),
        material: SurfaceMaterial(friction: 0.8),
        enableHitEvents: true,
      ),
    );
    b.massData = MassData(
      mass: massKg,
      center: b.localCenterOfMass,
      rotationalInertia: b.rotationalInertia * massKg / b.mass,
    );
    _rope = world.physicsWorld.createDistanceJoint(
      DistanceJointDef(
        bodyA: _hook,
        bodyB: b,
        localAnchorB: Vector2(0, -hh),
        length: ropeLength,
        enableLimit: true,
        minLength: ropeLength,
        maxLength: ropeLength,
      ),
    );
    _ready = true;
    return b;
  }

  /// Lets the rope go.
  void release() {
    final rope = _rope;
    if (rope == null) return;
    if (rope.isValid) rope.destroy();
    _rope = null;
  }

  /// Hung again, lit, as it was (after a death undid the boy's work).
  void rehang() {
    if (!isReady) return;
    if (wedged) {
      wedged = false;
      body.type = BodyType.dynamic;
    }
    _still = 0;
    body
      ..setTransform(
        anchor + Vector2(0, ropeLength + height / 2),
        const Rot.identity(),
      )
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;
    _rope ??= world.physicsWorld.createDistanceJoint(
      DistanceJointDef(
        bodyA: _hook,
        bodyB: body,
        localAnchorB: Vector2(0, -height / 2),
        length: ropeLength,
        enableLimit: true,
        minLength: ropeLength,
        maxLength: ropeLength,
      ),
    );
    landed = false;
    lit = true;
  }

  /// Falling now, fast enough to kill.
  bool get crushing => isReady && released && body.linearVelocity.y > 4;

  /// Its underside, world metres.
  double get bottom => isReady ? body.position.y + height * 0.38 : 0;

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady) return;
    _time += dt;
    if (released && !landed) {
      for (final hit in body.world.contactEvents.hit) {
        if (!hit.shapeA.isValid || !hit.shapeB.isValid) continue;
        if (hit.shapeA.body != body && hit.shapeB.body != body) continue;
        if (hit.approachSpeed > 3) {
          landed = true;
          // The candles go out in the crash.
          lit = false;
          cue('gate', at: body.position, shake: 0.8);
          cue('wood', weight: 0.7, at: body.position);
        }
      }
    }
    if (landed && !wedged) {
      final bool resting =
          body.linearVelocity.length < 0.05 &&
          body.angularVelocity.abs() < 0.05;
      _still = resting ? _still + dt : 0;
      if (_still > 0.3) {
        wedged = true;
        body.type = BodyType.static;
      }
    }
    // Falling onto him.
    final Player? boy = stage?.player;
    if (boy == null || !crushing || boy.isDead || !boy.isMounted) return;
    final Vector2 p = boy.body.position;
    if ((p.x - body.position.x).abs() < width * 0.42 &&
        bottom > p.y - GameConfig.playerHeight / 2 &&
        bottom < p.y + GameConfig.playerHeight / 2 + 0.2) {
      boy.die(cause: DeathCause.crushing);
    }
  }

  @override
  void paintLight(Canvas canvas) {
    if (!lit || !isReady) return;
    final double f = Glow.flicker(_time, 11);
    Glow.round(
      canvas,
      body.position.toOffset(),
      radius * (1.2 + 0.03 * f),
      Palette.lampAmber,
      0.34 + 0.04 * f,
    );
  }

  static final Paint _paint = Paint()..filterQuality = FilterQuality.low;
  static final Paint _ropePaint = Paint()
    ..color = const Color(0xFF141414)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.04;
  static final Paint _metal = Paint()..color = _iron;

  @override
  void renderTree(Canvas canvas) {
    if (!isReady) return;
    final Vector2 c = body.position;
    if (!isOnScreen(
      Rect.fromLTRB(
        c.x - width,
        math.min(anchor.y, c.y - height),
        c.x + width,
        c.y + height,
      ),
    )) {
      return;
    }
    if (!released) {
      final Vector2 top = body.worldPoint(Vector2(0, -height / 2));
      canvas.drawLine(anchor.toOffset(), top.toOffset(), _ropePaint);
      canvas.drawCircle(anchor.toOffset(), 0.12, _metal);
    }
    super.renderTree(canvas);
  }

  @override
  void render(Canvas canvas) {
    final double hw = width / 2, hh = height / 2;
    final Image? art = _art;
    if (art != null) {
      canvas.drawImageRect(
        art,
        Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
        Rect.fromLTRB(-hw, -hh, hw, hh),
        _paint,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(-hw, 0)
          ..lineTo(hw, 0)
          ..lineTo(hw * 0.4, hh * 0.7)
          ..lineTo(-hw * 0.4, hh * 0.7)
          ..close(),
        _metal,
      );
    }
    if (!lit) return;
    // Flames on the candles of the three tiers.
    for (final (double y, double span, int n) in const [
      (-0.29, 0.44, 7),
      (0.03, 0.9, 11),
      (0.43, 0.42, 6),
    ]) {
      for (var i = 0; i < n; i++) {
        final double x = (i / (n - 1) - 0.5) * 2 * span * hw;
        Glow.flame(
          canvas,
          Offset(x, y * hh),
          0.07,
          Palette.lampAmber,
          Glow.flicker(_time, i * 5 + n),
        );
      }
    }
  }

  @override
  void onRemove() {
    if (_ready && _hook.isValid) world.destroyBody(_hook);
    super.onRemove();
  }
}

/// A chandelier hanging on a long rope from the vault, its candles lit: a
/// rope to catch and swing on like any other, carrying its light as it
/// swings.
class ChandelierRope extends SwingRope with StageLight implements GlowingLight {
  ChandelierRope({
    required super.anchor,
    required super.length,
    this.width = 1.7,
  }) : super(support: RopeSupport.ring);

  final double width;
  double get _height => width * HungChandelier.aspect;
  double _time = 0;
  Image? _art;

  /// Where the candles' light reaches round it.
  double get radius => width * 1.1;

  /// The middle of the chandelier, world metres.
  Vector2 get centre {
    if (!isReady) return anchor + Vector2(0, length);
    final Vector2 end = pointAt(length);
    final Vector2 before = pointAt(length - 0.15);
    final Vector2 down = (end - before)..normalize();
    return end + down * (_height * 0.5);
  }

  @override
  bool lights(Vector2 p) => isReady && (p - centre).length < radius * 0.9;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    try {
      _art = await Flame.images.load('part3/ch9_far_chandelier.png');
    } catch (_) {
      // A bare test binding has no images.
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  @override
  void paintLight(Canvas canvas) {
    if (!isReady) return;
    final double f = Glow.flicker(_time, 17);
    Glow.round(
      canvas,
      centre.toOffset(),
      radius * (1.25 + 0.03 * f),
      Palette.lampAmber,
      0.3 + 0.04 * f,
    );
  }

  static final Paint _artPaint = Paint()..filterQuality = FilterQuality.low;
  static final Paint _metal = Paint()..color = _iron;

  @override
  void drawEnd(Canvas canvas, Offset end, Offset down) {
    final double hw = width / 2, h = _height;
    canvas.save();
    canvas.translate(end.dx, end.dy);
    canvas.rotate(-math.atan2(down.dx, down.dy));
    final Image? art = _art;
    if (art != null) {
      canvas.drawImageRect(
        art,
        Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
        Rect.fromLTRB(-hw, 0, hw, h),
        _artPaint,
      );
    } else {
      canvas.drawPath(
        Path()
          ..moveTo(-hw, h * 0.5)
          ..lineTo(hw, h * 0.5)
          ..lineTo(hw * 0.4, h)
          ..lineTo(-hw * 0.4, h)
          ..close(),
        _metal,
      );
    }
    for (final (double y, double span, int n) in const [
      (0.355, 0.44, 5),
      (0.515, 0.9, 8),
      (0.715, 0.42, 4),
    ]) {
      for (var i = 0; i < n; i++) {
        final double x = (i / (n - 1) - 0.5) * 2 * span * hw;
        Glow.flame(
          canvas,
          Offset(x, y * h),
          0.06,
          Palette.lampAmber,
          Glow.flicker(_time, i * 3 + n),
        );
      }
    }
    canvas.restore();
  }
}

/// A short cord hanging from a pulley in the vault, an iron handle on its
/// end. He jumps and hangs on it; his weight draws it down, and that does
/// whatever it is tied to: opens a shutter, slips a latch.
class PullCord extends SwingRope {
  PullCord({required super.anchor, super.length = 1.6, required this.onPulled})
    : super(support: RopeSupport.ring);

  final void Function() onPulled;
  bool pulled = false;
  double _held = 0;
  Stage? _stage;

  /// Ready to be pulled again.
  void reset() {
    pulled = false;
    _held = 0;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _stage = ancestors().whereType<Stage>().firstOrNull;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final Player? boy = _stage?.player;
    if (boy == null || !boy.isMounted) return;
    if (boy.interactions.attachedRope == this) {
      _held += dt;
      if (!pulled && _held > 0.25) {
        pulled = true;
        cue('chain', weight: 0.8, at: anchor);
        onPulled();
      }
    } else {
      _held = 0;
    }
  }

  static final Paint _metal = Paint()..color = _iron;

  @override
  void drawEnd(Canvas canvas, Offset end, Offset down) {
    // A T-handle of iron.
    canvas.save();
    canvas.translate(end.dx, end.dy);
    canvas.rotate(-math.atan2(down.dx, down.dy));
    canvas.drawRect(const Rect.fromLTRB(-0.02, 0, 0.02, 0.12), _metal);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(-0.16, 0.1, 0.16, 0.16),
        const Radius.circular(0.03),
      ),
      _metal,
    );
    canvas.restore();
  }
}

/// Steps drawn over a ramp of the ground between [from] and [to], so it
/// reads as a stair: each tread level with the top of the ramp under it,
/// so the ramp never shows above them. Added after the ground and before
/// the boy, it is drawn over the one and behind the other; his feet stay
/// on the ramp.
class Staircase extends Component with OffScreenCulling {
  Staircase({
    required this.from,
    required this.to,
    this.rise = 0.2,
    this.surface,
    super.priority,
  });

  final Vector2 from, to;
  final double rise;

  /// The ground's real height at x, if known: each tread is laid at the
  /// highest point of it under the tread.
  final double Function(double x)? surface;

  double _tread(double x0, double x1, double fallback) {
    final double Function(double)? ground = surface;
    if (ground == null) return fallback;
    double top = double.infinity;
    for (var k = 0; k <= 8; k++) {
      top = math.min(top, ground(x0 + (x1 - x0) * k / 8));
    }
    return math.min(top, fallback) - 0.01;
  }

  late final Path _steps = () {
    final int n = math.max(1, ((to.y - from.y).abs() / rise).round());
    final double run = (to.x - from.x) / n;
    final double step = (to.y - from.y) / n;
    final double base = math.max(from.y, to.y) + 0.4;
    final path = Path()..moveTo(from.x, base);
    final bool up = to.y < from.y;
    for (var i = 0; i < n; i++) {
      final double x0 = from.x + i * run, x1 = x0 + run;
      // Going up, the tread at the ramp's height at its far end; going
      // down, at its near end.
      final double y = _tread(x0, x1, from.y + (up ? i + 1 : i) * step);
      path
        ..lineTo(x0, y)
        ..lineTo(x1, y);
    }
    path
      ..lineTo(to.x, base)
      ..close();
    return path;
  }();

  late final Path _nosings = () {
    final int n = math.max(1, ((to.y - from.y).abs() / rise).round());
    final double run = (to.x - from.x) / n;
    final double step = (to.y - from.y) / n;
    final bool up = to.y < from.y;
    final path = Path();
    for (var i = 0; i < n; i++) {
      final double x0 = from.x + i * run;
      final double y = _tread(x0, x0 + run, from.y + (up ? i + 1 : i) * step);
      path.addRect(Rect.fromLTRB(x0, y, x0 + run, y + 0.012));
    }
    return path;
  }();

  static final Paint _stone = Paint()..color = const Color(0xFF060606);
  static final Paint _edge = Paint()..color = const Color(0x18D8D0C0);

  @override
  void render(Canvas canvas) {
    final Rect area = Rect.fromLTRB(
      math.min(from.x, to.x),
      math.min(from.y, to.y) - 0.3,
      math.max(from.x, to.x),
      math.max(from.y, to.y) + 0.4,
    );
    if (!isOnScreen(area)) return;
    canvas
      ..drawPath(_steps, _stone)
      ..drawPath(_nosings, _edge);
  }
}

/// A stone balustrade along the edge of a gallery: a rail on a row of
/// turned balusters, with posts. Seen, not touched.
class Balustrade extends Component with OffScreenCulling {
  Balustrade({
    required this.left,
    required this.right,
    required this.floorY,
    this.height = 0.95,
    super.priority = -6,
  });

  final double left, right, floorY, height;

  late final Path _shape = () {
    final path = Path()
      ..addRect(
        Rect.fromLTRB(left, floorY - height, right, floorY - height + 0.1),
      )
      ..addRect(Rect.fromLTRB(left, floorY - 0.12, right, floorY));
    for (double x = left + 0.2; x < right - 0.1; x += 0.34) {
      // A baluster: narrow neck, a swelling belly, a narrow foot.
      final double top = floorY - height + 0.1, bottom = floorY - 0.12;
      final double h = bottom - top;
      path
        ..moveTo(x - 0.03, top)
        ..lineTo(x + 0.03, top)
        ..quadraticBezierTo(x + 0.02, top + h * 0.3, x + 0.075, top + h * 0.62)
        ..quadraticBezierTo(x + 0.06, top + h * 0.9, x + 0.035, bottom)
        ..lineTo(x - 0.035, bottom)
        ..quadraticBezierTo(x - 0.06, top + h * 0.9, x - 0.075, top + h * 0.62)
        ..quadraticBezierTo(x - 0.02, top + h * 0.3, x - 0.03, top)
        ..close();
    }
    for (
      double x = left;
      x <= right + 0.01;
      x += math.max(1.6, (right - left) / 4)
    ) {
      path.addRect(
        Rect.fromLTRB(x - 0.09, floorY - height - 0.08, x + 0.09, floorY),
      );
    }
    return path;
  }();

  static final Paint _stone = Paint()..color = const Color(0xFF292A2B);

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(
      Rect.fromLTRB(left, floorY - height - 0.1, right, floorY),
    )) {
      return;
    }
    canvas.drawPath(_shape, _stone);
  }
}
