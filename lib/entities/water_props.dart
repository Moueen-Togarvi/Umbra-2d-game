import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';
import '../physics/water.dart';
import 'physics_props.dart';

const Color _wood = Color(0xFF060504);
const Color _grain = Color(0x1FD8D0C0);

/// A length of fallen tree, light enough to float. On land it is pushed
/// like a crate; in water it rides high, takes his weight, and rolls a
/// little when he lands on one end.
class FloatingLog extends PhysicsCrate {
  FloatingLog({
    required super.position,
    double length = 2.6,
    double diameter = 0.46,
    super.massKg = 14,
  }) : super(size: Vector2(length, diameter), friction: 0.8);

  static final Paint _bark = Paint()..color = _wood;
  static final Paint _line = Paint()
    ..color = _grain
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.012;

  @override
  void render(Canvas canvas) {
    final double hw = size.x / 2, hh = size.y / 2;
    // A trunk, a little thicker at the root end, with sawn ends.
    canvas.drawPath(
      Path()
        ..moveTo(-hw + 0.04, -hh)
        ..quadraticBezierTo(0, -hh - 0.015, hw - 0.04, -hh + 0.03)
        ..quadraticBezierTo(hw + 0.02, 0, hw - 0.04, hh - 0.01)
        ..quadraticBezierTo(0, hh + 0.01, -hw + 0.04, hh)
        ..quadraticBezierTo(-hw - 0.03, 0, -hw + 0.04, -hh)
        ..close(),
      _bark,
    );
    // Bark furrows along it, a knot, and the rings of the cut end.
    for (final y in [-hh * 0.45, hh * 0.05, hh * 0.5]) {
      canvas.drawLine(
        Offset(-hw * 0.8, y),
        Offset(hw * (0.2 + (y + hh) * 0.6), y + 0.01),
        _line,
      );
    }
    canvas.drawCircle(Offset(hw * 0.35, -hh * 0.2), 0.03, _line);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(hw - 0.05, 0),
        width: 0.07,
        height: hh * 1.4,
      ),
      _line,
    );
    // A broken branch stub.
    canvas.drawPath(
      Path()
        ..moveTo(-hw * 0.3, -hh + 0.02)
        ..lineTo(-hw * 0.38, -hh - 0.14)
        ..lineTo(-hw * 0.3, -hh - 0.12)
        ..lineTo(-hw * 0.22, -hh + 0.02)
        ..close(),
      _bark,
    );
  }
}

/// An old wooden coffin. Pushed like a crate on stone; in the water it
/// floats low, and sinks under him if he stands on it too long.
class Coffin extends PhysicsCrate {
  Coffin({required super.position, super.massKg = 40, this.chainedTo})
    : super(size: Vector2(2.0, 0.62), friction: 0.5);

  /// Where a chain from its foot is fixed in the floor, if it is chained:
  /// it may float up as far as the chain lets it, but not drift away.
  final Vector2? chainedTo;
  Body? _ring;
  double _chainLength = 0;

  @override
  Body createBody() {
    final Body coffin = super.createBody();
    final Vector2? anchor = chainedTo;
    if (anchor != null) {
      final ring = _ring = world.createBody(
        BodyDef(type: BodyType.static, position: anchor.clone()),
      );
      _chainLength = (coffin.position - anchor).length;
      world.physicsWorld.createDistanceJoint(
        DistanceJointDef(
          bodyA: ring,
          bodyB: coffin,
          localAnchorB: Vector2(0, size.y / 2),
          length: _chainLength,
          enableSpring: true,
          hertz: 0,
          enableLimit: true,
          minLength: 0,
          maxLength: _chainLength,
        ),
      );
    }
    return coffin;
  }

  @override
  void onRemove() {
    final ring = _ring;
    if (ring != null && ring.isValid) world.destroyBody(ring);
    super.onRemove();
  }

  static final Paint _chain = Paint()
    ..color = _wood
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.025;

