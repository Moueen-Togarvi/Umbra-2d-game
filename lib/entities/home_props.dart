import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';
import '../render/culling.dart';
import 'physics_props.dart';
import 'player.dart';

Filter _solidProp() => Filter(
  categoryBits: CollisionLayers.prop,
  maskBits:
      CollisionLayers.terrain |
      CollisionLayers.prop |
      CollisionLayers.ragdoll |
      CollisionLayers.player,
);

const Color _black = Color(0xFF050505);
const Color _crack = Color(0x26C8C8C8);

/// A farm cart: a plank bed on two spoked wheels, each on a real wheel
/// joint with a little suspension and a little drag in its axle. He grabs
/// and pushes it like a crate (it is one, to the hands), and it rolls.
class Cart extends PhysicsCrate {
  Cart({required double x, required double groundY, this.shafts = true})
    : super(
        position: Vector2(x, groundY - wheelRadius - _axleBelow),
        size: Vector2(1.5, 0.4),
        massKg: 22,
        friction: 0.6,
      );

  static const double wheelRadius = 0.3;

  /// The shafts a donkey was once harnessed to, resting on the ground.
  final bool shafts;

  /// How far below the bed's centre the axles sit.
  static const double _axleBelow = 0.17;
  static const double _axleX = 0.48;

  final List<Body> wheels = [];

  /// The bed's top, above the ground the cart stands on.
  static double get bedTop => wheelRadius + _axleBelow + 0.2;

  @override
  Body createBody() {
    final Body bed = super.createBody();
    for (final side in [-1.0, 1.0]) {
      final Vector2 at = bed.position + Vector2(side * _axleX, _axleBelow);
      final wheel = world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: at,
          angularDamping: 0.05,
          userData: this,
        ),
      );
      wheel.createShape(
        Circle(radius: wheelRadius),
        ShapeDef(
          density: 30,
          filter: _solidProp(),
          material: SurfaceMaterial(friction: 1.2, rollingResistance: 0.02),
        ),
      );
      world.physicsWorld.createWheelJoint(
        WheelJointDef(
          bodyA: bed,
          bodyB: wheel,
          localAnchorA: Vector2(side * _axleX, _axleBelow),
          localAxisA: Vector2(0, 1),
          hertz: 7,
          dampingRatio: 0.8,
          enableLimit: true,
          lowerTranslation: -0.04,
          upperTranslation: 0.04,
          // Drag in the axle: a push rolls it, and it soon stops.
          enableMotor: true,
          maxMotorTorque: 1.6,
          motorSpeed: 0,
        ),
      );
      wheels.add(wheel);
    }
    return bed;
  }

  /// The cart and its wheels back where they started, at rest.
  @override
  void resetToStart() {
    if (!isReady) return;
    super.resetToStart();
    for (var i = 0; i < wheels.length; i++) {
      final Body wheel = wheels[i];
      if (!wheel.isValid) continue;
      wheel
        ..setTransform(
          body.position + Vector2((i * 2 - 1) * _axleX, _axleBelow),
          Rot.fromAngle(0),
        )
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
    }
  }

  @override
  void onRemove() {
    for (final wheel in wheels) {
      if (wheel.isValid) world.destroyBody(wheel);
    }
    wheels.clear();
    super.onRemove();
  }

  static final Paint _wood = Paint()..color = _black;
  static final Paint _gap = Paint()..color = _crack;
  static final Paint _spoke = Paint()
    ..color = _black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.035
    ..strokeCap = StrokeCap.round;
  static final Paint _rim = Paint()
    ..color = _black
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.06;

  @override
  void render(Canvas canvas) {
    if (!isReady) return;
    final double hw = size.x / 2, hh = size.y / 2;
    // Shafts for a donkey that is long gone, resting on the ground.
    if (shafts) {
      canvas.drawPath(
        Path()
          ..moveTo(-hw + 0.05, hh * 0.2)
          ..lineTo(-hw - 0.95, hh + 0.42)
          ..lineTo(-hw - 0.93, hh + 0.47)
          ..lineTo(-hw + 0.05, hh * 0.55)
          ..close(),
        _wood,
      );
    }
    // The bed and its low side boards.
    canvas.drawRect(Rect.fromLTRB(-hw, -hh, hw, hh), _wood);
    for (final x in [-hw + 0.02, hw - 0.08]) {
      canvas.drawRect(Rect.fromLTRB(x, -hh - 0.22, x + 0.06, -hh), _wood);
    }
    canvas.drawRect(Rect.fromLTRB(-hw, -hh - 0.16, hw, -hh - 0.11), _wood);
    for (var i = 1; i < 3; i++) {
      final double y = -hh + i * size.y / 3;
      canvas.drawRect(Rect.fromLTRB(-hw + 0.06, y - 0.006, hw - 0.06, y), _gap);
    }
    // The wheels, from their own bodies.
    final double c = math.cos(-body.angle), s = math.sin(-body.angle);
    for (final wheel in wheels) {
      if (!wheel.isValid) continue;
      final Vector2 d = wheel.position - body.position;
      final Offset centre = Offset(d.x * c - d.y * s, d.x * s + d.y * c);
      canvas.drawCircle(centre, wheelRadius - 0.03, _rim);
      final double spin = wheel.angle - body.angle;
      for (var k = 0; k < 6; k++) {
        final double a = spin + k * math.pi / 3;
        canvas.drawLine(
          centre,
          centre + Offset(math.cos(a), math.sin(a)) * (wheelRadius - 0.04),
          _spoke,
        );
      }
      canvas.drawCircle(centre, 0.07, _wood);
    }
  }
}

