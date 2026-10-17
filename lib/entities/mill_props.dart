import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';
import '../physics/water.dart';
import '../render/culling.dart';

const Color _wood = Color(0xFF070605);
const Color _iron = Color(0xFF050505);

/// An undershot mill wheel, its lowest paddles in a mill race. A real
/// wheel on an axle: what turns it is the water running past its wet
/// paddles, pushing on each as hard as the water is faster than it,
/// against the wheel's weight and the drag in its bearing. Still water
/// leaves it still.
class Waterwheel extends BodyComponent with OffScreenCulling {
  Waterwheel({
    required this.axle,
    required this.radius,
    required this.race,
    this.paddles = 12,
    this.paddle = 0.9,
    this.massKg = 400,
    super.priority = -8,
  }) : super(renderBody: false);

  final Vector2 axle;
  final double radius;
  final WaterBody race;
  final int paddles;

  /// How far each paddle reaches out past the rim.
  final double paddle;
  final double massKg;

  late final Body _pin;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;

  /// How far it has turned since it was built, radians.
  double turned = 0;

  double get turning => isReady ? body.angularVelocity : 0;

  @override
  Body createBody() {
    _pin = world.createBody(BodyDef(position: axle));
    final b = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: axle.clone(),
        angularDamping: 0.05,
        userData: this,
      ),
    );
    // A disc that touches nothing: the water's push on it is worked out
    // here, from its paddles.
    b.createShape(
      Circle(radius: radius),
      ShapeDef(
        density: 1,
        filter: Filter(categoryBits: CollisionLayers.prop, maskBits: 0),
      ),
    );
    b.massData = MassData(
      mass: massKg,
      center: Vector2.zero(),
      rotationalInertia: massKg * radius * radius * 0.7,
    );
    world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: _pin,
        bodyB: b,
        // The bearing's friction.
        enableMotor: true,
        maxMotorTorque: 120,
      ),
    );
    _ready = true;
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || dt <= 0) return;
    turned += body.angularVelocity * dt;
    // Each paddle under the surface takes the push of the water running
    // past it: as much as the water outruns the paddle, over how much of
    // the paddle is wet.
    final double w = body.angularVelocity;
    double torque = 0;
    for (var i = 0; i < paddles; i++) {
      final double a = body.angle + i * 2 * math.pi / paddles;
      final Vector2 dir = Vector2(math.cos(a), math.sin(a));
      final Vector2 tip = axle + dir * (radius + paddle);
      final Vector2 root = axle + dir * radius;
      final double surface = race.level;
      final double deepest = math.max(tip.y, root.y);
      if (deepest <= surface) continue;
      final double wet = (deepest - math.max(surface, math.min(tip.y, root.y)))
          .clamp(0.0, paddle);
      // The wet paddle's middle, from the axle, and how fast it moves
      // across the race (w × r); the water pushes it by how much faster it
      // runs, and that push turns the wheel (r × F).
      final Vector2 d = dir * (radius + paddle / 2);
      final double vx = -w * d.y;
      final double rel = race.current - vx;
      final double push = 380 * wet * rel * rel.abs();
      torque += -d.y * push;
    }
    body.applyTorque(torque);
  }

  @override
  void onRemove() {
    if (_ready && _pin.isValid) world.destroyBody(_pin);
    super.onRemove();
  }

  static final Paint _paint = Paint()..color = _wood;
  static final Paint _spoke = Paint()
    ..color = _wood
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.16;
  static final Paint _rim = Paint()
    ..color = _wood
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.22;
  static final Paint _metal = Paint()..color = _iron;

  @override
  void render(Canvas canvas) {
    final double r = radius + paddle;
    if (!isOnScreen(Rect.fromCircle(center: axle.toOffset(), radius: r))) {
      return;
    }
    canvas.drawCircle(Offset.zero, radius, _rim);
    canvas.drawCircle(Offset.zero, radius * 0.86, _rim..strokeWidth = 0.1);
    _rim.strokeWidth = 0.22;
    for (var i = 0; i < 6; i++) {
      final double a = i * math.pi / 6;
      canvas.drawLine(
        Offset(math.cos(a), math.sin(a)) * radius,
        Offset(math.cos(a), math.sin(a)) * -radius,
        _spoke,
      );
    }
    for (var i = 0; i < paddles; i++) {
      final double a = i * 2 * math.pi / paddles;
      canvas.save();
      canvas.rotate(a);
      canvas.drawRect(
        Rect.fromLTRB(radius - 0.05, -0.06, radius + paddle, 0.06),
        _paint,
      );
      canvas.drawRect(
        Rect.fromLTRB(radius + paddle - 0.08, -0.22, radius + paddle, 0.22),
        _paint,
      );
      canvas.restore();
    }
    canvas.drawCircle(Offset.zero, 0.35, _metal);
  }
}

/// A heavy gate in a slot, wound up on a rope round the mill's shaft:
/// every turn of the wheel lifts it [spool] metres a radian, up to [rise]
/// (a ratchet holds it there). Kinematic: nothing stops it but the stops.
class WinchGate extends BodyComponent with OffScreenCulling {
  WinchGate({
    required this.x,
    required this.floorY,
    required this.wheel,
    this.height = 2.8,
    this.rise = 2.3,
    this.spool = 0.3,
  }) : super(renderBody: false);

  final double x, floorY, height, rise, spool;
  final Waterwheel wheel;
  double _lift = 0;
  double _from = 0;
  bool _started = false;

  double get lift => _lift;
  bool get open => _lift > rise - 0.05;

  @override
  Body createBody() {
    final b = world.createBody(
      BodyDef(
        type: BodyType.kinematic,
        position: Vector2(x, floorY - height / 2),
        userData: this,
      ),
    );
    b.createShape(
      Polygon.box(0.14, height / 2),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.5),
      ),
    );
    return b;
  }

  /// Shut again, the rope run out.
  void reset() {
    _lift = 0;
    _from = wheel.turned;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dt <= 0) return;
    if (!_started) {
      _started = true;
      _from = wheel.turned;
    }
    // The wheel turns the shaft one way only through its ratchet.
    final double wound = (_from - wheel.turned).abs() * spool;
    final double goal = math.max(_lift, math.min(rise, wound));
    final double step = goal - _lift;
    _lift = goal;
    body.linearVelocity = Vector2(0, -step / dt);
  }

  static final Paint _bars = Paint()..color = _iron;

  @override
  void render(Canvas canvas) {
    final double hh = height / 2;
    final Vector2 c = body.position;
    if (!isOnScreen(Rect.fromLTRB(c.x - 1, c.y - hh - 1, c.x + 1, c.y + hh))) {
      return;
    }
    for (final dx in const [-0.42, -0.14, 0.14, 0.42]) {
      canvas.drawRect(Rect.fromLTRB(dx - 0.035, -hh, dx + 0.035, hh), _bars);
    }
    for (double y = -hh + 0.15; y < hh; y += 0.45) {
      canvas.drawRect(Rect.fromLTRB(-0.5, y, 0.5, y + 0.06), _bars);
    }
  }
}
