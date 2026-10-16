import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';
import '../render/culling.dart';
import 'player.dart';

const Color _rock = Color(0xFF050505);
const Color _iron = Color(0xFF060606);

Filter _propFilter() => Filter(
  categoryBits: CollisionLayers.prop,
  maskBits:
      CollisionLayers.terrain |
      CollisionLayers.prop |
      CollisionLayers.ragdoll |
      CollisionLayers.player,
);

/// A mass of cave rock: a closed outline that is solid all round (a chain
/// loop), drawn with a roughened edge and with stalactites hanging from
/// every face that looks down.
class RockMass extends BodyComponent with OffScreenCulling {
  RockMass(List<Vector2> outline, {this.drips = true, this.seed = 0})
    : points = _clockwise(outline),
      super(
        renderBody: false,
        bodyDef: BodyDef(type: BodyType.static, position: Vector2.zero()),
      ) {
    bodyDef!.userData = this;
  }

  /// The outline, clockwise on screen (y down) so the chain faces out.
  final List<Vector2> points;
  final bool drips;
  final int seed;

  static List<Vector2> _clockwise(List<Vector2> p) {
    double area = 0;
    for (var i = 0; i < p.length; i++) {
      final a = p[i], b = p[(i + 1) % p.length];
      area += a.x * b.y - b.x * a.y;
    }
    // With y down, a positive shoelace sum is clockwise on screen.
    return area >= 0 ? p : p.reversed.toList();
  }

  late final Rect bounds = () {
    double l = double.infinity, t = double.infinity;
    double r = -double.infinity, b = -double.infinity;
    for (final p in points) {
      l = math.min(l, p.x);
      t = math.min(t, p.y);
      r = math.max(r, p.x);
      b = math.max(b, p.y);
    }
    return Rect.fromLTRB(l, t - 0.1, r, b + 1.2);
  }();

  @override
  Body createBody() {
    final Body b = super.createBody();
    b.createChain(
      ChainDef(
        points: [for (final p in points) p.clone()],
        isLoop: true,
        filter: Filter(categoryBits: CollisionLayers.terrain),
        materials: [SurfaceMaterial(friction: 0.9)],
        enableSensorEvents: true,
        userData: this,
      ),
    );
    return b;
  }

  late final Path _path = _build();

  Path _build() {
    final random = math.Random(seed * 31 + points.length);
    final path = Path();
    var first = true;
    for (var i = 0; i < points.length; i++) {
      final a = points[i], b = points[(i + 1) % points.length];
      final Vector2 d = b - a;
      final double len = d.length;
      final int steps = math.max(1, (len / 0.18).round());
      // Outward normal of a clockwise outline (y down).
      final Vector2 n = Vector2(d.y, -d.x)..normalize();
      for (var s = 0; s < steps; s++) {
        final double t = s / steps;
        // A few centimetres of crumbling edge, never inside the collision.
        final double rough = -random.nextDouble() * 0.05;
        final Vector2 p = a + d * t + n * rough;
        if (first) {
          path.moveTo(p.x, p.y);
          first = false;
        } else {
          path.lineTo(p.x, p.y);
        }
      }
      // Faces that look down grow stalactites.
      if (drips && n.y > 0.6 && len > 0.6) {
        for (
          double u = 0.2 + random.nextDouble() * 0.4;
          u < len - 0.2;
          u += 0.35 + random.nextDouble() * 0.9
        ) {
          final Vector2 base = a + d * (u / len);
          final double h = 0.12 + math.pow(random.nextDouble(), 2) * 0.7;
          final double w = 0.06 + h * 0.18;
          path
            ..lineTo(base.x - w, base.y)
            ..quadraticBezierTo(
              base.x - w * 0.3,
              base.y + h * 0.5,
              base.x + (random.nextDouble() - 0.5) * 0.04,
              base.y + h,
            )
            ..quadraticBezierTo(
              base.x + w * 0.3,
              base.y + h * 0.5,
              base.x + w,
              base.y,
            );
        }
      }
    }
    return path..close();
  }