/// A dry-stone wall: a static block drawn as rough courses of stone with
/// a ragged top, too high to jump and too high to catch from the ground.
class StoneWall extends BodyComponent with OffScreenCulling {
  StoneWall({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  }) : super(
         renderBody: false,
         bodyDef: BodyDef(
           type: BodyType.static,
           position: Vector2((left + right) / 2, (top + bottom) / 2),
         ),
       );

  final double left, right, top, bottom;
  late final Path _stones = _build();
  static final Paint _fill = Paint()..color = _black;
  static final Paint _joint = Paint()
    ..color = const Color(0x14C8C8C8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.012;

  @override
  Body createBody() {
    final Body b = super.createBody();
    b.userData = this;
    b.createShape(
      Polygon.box((right - left) / 2, (bottom - top) / 2, radius: 0.02),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.9),
        enableSensorEvents: true,
      ),
    );
    return b;
  }

  /// The joints between stones, body-local: courses of uneven height,
  /// stones of uneven length with slanted ends, each a rounded outline, so
  /// it reads as dry-stone and not as brick.
  Path _build() {
    final random = math.Random((left * 100).round());
    final double hw = (right - left) / 2, hh = (bottom - top) / 2;
    final path = Path();
    double y = -hh + 0.07;
    while (y < hh - 0.06) {
      final double h = 0.16 + random.nextDouble() * 0.2;
      final double yb = math.min(hh, y + h);
      double x = -hw + 0.03 - random.nextDouble() * 0.15;
      while (x < hw - 0.03) {
        final double w = 0.2 + random.nextDouble() * 0.38;
        final double l = math.max(-hw + 0.03, x);
        final double r = math.min(hw - 0.03, x + w);
        if (r - l > 0.08) {
          final double slant = (random.nextDouble() - 0.5) * 0.08;
          final double sag = (random.nextDouble() - 0.5) * 0.04;
          path.addRRect(
            RRect.fromLTRBR(
              l + 0.012 + slant.abs() * 0.3,
              y + 0.012 + sag.abs() * 0.4,
              r - 0.012,
              yb - 0.012,
              Radius.circular(0.035 + random.nextDouble() * 0.04),
            ),
          );
        }
        x += w;
      }
      y = yb;
    }
    return path;
  }

  /// Ivy on the top and grass at the foot, drawn over the stones.
  late final Path _growth = _buildGrowth();
  Path _buildGrowth() {
    final random = math.Random((right * 77).round());
    final double hw = (right - left) / 2, hh = (bottom - top) / 2;
    final path = Path();
    // Ivy hanging from the top over one face.
    for (var i = 0; i < 9; i++) {
      final double x = -hw + random.nextDouble() * (hw * 1.2);
      final double len = 0.2 + random.nextDouble() * 0.9;
      for (double v = 0; v < len; v += 0.07) {
        final double cx = x + math.sin(v * 9 + i) * 0.03;
        final double cy = -hh + v;
        path.addOval(
          Rect.fromCenter(
            center: Offset(cx + (random.nextDouble() - 0.5) * 0.05, cy),
            width: 0.07,
            height: 0.05,
          ),
        );
      }
    }
    // Tufts at the foot.
    for (double x = -hw - 0.1; x < hw + 0.1; x += 0.12) {
      final double h = 0.08 + random.nextDouble() * 0.16;
      path
        ..moveTo(x - 0.03, hh)
        ..lineTo(x + (random.nextDouble() - 0.5) * 0.08, hh - h)
        ..lineTo(x + 0.03, hh)
        ..close();
    }
    return path;
  }

  /// The wall's outline, body-local: rounded stones along the top and
  /// stones standing out of the sides, all inside the collision box so his
  /// feet meet what is drawn.
  late final Path _outline = _buildOutline();
  Path _buildOutline() {
    final random = math.Random((left * 31).round());
    final double hw = (right - left) / 2, hh = (bottom - top) / 2;
    final path = Path()..moveTo(-hw + 0.02, hh);
    // Up the left side, stones bulging out of it a little.
    for (
      double y = hh - 0.2;
      y > -hh + 0.2;
      y -= 0.22 + random.nextDouble() * 0.1
    ) {
      path.quadraticBezierTo(-hw - 0.01, y + 0.1, -hw + 0.03, y);
    }
    path.lineTo(-hw + 0.04, -hh + 0.12);
    // Capstones of different sizes, set on edge, the tallest at the top.
    double x = -hw + 0.04;
    while (x < hw - 0.06) {
      final double w = math.min(
        hw - 0.04 - x,
        0.14 + random.nextDouble() * 0.16,
      );
      final double dip = random.nextDouble() * 0.06;
      path
        ..lineTo(x, -hh + 0.1)
        ..cubicTo(x, -hh + dip, x + w, -hh + dip, x + w, -hh + 0.1);
      x += w;
    }
    path.lineTo(hw - 0.04, -hh + 0.12);
    for (
      double y = -hh + 0.25;
      y < hh - 0.1;
      y += 0.22 + random.nextDouble() * 0.1
    ) {
      path.quadraticBezierTo(hw + 0.01, y - 0.1, hw - 0.03, y);
    }
    path
      ..lineTo(hw - 0.02, hh)
      ..close();
    return path;
  }

  static final List<Paint> _behind = [
    for (var i = 1; i <= 4; i++)
      Paint()..color = Color.fromARGB(255, 8 + 14 * i, 8 + 13 * i, 8 + 12 * i),
  ];

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(Rect.fromLTRB(left - 1.5, top - 1, right, bottom))) {
      return;
    }
    // The wall runs away from us into the field: the further courses, a
    // step back and up each time, paler in the fog.
    for (var i = 4; i >= 1; i--) {
      canvas.save();
      canvas.translate(-0.3 * i, -0.18 * i);
      canvas.scale(math.pow(0.95, i).toDouble());
      canvas.drawPath(_outline, _behind[i - 1]);
      canvas.restore();
    }
    canvas.drawPath(_outline, _fill);
    canvas.drawPath(_stones, _joint);
    canvas.drawPath(_growth, _fill);
  }
}