  @override
  void renderTree(Canvas canvas) {
    final Vector2? anchor = chainedTo;
    if (anchor != null && isReady) {
      // The chain hangs slack from the coffin to its ring in the floor.
      final Vector2 foot = body.worldPoint(Vector2(0, size.y / 2));
      final double span = (foot - anchor).length;
      final double slack = math.max(0, _chainLength - span) * 0.5;
      final path = Path()..moveTo(foot.x, foot.y);
      path.quadraticBezierTo(
        (foot.x + anchor.x) / 2 + slack,
        (foot.y + anchor.y) / 2,
        anchor.x,
        anchor.y,
      );
      canvas.drawPath(path, _chain);
    }
    super.renderTree(canvas);
  }

  static final Paint _paint = Paint()..color = _wood;
  static final Paint _seam = Paint()
    ..color = _grain
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.012;
  // The wet lid catching what light there is, so it reads in the dark.
  static final Paint _wet = Paint()
    ..color = const Color(0x52D8D0C0)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeWidth = 0.022;

  @override
  void render(Canvas canvas) {
    final double hw = size.x / 2, hh = size.y / 2;
    // The body narrowing towards the foot, and the lid's raised ridge.
    canvas.drawPath(
      Path()
        ..moveTo(-hw, -hh + 0.08)
        ..lineTo(-hw * 0.35, -hh)
        ..lineTo(hw, -hh + 0.06)
        ..lineTo(hw, hh - 0.04)
        ..lineTo(-hw * 0.35, hh)
        ..lineTo(-hw, hh - 0.06)
        ..close(),
      _paint,
    );
    canvas.drawPath(
      Path()
        ..moveTo(-hw + 0.03, -hh + 0.09)
        ..lineTo(-hw * 0.35, -hh + 0.01)
        ..lineTo(hw - 0.03, -hh + 0.07),
      _wet,
    );
    canvas.drawLine(
      Offset(-hw + 0.04, -hh + 0.16),
      Offset(hw - 0.04, -hh + 0.15),
      _seam,
    );
    for (final x in [-hw * 0.55, 0.0, hw * 0.55]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, hh * 0.25),
            width: 0.14,
            height: 0.06,
          ),
          const Radius.circular(0.03),
        ),
        _seam,
      );
    }
  }
}

/// Where an underground river comes out of the rock: every [every] seconds
/// it lets go a floating log at [at], which the current carries down. Logs
/// that reach [sink] are swallowed by it.
///
/// The logs are made once, with the chapter, and parked out of the world
/// when not in use: letting one go moves it to the source, and the sink
/// parks it again. Nothing is created while he plays.
class LogSource extends Component {
  LogSource({
    required this.at,
    required this.sink,
    this.every = 5.5,
    this.firstAfter = 0.5,
    int most = 4,
  }) : logs = [
         // Thick trunks: with him aboard one still rides a hand above the
         // water (24 kg + 40 kg on 2.1 m² of 60 kg/m² water).
         for (var i = 0; i < most; i++)
           FloatingLog(
             position: Vector2(at.x + i * 3.5, _parkY),
             length: 3.0,
             diameter: 0.7,
             massKg: 24,
           ),
       ];

  static const double _parkY = -60;
  final Vector2 at;
  final double sink;
  final double every;
  final double firstAfter;

  /// Every log this source uses: add them to the chapter with it.
  final List<FloatingLog> logs;
  final Set<FloatingLog> _out = {};
  double _clock = 0;
  int released = 0;

  /// The logs in the river now.
  Iterable<FloatingLog> get afloat =>
      _out.where((l) => l.isReady && l.body.isEnabled && l.body.position.y > 0);

  @override
  void onMount() {
    super.onMount();
    _clock = every - firstAfter;
  }

  void _park(FloatingLog log, int i) {
    log.body
      ..setTransform(Vector2(at.x + i * 3.5, _parkY), Rot.fromAngle(0))
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0
      ..isEnabled = false;
  }

  /// Logs parked this frame: Box2D settles a body's changes at the end
  /// of the step, so one is not sent out again until the next.
  final Set<FloatingLog> _justParked = {};

