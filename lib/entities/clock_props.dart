import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../physics/collision_layers.dart';
import '../render/culling.dart';
import '../world/stage.dart';
import 'player.dart';

const Color _iron = Color(0xFF050505);
const Color _sheen = Color(0x1CD8D0C0);

Filter _solid() => Filter(
  categoryBits: CollisionLayers.prop,
  maskBits:
      CollisionLayers.terrain |
      CollisionLayers.prop |
      CollisionLayers.ragdoll |
      CollisionLayers.player,
);

/// The great pendulum of the tower clock, built as a swing-boat: two
/// equal rods from twin pivots carry a heavy iron platform between their
/// feet. The four hinges make a parallelogram, so the platform swings
/// round its arc but always lies level, and he can ride it across a drop.
///
/// It swings freely under gravity; like a real clock's escapement, a small
/// kick as it passes the bottom of each swing keeps its arc at [amplitude]
/// (radians) against the friction in its pivots and his weight.
class Pendulum extends BodyComponent with OffScreenCulling {
  Pendulum({
    required this.pivot,
    required this.length,
    this.amplitude = 0.56,
    this.massKg = 260,
    this.plate = 1.6,
  }) : super(renderBody: false);

  /// Midway between the two pivots.
  final Vector2 pivot;
  final double length, amplitude, massKg;

  /// The platform's width; the rods are this far apart less a little.
  final double plate;
  double get _spread => plate - 0.3;

  late final Body _anchor;
  late final Body _rodA, _rodB;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;
  double _lastAngle = 0;

  /// The swing, radians from straight down (positive swung to the left
  /// on screen, as Box2D turns).
  double get swing => isReady ? _rodA.angle : 0;

  /// The top of the platform, world metres.
  Vector2 get plateTop => body.position - Vector2(0, 0.1);

  /// How high the platform rides at the ends of the swing, for laying the
  /// ledges level with it.
  static double plateTopAtEnd({
    required double pivotY,
    required double length,
    required double amplitude,
  }) => pivotY + length * math.cos(amplitude) - 0.1;

  Vector2 _at(double angle) =>
      Vector2(-math.sin(angle), math.cos(angle)) * length;