/// A plank laid over a ditch on a post, free to tip: step on the raised
/// end and it comes down to the lip; walk past the middle and the far end
/// goes down to the other lip. A real body on a real hinge with limits.
class Seesaw extends BodyComponent with OffScreenCulling {
  Seesaw({
    required this.pivot,
    required this.length,
    required this.postBottom,
    this.tilt = 0.3,
    this.onTip,
  }) : super(renderBody: false);

  /// Called once, the first time it tips past the middle the other way
  /// (a lever worked by standing on it).
  final void Function()? onTip;
  bool tipped = false;

  final Vector2 pivot;
  final double length;

  /// Where the post stands, in the ditch.
  final double postBottom;

  /// How far it may tip either way, radians.
  final double tilt;

  late Body post;
  late RevoluteJoint hinge;
  bool _ready = false;
  static const double thickness = 0.13;

  @override
  Body createBody() {
    post = world.createBody(BodyDef(type: BodyType.static, position: pivot));
    final plank = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: pivot.clone(),
        // Resting on its far end.
        rotation: Rot.fromAngle(tilt),
        angularDamping: 0.6,
        userData: this,
      ),
    );
    plank.createShape(
      Polygon.box(length / 2, thickness / 2, radius: 0.015),
      ShapeDef(
        density: 14 / (length * thickness),
        filter: _solidProp(),
        material: SurfaceMaterial(friction: 0.95),
        enableSensorEvents: true,
      ),
    );
    hinge = world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: post,
        bodyB: plank,
        enableLimit: true,
        lowerAngle: -tilt,
        upperAngle: tilt,
        // A stiff old peg: it does not spin freely.
        enableMotor: true,
        maxMotorTorque: 6,
        motorSpeed: 0,
      ),
    );
    _ready = true;
    return plank;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!tipped && _ready && body.angle < -tilt * 0.6) {
      tipped = true;
      onTip?.call();
    }
  }

  @override
  void onRemove() {
    if (_ready && post.isValid) world.destroyBody(post);
    super.onRemove();
  }

  static final Paint _wood = Paint()..color = _black;
  static final Paint _grain = Paint()
    ..color = _crack
    ..strokeWidth = 0.008;

  @override
  void renderTree(Canvas canvas) {
    if (!_ready) return;
    if (!isOnScreen(
      Rect.fromCenter(
        center: Offset(pivot.x, pivot.y + 1),
        width: length + 1,
        height: 4,
      ),
    )) {
      return;
    }
    // The post, in world space: from the ditch floor up to the peg.
    canvas.drawPath(
      Path()
        ..moveTo(pivot.x - 0.11, postBottom)
        ..lineTo(pivot.x - 0.08, pivot.y + 0.05)
        ..lineTo(pivot.x + 0.08, pivot.y + 0.05)
        ..lineTo(pivot.x + 0.12, postBottom)
        ..close(),
      _wood,
    );
    super.renderTree(canvas);
  }

  @override
  void render(Canvas canvas) {
    final double hw = length / 2, hh = thickness / 2;
    canvas.drawPath(
      Path()
        ..moveTo(-hw, -hh + 0.01)
        ..lineTo(-hw * 0.4, -hh)
        ..lineTo(hw * 0.5, -hh + 0.008)
        ..lineTo(hw, -hh + 0.02)
        ..lineTo(hw - 0.03, hh)
        ..lineTo(-hw + 0.04, hh)
        ..close(),
      _wood,
    );
    canvas.drawLine(Offset(-hw * 0.8, 0), Offset(-hw * 0.1, 0.005), _grain);
    canvas.drawLine(Offset(hw * 0.2, -0.01), Offset(hw * 0.7, -0.008), _grain);
    canvas.drawCircle(Offset.zero, 0.035, _grain);
  }
}