  static final Paint _paint = Paint()..color = _rock;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(bounds)) return;
    canvas.drawPath(_path, _paint);
  }
}

/// An iron cage hanging from the cave roof on a chain of real links (small
/// bodies joined by hinges), so it swings like a pendulum and twists a
/// little at the top.
///
/// The boy's feet push on its floor as hard as it pushes him, so running
/// back and forth inside it, in time, swings it higher and higher. If
/// [breakSpeed] is set, a blow against the rock at least that fast snaps
/// the rusted latch, and the door, hinged at its foot, falls open outwards
/// like a drawbridge.
class HangingCage extends Component with OffScreenCulling {
  HangingCage({
    required this.anchor,
    required this.chainLength,
    this.width = 1.6,
    this.height = 1.9,
    this.breakSpeed,
    this.child = false,
    this.links = 8,
  });

  final Vector2 anchor;
  final double chainLength, width, height;
  final double? breakSpeed;
  final bool child;
  final int links;

  late Body body;
  Body? door;
  RevoluteJoint? _latch;
  final List<Body> chain = [];
  late Body _fixed;
  bool _built = false;

  /// Whether the door has burst open.
  bool get isOpen => _latch == null && door != null;

  /// The fastest blow it has taken.
  double hardestHit = 0;

  static const double bar = 0.05;

  double get _hw => width / 2;
  double get _hh => height / 2;

  /// Where the cage hangs at rest: its centre.
  Vector2 get restCentre => anchor + Vector2(0, chainLength + _hh);