  @override
  Body createBody() {
    _anchor = world.createBody(BodyDef(position: pivot));
    final def = ShapeDef(
      density: 10,
      filter: _solid(),
      material: SurfaceMaterial(friction: 0.95),
      enableSensorEvents: true,
    );
    Body rod(double side) {
      final r = world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: pivot + Vector2(side * _spread / 2, 0),
          rotation: Rot.fromAngle(amplitude),
          angularDamping: 0.01,
          userData: this,
        ),
      );
      // A thin iron rod that touches nothing.
      r.createShape(
        Polygon.offsetBox(0.05, length / 2, center: Vector2(0, length / 2)),
        ShapeDef(
          density: 4,
          filter: Filter(categoryBits: CollisionLayers.prop, maskBits: 0),
        ),
      );
      world.physicsWorld.createRevoluteJoint(
        RevoluteJointDef(
          bodyA: _anchor,
          bodyB: r,
          localAnchorA: Vector2(side * _spread / 2, 0),
        ),
      );
      return r;
    }

    _rodA = rod(-1);
    _rodB = rod(1);
    final b = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: pivot + _at(amplitude),
        userData: this,
      ),
    );
    b.createShape(
      Polygon.offsetBox(plate / 2, 0.1, center: Vector2.zero()),
      def,
    );
    // The weight under the floor.
    b.createShape(
      Polygon([
        Vector2(-plate * 0.32, 0.1),
        Vector2(plate * 0.32, 0.1),
        Vector2(plate * 0.12, 0.55),
        Vector2(-plate * 0.12, 0.55),
      ]),
      def,
    );
    b.massData = MassData(
      mass: massKg,
      center: Vector2(0, 0.15),
      rotationalInertia: massKg * 0.3,
    );
    for (final (r, side) in [(_rodA, -1.0), (_rodB, 1.0)]) {
      world.physicsWorld.createRevoluteJoint(
        RevoluteJointDef(
          bodyA: r,
          bodyB: b,
          localAnchorA: Vector2(0, length),
          localAnchorB: Vector2(side * _spread / 2, 0),
        ),
      );
    }
    _ready = true;
    _lastAngle = amplitude;
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || dt <= 0) return;
    final double a = _rodA.angle;
    // Through the bottom: the escapement's kick, just enough to bring the
    // arc back to what it should be.
    if (a.sign != _lastAngle.sign && _lastAngle != 0) {
      final Vector2 v = body.linearVelocity;
      final double g = GameConfig.gravityMetersPerSecondSquared;
      final double want = math.sqrt(2 * g * length * (1 - math.cos(amplitude)));
      final double speed = v.length;
      if (speed > 1e-3) {
        final double change = (want - speed).clamp(-0.5, 0.5);
        body.linearVelocity = v * ((speed + change) / speed);
      }
    }
    _lastAngle = a;
  }

  /// Back to the end of its swing, at rest.
  void reset() {
    if (!isReady) return;
    for (final (r, side) in [(_rodA, -1.0), (_rodB, 1.0)]) {
      r
        ..setTransform(
          pivot + Vector2(side * _spread / 2, 0),
          Rot.fromAngle(amplitude),
        )
        ..angularVelocity = 0
        ..linearVelocity = Vector2.zero();
    }
    body
      ..setTransform(pivot + _at(amplitude), const Rot.identity())
      ..angularVelocity = 0
      ..linearVelocity = Vector2.zero();
    _lastAngle = amplitude;
  }

  @override
  void onRemove() {
    if (_ready) {
      for (final b in [_rodA, _rodB, _anchor]) {
        if (b.isValid) world.destroyBody(b);
      }
    }
    super.onRemove();
  }

  static final Paint _metal = Paint()..color = _iron;
  static final Paint _line = Paint()..color = _sheen;
  static final Paint _rod = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 0.1;

  @override
  void renderTree(Canvas canvas) {
    if (!isReady) return;
    if (!isOnScreen(
      Rect.fromLTRB(
        pivot.x - length - plate,
        pivot.y - 0.5,
        pivot.x + length + plate,
        pivot.y + length + 1,
      ),
    )) {
      return;
    }
    // The rods, from the pivots to the platform's ends.
    for (final (r, side) in [(_rodA, -1.0), (_rodB, 1.0)]) {
      final Vector2 top = r.position;
      final Vector2 foot = body.worldPoint(Vector2(side * _spread / 2, 0));
      canvas.drawLine(top.toOffset(), foot.toOffset(), _rod);
      canvas.drawCircle(top.toOffset(), 0.18, _metal);
    }
    super.renderTree(canvas);
  }

  @override
  void render(Canvas canvas) {
    // The platform, a lens of iron under it, a brass line along its edge.
    canvas.drawRect(Rect.fromLTRB(-plate / 2, -0.1, plate / 2, 0.1), _metal);
    canvas.drawPath(
      Path()
        ..moveTo(-plate * 0.4, 0.08)
        ..quadraticBezierTo(0, 0.85, plate * 0.4, 0.08)
        ..close(),
      _metal,
    );
    canvas.drawRect(Rect.fromLTRB(-plate / 2, -0.1, plate / 2, -0.088), _line);
  }
}

/// A great gear of the clockwork, turned by the weight-driven train: a
/// dynamic wheel of teeth on an axle, driven by a motor of limited torque.
/// Jam something hard between its teeth and the stone and it stops; so
/// does everything it drives ([Gear.speed] reads its real turning).
class Gear extends BodyComponent with OffScreenCulling {
  Gear({
    required this.centre,
    required this.radius,
    this.teeth = 14,
    this.speed = 1.2,
    this.torque = 300,
  }) : super(renderBody: false);

  final Vector2 centre;
  final double radius;
  final int teeth;

  /// The speed it is driven at (rad/s) and the most torque it has.
  final double speed, torque;

  late final Body _axle;
  late final RevoluteJoint _drive;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;

  /// How fast it really turns, rad/s.
  double get turning => isReady ? body.angularVelocity : 0;

  /// Whether it has been stopped by something in its teeth.
  bool get jammed => isReady && turning.abs() < speed * 0.15;

  static const double tooth = 0.28;