/// A fence running away from the camera across his path: the nearest
/// post and rail are solid and must be hopped; the rest recede into the
/// fog behind it.
class LowFence extends BodyComponent with OffScreenCulling {
  LowFence({required this.x, required this.groundY, this.height = 0.72})
    : super(
        renderBody: false,
        bodyDef: BodyDef(
          type: BodyType.static,
          position: Vector2(x, groundY - height / 2),
        ),
      );

  final double x, groundY, height;
  static final Paint _paint = Paint();

  @override
  Body createBody() {
    final Body b = super.createBody();
    b.userData = this;
    b.createShape(
      Polygon.box(0.07, height / 2, radius: 0.02),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.8),
        enableSensorEvents: true,
      ),
    );
    return b;
  }

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(Rect.fromLTRB(x - 2, groundY - 2, x + 1, groundY + 1))) {
      return;
    }
    // Furthest first: each picket a step back and up into the fog.
    const int count = 7;
    final double hh = height / 2;
    for (var i = count - 1; i >= 0; i--) {
      final double k = math.pow(0.9, i).toDouble();
      final double dx = -0.2 * i, dy = -0.12 * i;
      final int fog = (i * 13).clamp(0, 90);
      _paint.color = Color.fromARGB(255, 5 + fog, 5 + fog, 5 + fog);
      final double w = 0.12 * k, h = height * k;
      final double lean = ((i * 7) % 5 - 2) * 0.012;
      canvas.drawPath(
        Path()
          ..moveTo(dx - w / 2, hh + dy)
          ..lineTo(dx - w / 2 + lean, hh + dy - h + w * 0.6)
          ..lineTo(dx + lean, hh + dy - h)
          ..lineTo(dx + w / 2 + lean, hh + dy - h + w * 0.6)
          ..lineTo(dx + w / 2, hh + dy)
          ..close(),
        _paint,
      );
      if (i > 0) {
        // Two rails back to the next picket.
        final double pdx = -0.2 * (i - 1), pdy = -0.12 * (i - 1);
        final double pk = math.pow(0.9, i - 1).toDouble();
        for (final f in [0.3, 0.72]) {
          canvas.drawPath(
            Path()
              ..moveTo(dx, hh + dy - h * f)
              ..lineTo(pdx, hh + pdy - height * pk * f)
              ..lineTo(pdx, hh + pdy - height * pk * f + 0.045 * pk)
              ..lineTo(dx, hh + dy - h * f + 0.045 * k)
              ..close(),
            _paint,
          );
        }
      }
    }
  }
}