  @override
  Future<void> onLoad() async {
    final world = (findGame()! as Forge2DGame).world;
    final w = world.physicsWorld;
    _fixed = w.createBody(BodyDef(type: BodyType.static, position: anchor));
    Body previous = _fixed;
    final double link = chainLength / links;
    for (var i = 0; i < links; i++) {
      final Vector2 at = anchor + Vector2(0, link * (i + 0.5));
      final b = w.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: at,
          angularDamping: 0.6,
          linearDamping: 0.05,
        ),
      );
      b.createShape(
        Polygon.box(0.03, link / 2),
        ShapeDef(
          density: 40,
          // The chain passes through everything; only its ends matter.
          filter: Filter(categoryBits: CollisionLayers.prop, maskBits: 0),
        ),
      );
      w.createRevoluteJoint(
        RevoluteJointDef(
          bodyA: previous,
          bodyB: b,
          localAnchorA: i == 0 ? Vector2.zero() : Vector2(0, link / 2),
          localAnchorB: Vector2(0, -link / 2),
        ),
      );
      chain.add(b);
      previous = b;
    }
    final Vector2 centre = restCentre;
    body = w.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: centre,
        angularDamping: 0.5,
        linearDamping: 0.02,
        userData: this,
        isBullet: true,
      ),
    );
    ShapeDef part(double density) => ShapeDef(
      density: density,
      filter: _propFilter(),
      material: SurfaceMaterial(friction: 0.9),
      enableHitEvents: true,
      enableSensorEvents: true,
    );
    // Floor, roof and the barred back wall are one body; the barred front
    // wall too unless it is a door.
    body
      ..createShape(
        Polygon.offsetBox(_hw, 0.05, center: Vector2(0, _hh - 0.05)),
        part(60),
      )
      ..createShape(
        Polygon.offsetBox(_hw, 0.05, center: Vector2(0, -_hh + 0.05)),
        part(40),
      )
      ..createShape(
        Polygon.offsetBox(bar, _hh, center: Vector2(-_hw + bar, 0)),
        part(40),
      );
    if (breakSpeed == null) {
      body.createShape(
        Polygon.offsetBox(bar, _hh, center: Vector2(_hw - bar, 0)),
        part(40),
      );
    }
    w.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: previous,
        bodyB: body,
        localAnchorA: Vector2(0, link / 2),
        localAnchorB: Vector2(0, -_hh),
      ),
    );
    if (breakSpeed != null) {
      // The door, hinged at its foot, latched at its head.
      final d = door = w.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: centre + Vector2(_hw - bar, 0),
          angularDamping: 0.4,
          userData: this,
        ),
      );
      d.createShape(Polygon.box(bar, _hh - 0.06), part(45));
      w.createRevoluteJoint(
        RevoluteJointDef(
          bodyA: body,
          bodyB: d,
          localAnchorA: Vector2(_hw - bar, _hh - 0.06),
          localAnchorB: Vector2(0, _hh - 0.06),
          enableLimit: true,
          lowerAngle: 0,
          upperAngle: 1.62,
        ),
      );
      _latch = w.createRevoluteJoint(
        RevoluteJointDef(
          bodyA: body,
          bodyB: d,
          localAnchorA: Vector2(_hw - bar, -_hh + 0.06),
          localAnchorB: Vector2(0, -_hh + 0.06),
        ),
      );
    }
    _built = true;
  }

  @override
  void update(double dt) {
    if (!_built || !body.isValid) return;
    final double? limit = breakSpeed;
    final w = body.world;
    for (final hit in w.contactEvents.hit) {
      if (!hit.shapeA.isValid || !hit.shapeB.isValid) continue;
      final Body a = hit.shapeA.body, b = hit.shapeB.body;
      final bool mine = a == body || b == body || a == door || b == door;
      if (!mine) continue;
      final Body other = (a == body || a == door) ? b : a;
      // Only blows against rock count, not the boy inside.
      if (other.userData is Player || other == body || other == door) continue;
      hardestHit = math.max(hardestHit, hit.approachSpeed);
      if (limit != null && _latch != null && hit.approachSpeed >= limit) {
        _latch!.destroy();
        _latch = null;
        // The latch gives with a jolt that starts the door falling.
        door?.applyAngularImpulse(door!.mass * 0.15);
      }
    }
  }

  @override
  void onRemove() {
    if (_built) {
      for (final b in [...chain, body, ?door, _fixed]) {
        if (b.isValid) b.destroy();
      }
    }
    super.onRemove();
  }

  static final Paint _bars = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.035;
  static final Paint _solid = Paint()..color = _iron;
  static final Paint _kid = Paint()..color = const Color(0xFF0A0A0A);

  @override
  void render(Canvas canvas) {
    if (!_built || !body.isValid) return;
    final Vector2 c = body.position;
    if (!isOnScreen(
      Rect.fromLTRB(
        math.min(anchor.x, c.x) - 2,
        anchor.y,
        math.max(anchor.x, c.x) + 2,
        c.y + _hh + 0.5,
      ),
    )) {
      return;
    }
    // The chain: oval links, alternately seen face on and edge on.
    Vector2 from = anchor;
    for (var i = 0; i < chain.length; i++) {
      final Vector2 to = i + 1 < chain.length
          ? (chain[i].position + chain[i + 1].position) / 2
          : body.worldPoint(Vector2(0, -_hh));
      final Vector2 mid = (from + to) / 2;
      final double len = (to - from).length;
      final double a = math.atan2(to.y - from.y, to.x - from.x);
      canvas.save();
      canvas.translate(mid.x, mid.y);
      canvas.rotate(a);
      if (i.isEven) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: len + 0.04,
              height: 0.09,
            ),
            const Radius.circular(0.045),
          ),
          _bars..strokeWidth = 0.022,
        );
      } else {
        canvas.drawRect(
          Rect.fromCenter(
            center: Offset.zero,
            width: len + 0.04,
            height: 0.025,
          ),
          _solid,
        );
      }
      canvas.restore();
      from = to;
    }
    _bars.strokeWidth = 0.035;
    canvas.save();
    canvas.translate(c.x, c.y);
    canvas.rotate(body.angle);
    // A domed top with a ring, the floor plate, and the bars.
    canvas.drawPath(
      Path()
        ..moveTo(-_hw, -_hh + 0.1)
        ..quadraticBezierTo(0, -_hh - 0.35, _hw, -_hh + 0.1)
        ..close(),
      _solid,
    );
    canvas.drawRect(Rect.fromLTRB(-_hw, _hh - 0.1, _hw, _hh), _solid);
    canvas.drawRect(Rect.fromLTRB(-_hw, -_hh + 0.04, _hw, -_hh + 0.12), _solid);
    canvas.drawRect(
      Rect.fromLTRB(-_hw - 0.03, -0.06, _hw + 0.03, -0.01),
      _solid,
    );
    final int count = (width / 0.17).round();
    for (var i = 0; i <= count; i++) {
      final double x = -_hw + bar + (width - bar * 2) * i / count;
      if (door != null && i == count) continue;
      canvas.drawLine(Offset(x, -_hh + 0.1), Offset(x, _hh - 0.1), _bars);
    }
    if (child) _curledChild(canvas);
    canvas.restore();
    final Body? d = door;
    if (d != null && d.isValid) {
      canvas.save();
      canvas.translate(d.position.x, d.position.y);
      canvas.rotate(d.angle);
      canvas.drawRect(
        Rect.fromLTRB(-bar, -_hh + 0.06, bar, _hh - 0.06),
        _solid,
      );
      for (final y in [-_hh * 0.5, 0.0, _hh * 0.5]) {
        canvas.drawRect(Rect.fromLTRB(-0.08, y - 0.02, 0.02, y + 0.02), _solid);
      }
      canvas.restore();
    }
  }

  /// A small child curled up on the cage floor, knees drawn in.
  void _curledChild(Canvas canvas) {
    final double f = _hh - 0.1;
    canvas.drawPath(
      Path()
        ..moveTo(-0.45, f)
        ..quadraticBezierTo(-0.5, f - 0.42, -0.22, f - 0.5)
        ..quadraticBezierTo(0.05, f - 0.52, 0.12, f - 0.3)
        ..lineTo(0.3, f - 0.22)
        ..quadraticBezierTo(0.36, f - 0.08, 0.28, f)
        ..close(),
      _kid,
    );
    canvas.drawCircle(Offset(-0.32, f - 0.6), 0.12, _kid);
  }
}