  @override
  Body createBody() {
    _axle = world.createBody(BodyDef(position: centre));
    final b = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: centre.clone(),
        angularDamping: 0.1,
        userData: this,
        isBullet: true,
      ),
    );
    final def = ShapeDef(
      density: 30,
      filter: _solid(),
      material: SurfaceMaterial(friction: 1.0),
    );
    b.createShape(Circle(radius: radius), def);
    for (var i = 0; i < teeth; i++) {
      final double a = i * 2 * math.pi / teeth;
      final Vector2 at =
          Vector2(math.cos(a), math.sin(a)) * (radius + tooth / 2 - 0.02);
      b.createShape(
        Polygon.offsetBox(tooth / 2, 0.11, center: at, rotation: a),
        def,
      );
    }
    _drive = world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: _axle,
        bodyB: b,
        enableMotor: true,
        motorSpeed: speed,
        maxMotorTorque: torque,
      ),
    );
    _ready = true;
    return b;
  }

  /// Turning freely again, nothing in its teeth.
  void free() {
    if (!isReady) return;
    _drive.motorSpeed = speed;
    body.isAwake = true;
  }

  @override
  void onRemove() {
    if (_ready && _axle.isValid) world.destroyBody(_axle);
    super.onRemove();
  }

  static final Paint _metal = Paint()..color = _iron;
  static final Paint _hole = Paint()..color = const Color(0x22D8D0C0);

  @override
  void render(Canvas canvas) {
    final double r = radius + tooth;
    if (!isOnScreen(Rect.fromCircle(center: centre.toOffset(), radius: r))) {
      return;
    }
    final path = Path()
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: radius));
    for (var i = 0; i < teeth; i++) {
      final double a = i * 2 * math.pi / teeth;
      final double w = 0.11 / radius;
      path.addPolygon([
        Offset(math.cos(a - w * 1.4), math.sin(a - w * 1.4)) * (radius - 0.02),
        Offset(math.cos(a - w), math.sin(a - w)) * (radius + tooth),
        Offset(math.cos(a + w), math.sin(a + w)) * (radius + tooth),
        Offset(math.cos(a + w * 1.4), math.sin(a + w * 1.4)) * (radius - 0.02),
      ], true);
    }
    canvas.drawPath(path, _metal);
    // Spokes seen through the rim, and the hub.
    final rim = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: Offset.zero, radius: radius * 0.78));
    for (var i = 0; i < 5; i++) {
      final double a = i * 2 * math.pi / 5;
      final double b = a + 2 * math.pi / 5;
      rim.addPolygon([
        Offset(math.cos(a + 0.18), math.sin(a + 0.18)) * radius * 0.3,
        Offset(math.cos(a + 0.12), math.sin(a + 0.12)) * radius * 0.72,
        Offset(math.cos(b - 0.12), math.sin(b - 0.12)) * radius * 0.72,
        Offset(math.cos(b - 0.18), math.sin(b - 0.18)) * radius * 0.3,
      ], true);
    }
    canvas.drawPath(rim, _hole);
    canvas.drawCircle(Offset.zero, radius * 0.14, _hole);
  }
}

/// A hammer of the striking train, on an arm round an axle, driven by a
/// [Gear]: it turns only as fast as the gear turns. Whatever is in its way
/// as it comes round, it kills.
class StrikingHammer extends Component with OffScreenCulling {
  StrikingHammer({
    required this.axle,
    required this.arm,
    required this.gear,
    this.ratio = 1.6,
    this.arms = 3,
    super.priority = 1,
  });

  /// How many arms, each with its head, evenly round the axle.
  final int arms;

  final Vector2 axle;
  final double arm;
  final Gear gear;

  /// Turns of the hammer for each turn of the gear.
  final double ratio;

  /// The arm's angle, radians from pointing straight down.
  double angle = math.pi;
  Stage? _stage;

  Vector2 get head => headAt(0);

  /// The [i]th head, world metres.
  Vector2 headAt(int i) {
    final double a = angle + i * 2 * math.pi / arms;
    return axle + Vector2(-math.sin(a), math.cos(a)) * arm;
  }

  @override
  Future<void> onLoad() async {
    _stage = ancestors().whereType<Stage>().firstOrNull;
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    final double w = gear.turning * ratio;
    angle = (angle + w * dt) % (2 * math.pi);
    final Player? boy = _stage?.player;
    if (boy == null || !boy.isMounted || boy.isDead || w.abs() < 0.3) return;
    final Vector2 p = boy.body.position;
    for (var i = 0; i < arms; i++) {
      final Vector2 h = headAt(i);
      if ((h.x - p.x).abs() < 0.7 &&
          (h.y - p.y).abs() < GameConfig.playerHeight / 2 + 0.3) {
        boy.die();
        return;
      }
    }
  }