/// Sheets drying on a line between two posts, just behind the path. Each
/// sheet is a small cloth (a grid of points joined by sticks, Verlet
/// integrated), pegged along its top. The evening breeze moves them, and
/// the air the boy pushes as he runs past billows them out.
class ClothLine extends Component with OffScreenCulling {
  ClothLine({
    required this.left,
    required this.right,
    required this.lineY,
    required this.groundY,
    required this.player,
    this.sheets = 3,
  }) : super(priority: -2);

  final double left, right, lineY, groundY;
  final Player player;
  final int sheets;
  final List<_Cloth> _cloths = [];
  double _time = 0;
  // A step behind the path, so a breath of fog lies over it and the boy
  // reads in front of the sheets.
  static final Paint _post = Paint()..color = const Color(0xFF1E1D1B);
  static final Paint _line = Paint()
    ..color = const Color(0xFF1E1D1B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.022;
  static final Paint _sheet = Paint()..color = const Color(0xFF2A2825);

  /// The line's sag at [x].
  double lineAt(double x) {
    final double t = (x - left) / (right - left);
    return lineY + 0.22 * 4 * t * (1 - t);
  }

  @override
  Future<void> onLoad() async {
    final double span = right - left;
    final double width = span / sheets * 0.78;
    for (var i = 0; i < sheets; i++) {
      final double cx = left + span * (i + 0.5) / sheets;
      final double drop = 0.95 + (i % 2) * 0.25;
      _cloths.add(_Cloth(cx - width / 2, cx + width / 2, drop, lineAt));
    }
  }

  @override
  void update(double dt) {
    _time += dt;
    // A slow breeze with gusts, and the boy's wake: air pushed ahead of
    // him and dragged behind, strongest close to him.
    final double breeze =
        0.35 +
        0.25 * math.sin(_time * 0.7) +
        0.3 * math.max(0, math.sin(_time * 0.23 + 1.3));
    final double px = player.body.position.x;
    final double vx = player.isMounted ? player.velocity.x : 0;
    for (final cloth in _cloths) {
      cloth.step(dt, breeze, px, vx, _time);
    }
  }

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(
      Rect.fromLTRB(left - 0.5, lineY - 0.5, right + 0.5, groundY),
    )) {
      return;
    }
    for (final x in [left, right]) {
      canvas.drawPath(
        Path()
          ..moveTo(x - 0.06, groundY + 0.1)
          ..lineTo(x - 0.045, lineY - 0.25)
          ..lineTo(x + 0.045, lineY - 0.27)
          ..lineTo(x + 0.06, groundY + 0.1)
          ..close(),
        _post,
      );
    }
    final line = Path()..moveTo(left, lineY);
    for (double x = left; x <= right; x += 0.2) {
      line.lineTo(x, lineAt(x));
    }
    line.lineTo(right, lineY);
    canvas.drawPath(line, _line);
    for (final cloth in _cloths) {
      canvas.drawPath(cloth.outline(), _sheet);
      canvas.drawPath(cloth.folds(), _fold);
    }
  }

  static final Paint _fold = Paint()
    ..color = const Color(0x22000000)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.018;
}