/// A cage on the winch chain above a pit: when the winch is let go it is
/// lowered, swinging very slightly, until its roof is level with the lips
/// and it makes a bridge.
class WinchCage extends BodyComponent with OffScreenCulling {
  WinchCage({
    required this.anchor,
    required this.startTop,
    required this.endTop,
    this.width = 2.1,
    this.height = 1.8,
  }) : super(renderBody: false);

  final Vector2 anchor;
  final double startTop, endTop, width, height;
  bool lowering = false;
  bool get isDown => _top >= endTop - 0.005;
  double _top = 0;
  double _speed = 0;

  @override
  Body createBody() {
    _top = startTop;
    final b = world.createBody(
      BodyDef(
        type: BodyType.kinematic,
        position: Vector2(anchor.x, startTop + height / 2),
        userData: this,
      ),
    );
    b.createShape(
      Polygon.box(width / 2, height / 2, radius: 0.02),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.9),
        enableSensorEvents: true,
      ),
    );
    return b;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (dt <= 0) return;
    // The winch drum unwinds: quick at first, braking at the end.
    final double left = endTop - _top;
    final double target = lowering && left > 0
        ? math.min(1.4, math.max(0.15, left * 1.2))
        : 0;
    _speed += (target - _speed) * math.min(1, dt * 4);
    final double move = math.min(left, _speed * dt);
    _top += move;
    body.linearVelocity = Vector2(0, dt > 0 ? move / dt : 0);
  }

  static final Paint _bars = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.04;
  static final Paint _solid = Paint()..color = _iron;

  @override
  void render(Canvas canvas) {
    final double hw = width / 2, hh = height / 2;
    if (!isOnScreen(
      Rect.fromLTRB(
        anchor.x - hw,
        anchor.y,
        anchor.x + hw,
        body.position.y + hh,
      ),
    )) {
      return;
    }
    // Two chains up to the winch beam.
    for (final x in [-hw + 0.15, hw - 0.15]) {
      canvas.drawLine(
        Offset(x, -hh),
        Offset(x * 0.4, anchor.y - body.position.y),
        _bars..strokeWidth = 0.03,
      );
    }
    _bars.strokeWidth = 0.04;
    canvas.drawRect(Rect.fromLTRB(-hw, -hh, hw, -hh + 0.1), _solid);
    canvas.drawRect(Rect.fromLTRB(-hw, hh - 0.1, hw, hh), _solid);
    final int count = (width / 0.18).round();
    for (var i = 0; i <= count; i++) {
      final double x = -hw + 0.03 + (width - 0.06) * i / count;
      canvas.drawLine(Offset(x, -hh + 0.1), Offset(x, hh - 0.1), _bars);
    }
  }
}