  static final Paint _metal = Paint()..color = _iron;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(
      Rect.fromCircle(center: axle.toOffset(), radius: arm + 1),
    )) {
      return;
    }
    canvas.save();
    canvas.translate(axle.x, axle.y);
    for (var i = 0; i < arms; i++) {
      canvas.save();
      canvas.rotate(angle + i * 2 * math.pi / arms);
      canvas.drawRect(Rect.fromLTRB(-0.07, 0, 0.07, arm), _metal);
      // The head: a heavy iron block, wider across the swing.
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(0, arm), width: 1.0, height: 0.55),
          const Radius.circular(0.08),
        ),
        _metal,
      );
      canvas.restore();
    }
    canvas.restore();
    canvas.drawCircle(axle.toOffset(), 0.3, _metal);
  }
}

/// The minute hand of the great clock, seen from inside: a long iron bar
/// round the clock's arbor that moves in jumps, as a turret clock does,
/// [step] radians every [interval] seconds. It is solid, so he can stand
/// on it; level, it bridges the drop beside the clock.
class ClockHand extends BodyComponent with OffScreenCulling {
  ClockHand({
    required this.hub,
    required this.length,
    this.startAngle = 0,
    this.step = math.pi / 6,
    this.interval = 2.2,
    this.jump = 0.35,
  }) : super(renderBody: false);

  final Vector2 hub;
  final double length;

  /// Where it points at first, radians, 0 pointing right, turning
  /// clockwise on screen.
  final double startAngle;
  final double step, interval, jump;

  double _clock = 0;
  double _goal = 0;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;

  /// Where it points now, radians (0 right, clockwise on screen).
  double get pointing => isReady ? body.angle : startAngle;

  /// Whether it lies level, pointing either way.
  bool get level {
    final double a = (pointing % math.pi + math.pi) % math.pi;
    return a < 0.02 || a > math.pi - 0.02;
  }

  /// Seconds until it next moves.
  double get untilNext => interval - _clock;

  @override
  Body createBody() {
    _goal = startAngle;
    final b = world.createBody(
      BodyDef(
        type: BodyType.kinematic,
        position: hub.clone(),
        rotation: Rot.fromAngle(startAngle),
        userData: this,
      ),
    );
    b.createShape(
      Polygon.offsetBox(length / 2, 0.11, center: Vector2(length / 2 - 0.3, 0)),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.95),
        enableSensorEvents: true,
      ),
    );
    _ready = true;
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || dt <= 0) return;
    _clock += dt;
    if (_clock >= interval) {
      _clock -= interval;
      _goal += step;
    }
    // (Box2D reports the angle within a half turn either way.)
    double left = (_goal - body.angle) % (2 * math.pi);
    if (left > math.pi) left -= 2 * math.pi;
    if (left.abs() < 1e-4) {
      body.angularVelocity = 0;
      if (left != 0) body.setTransform(hub, Rot.fromAngle(_goal));
      _goal = _goal % (2 * math.pi);
    } else {
      body.angularVelocity = (left / dt).clamp(-step / jump, step / jump);
    }
  }

  /// As it was at the start.
  void reset() {
    if (!isReady) return;
    _clock = 0;
    _goal = startAngle;
    body
      ..setTransform(hub, Rot.fromAngle(startAngle))
      ..angularVelocity = 0;
  }

  static final Paint _metal = Paint()..color = _iron;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(
      Rect.fromCircle(center: hub.toOffset(), radius: length + 0.5),
    )) {
      return;
    }
    // A long tapering bar with a pierced spade near its tip, and its
    // short counterweighted tail.
    canvas.drawPath(
      Path()
        ..moveTo(-0.9, -0.1)
        ..lineTo(length - 1.0, -0.11)
        ..lineTo(length - 0.75, -0.3)
        ..lineTo(length - 0.3, 0)
        ..lineTo(length - 0.75, 0.3)
        ..lineTo(length - 1.0, 0.11)
        ..lineTo(-0.9, 0.11)
        ..close(),
      _metal,
    );
    canvas.drawCircle(const Offset(-0.9, 0), 0.26, _metal);
    canvas.drawCircle(Offset.zero, 0.34, _metal);
  }
}