class _Cloth {
  _Cloth(this.left, this.right, this.drop, this.lineAt) {
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        final double x = left + (right - left) * c / (cols - 1);
        final p = Vector2(x, lineAt(x) + drop * r / (rows - 1));
        points.add(p);
        previous.add(p.clone());
      }
    }
    _dx = (right - left) / (cols - 1);
    _dy = drop / (rows - 1);
  }

  final double left, right, drop;
  final double Function(double) lineAt;
  static const int cols = 7, rows = 7;
  final List<Vector2> points = [];
  final List<Vector2> previous = [];
  late final double _dx, _dy;

  Vector2 _p(int r, int c) => points[r * cols + c];

  void step(double dt, double breeze, double px, double vx, double time) {
    if (dt <= 0) return;
    const double damping = 0.985;
    for (var i = cols; i < points.length; i++) {
      final p = points[i];
      final q = previous[i];
      final int r = i ~/ cols;
      final double depth = r / (rows - 1);
      // Wind pushes the lower cloth more; the boy's wake fades with
      // distance and lifts the hem as it passes.
      final double near = math.exp(-math.pow((p.x - px) / 0.9, 2).toDouble());
      final double wake = vx * near * 0.9;
      final double gust =
          breeze * (0.5 + 0.5 * math.sin(time * 1.9 + p.x * 1.7)) * depth;
      // Ripples running along the cloth.
      final double ripple = math.sin(time * 3.1 - p.x * 4.0 + r * 0.7) * 0.5;
      final double ax =
          gust * 2.6 + ripple * breeze * depth + wake * depth * 2.6;
      final double ay = 9.8 - (vx.abs() * near * depth * 3.2);
      final double nx = p.x + (p.x - q.x) * damping + ax * dt * dt;
      final double ny = p.y + (p.y - q.y) * damping + ay * dt * dt;
      q.setFrom(p);
      p.setValues(nx, ny);
    }
    // Pegged at the corners and the middle; between the pegs the top
    // edge hangs off the line in a shallow sag.
    for (final c in _pegs) {
      final double x = left + (right - left) * c / (cols - 1);
      _p(0, c).setValues(x, lineAt(x));
    }
    for (var k = 0; k < 5; k++) {
      for (var r = 0; r < rows; r++) {
        for (var c = 0; c < cols; c++) {
          final bool pinned = r == 0 && _pegs.contains(c);
          if (c + 1 < cols) {
            _stick(
              _p(r, c),
              _p(r, c + 1),
              // Slack along the top, so it sags between the pegs.
              r == 0 ? _dx * 1.07 : _dx,
              pinned,
              r == 0 && _pegs.contains(c + 1),
            );
          }
          if (r + 1 < rows) _stick(_p(r, c), _p(r + 1, c), _dy, pinned, false);
        }
      }
      // The free top edge cannot rise above the line it hangs on.
      for (var c = 0; c < cols; c++) {
        final p = _p(0, c);
        final double line = lineAt(p.x);
        if (p.y < line) p.y = line;
      }
    }
  }

  static const List<int> _pegs = [0, 3, 6];

  void _stick(Vector2 a, Vector2 b, double rest, bool pinnedA, bool pinnedB) {
    final double dx = b.x - a.x, dy = b.y - a.y;
    final double d = math.sqrt(dx * dx + dy * dy);
    if (d < 1e-6) return;
    // Cloth does not stretch, but it may bunch up.
    if (d < rest) return;
    final double f = (d - rest) / d;
    if (pinnedA && pinnedB) return;
    if (pinnedA) {
      b.x -= dx * f;
      b.y -= dy * f;
    } else if (pinnedB) {
      a.x += dx * f;
      a.y += dy * f;
    } else {
      a.x += dx * f * 0.5;
      a.y += dy * f * 0.5;
      b.x -= dx * f * 0.5;
      b.y -= dy * f * 0.5;
    }
  }

  /// Where the cloth hangs in folds: lines down the columns that the
  /// sides have pushed closer together.
  Path folds() {
    final path = Path();
    for (var c = 1; c < cols - 1; c++) {
      final double gap = (_p(rows - 1, c + 1).x - _p(rows - 1, c - 1).x).abs();
      if (gap > _dx * 1.7) continue;
      path.moveTo(_p(1, c).x, _p(1, c).y);
      for (var r = 2; r < rows; r++) {
        path.lineTo(_p(r, c).x, _p(r, c).y - 0.02);
      }
    }
    return path;
  }

  Path outline() {
    final path = Path()..moveTo(_p(0, 0).x, _p(0, 0).y);
    for (var c = 1; c < cols; c++) {
      path.lineTo(_p(0, c).x, _p(0, c).y);
    }
    for (var r = 1; r < rows; r++) {
      path.lineTo(_p(r, cols - 1).x, _p(r, cols - 1).y);
    }
    // A ragged hem.
    for (var c = cols - 2; c >= 0; c--) {
      final a = _p(rows - 1, c + 1), b = _p(rows - 1, c);
      path.quadraticBezierTo(
        (a.x + b.x) / 2,
        (a.y + b.y) / 2 + (c.isEven ? 0.07 : -0.02),
        b.x,
        b.y,
      );
    }
    for (var r = rows - 2; r > 0; r--) {
      path.lineTo(_p(r, 0).x, _p(r, 0).y);
    }
    return path..close();
  }
}