/// A foot pedal for the winch: an iron-shod beam hinged at its far end on
/// the floor, its near end held up by a spring. His weight anywhere on it
/// presses it flat, and that lets the winch go.
class FootPedal extends BodyComponent with OffScreenCulling {
  FootPedal({
    required this.hinge,
    required this.onPress,
    this.length = 1.5,
    this.raised = 0.36,
  }) : super(renderBody: false);

  /// The hinge on the floor, at the beam's right end.
  final Vector2 hinge;
  final double length;

  /// The angle it rests at, near end up, radians.
  final double raised;
  final void Function() onPress;
  bool pressed = false;
  late Body _base;
  bool _ready = false;

  @override
  Body createBody() {
    _base = world.createBody(BodyDef(type: BodyType.static, position: hinge));
    final double c = math.cos(raised), s = math.sin(raised);
    final beam = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: hinge + Vector2(-length / 2 * c, -length / 2 * s),
        rotation: Rot.fromAngle(raised),
        angularDamping: 2,
        userData: this,
      ),
    );
    beam.createShape(
      Polygon.box(length / 2, 0.06, radius: 0.015),
      ShapeDef(
        density: 8 / (length * 0.12),
        filter: _propFilter(),
        material: SurfaceMaterial(friction: 0.95),
        enableSensorEvents: true,
      ),
    );
    world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: _base,
        bodyB: beam,
        localAnchorB: Vector2(length / 2, 0),
        referenceAngle: 0,
        enableLimit: true,
        lowerAngle: 0,
        upperAngle: raised,
        enableSpring: true,
        targetAngle: raised,
        hertz: 1.6,
        dampingRatio: 0.8,
      ),
    );
    _ready = true;
    return beam;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!pressed && _ready && body.angle < raised * 0.25) {
      pressed = true;
      onPress();
    }
  }

  @override
  void onRemove() {
    if (_ready && _base.isValid) world.destroyBody(_base);
    super.onRemove();
  }

  static final Paint _paint = Paint()..color = _iron;
  static final Paint _chain = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.025;

  @override
  void renderTree(Canvas canvas) {
    if (!_ready) return;
    if (!isOnScreen(
      Rect.fromLTRB(
        hinge.x - length - 1,
        hinge.y - 8,
        hinge.x + 1,
        hinge.y + 0.5,
      ),
    )) {
      return;
    }
    // A chain from the near end up into the dark, to the winch's brake.
    final Vector2 end = body.worldPoint(Vector2(-length / 2 + 0.08, 0));
    canvas.drawLine(end.toOffset(), Offset(end.x + 0.3, hinge.y - 7), _chain);
    canvas.drawCircle(hinge.toOffset(), 0.12, _paint);
    super.renderTree(canvas);
  }

  @override
  void render(Canvas canvas) {
    final double hw = length / 2;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-hw, -0.06, hw, 0.06),
        const Radius.circular(0.02),
      ),
      _paint,
    );
    // Iron straps.
    for (final x in [-hw + 0.12, 0.0, hw - 0.12]) {
      canvas.drawRect(
        Rect.fromLTRB(x - 0.025, -0.075, x + 0.025, 0.075),
        _paint,
      );
    }
  }
}