  @override
  void update(double dt) {
    _justParked.clear();
    for (var i = 0; i < logs.length; i++) {
      final log = logs[i];
      if (!log.isReady) continue;
      if (!_out.contains(log) && log.body.isEnabled) {
        _park(log, i);
        _justParked.add(log);
      }
      if (_out.contains(log) && log.body.position.x > sink) {
        _out.remove(log);
        _park(log, i);
        _justParked.add(log);
      }
    }
    _clock += dt;
    if (_clock < every) return;
    for (final log in logs) {
      if (!log.isReady || _out.contains(log) || _justParked.contains(log)) {
        continue;
      }
      _clock = 0;
      log.body
        ..isEnabled = true
        ..setTransform(at.clone(), Rot.fromAngle(0))
        ..linearVelocity = Vector2.zero()
        ..angularVelocity = 0;
      _out.add(log);
      released++;
      break;
    }
  }
}

/// A sluice between two pools: shut, they keep their levels; open, water
/// runs from the higher to the lower until they are level, the volume
/// that leaves one arriving in the other.
class Sluice extends Component {
  Sluice({required this.from, required this.into, this.flow = 0.9});

  final WaterBody from, into;

  /// How fast it runs, square metres a second per metre of difference.
  final double flow;
  bool open = false;

  @override
  void update(double dt) {
    if (!open || dt <= 0) return;
    // Surfaces in y-down: the higher water has the smaller y.
    final double head = into.level - from.level;
    if (head.abs() < 0.002) return;
    final double widthFrom = from.right - from.left;
    final double widthInto = into.right - into.left;
    final double moved = flow * head * dt;
    from.setLevel(from.level + moved / widthFrom);
    into.setLevel(into.level - moved / widthInto);
  }
}

/// How far a log of [diameter] floating in water of [density] at its own
/// [massKg] over [length] sits under the surface (for laying levels out).
double floatDepth(
  double massKg,
  double length,
  double diameter,
  double density,
) {
  final double fraction = (massKg / (length * diameter)) / density;
  return diameter * math.min(1, fraction);
}

/// An old barrel lying on its side in the water, seen along its length:
/// bulging staves between iron hoops. It floats high, dips and tips under
/// him, and bumps against its neighbours.
class Barrel extends BodyComponent {
  Barrel({
    required this.at,
    this.length = 1.5,
    this.thickness = 0.9,
    this.massKg = 14,
  }) : super(renderBody: false);

  final Vector2 at;
  final double length, thickness;
  final double massKg;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;

  @override
  Body createBody() {
    final b = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: at.clone(),
        angularDamping: 0.4,
        userData: this,
      ),
    );
    const double round = 0.16;
    b.createShape(
      Polygon.box(length / 2 - round, thickness / 2 - round, radius: round),
      ShapeDef(
        density: massKg / (length * thickness),
        filter: Filter(
          categoryBits: CollisionLayers.prop,
          maskBits:
              CollisionLayers.terrain |
              CollisionLayers.prop |
              CollisionLayers.ragdoll |
              CollisionLayers.player,
        ),
        material: SurfaceMaterial(friction: 0.9),
        enableSensorEvents: true,
      ),
    );
    _ready = true;
    return b;
  }

  /// Back where it began, at rest.
  void resetToStart() {
    if (!isReady) return;
    body
      ..setTransform(at.clone(), Rot.fromAngle(0))
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;
  }

  static final Paint _staves = Paint()..color = const Color(0xFF070605);
  static final Paint _hoop = Paint()
    ..color = const Color(0x2ED8D0C0)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.028;

  @override
  void render(Canvas canvas) {
    final double hw = length / 2, hh = thickness / 2;
    // The belly bulges between the heads.
    canvas.drawPath(
      Path()
        ..moveTo(-hw, -hh * 0.82)
        ..quadraticBezierTo(0, -hh * 1.12, hw, -hh * 0.82)
        ..lineTo(hw, hh * 0.82)
        ..quadraticBezierTo(0, hh * 1.12, -hw, hh * 0.82)
        ..close(),
      _staves,
    );
    for (final x in [-hw * 0.78, -hw * 0.3, hw * 0.3, hw * 0.78]) {
      final double bulge = 1 + 0.12 * (1 - (x / hw) * (x / hw));
      canvas.drawLine(
        Offset(x, -hh * 0.86 * bulge),
        Offset(x, hh * 0.86 * bulge),
        _hoop,
      );
    }
    canvas.drawLine(
      Offset(-hw * 0.7, -hh * 0.35),
      Offset(hw * 0.7, -hh * 0.38),
      _hoop..strokeWidth = 0.012,
    );
    _hoop.strokeWidth = 0.028;
  }
}
