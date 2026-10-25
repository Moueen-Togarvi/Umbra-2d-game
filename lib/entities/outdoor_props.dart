import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../physics/collision_layers.dart';
import '../render/culling.dart';
import '../render/light.dart';
import '../world/stage.dart';
import 'castle_props.dart';
import 'player.dart';

const Color _wood = Color(0xFF070605);
const Color _iron = Color(0xFF050505);

/// A drawbridge: a long heavy deck hinged at the near edge of the moat,
/// standing up and held by its chain. Let the chain go ([lower]) and it
/// falls across, turning on its hinge, and lands on the far side; there it
/// lies and is wedged.
class Drawbridge extends BodyComponent with OffScreenCulling {
  Drawbridge({
    required this.hinge,
    required this.length,
    this.massKg = 180,
    this.thickness = 0.3,
  }) : super(renderBody: false);

  /// The hinge, at the deck's top surface on the near side.
  final Vector2 hinge;
  final double length, massKg, thickness;

  late final Body _post;
  DistanceJoint? _chain;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;
  bool wedged = false;
  double _still = 0;
  double _turning = 0;

  bool get lowered => _chain == null;

  /// Down across the moat.
  bool get down => wedged || (isReady && body.angle.abs() < 0.05);

  @override
  Body createBody() {
    _post = world.createBody(BodyDef(position: hinge));
    // Standing up: its far end straight above the hinge.
    final b = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: hinge.clone(),
        rotation: Rot.fromAngle(-math.pi / 2),
        angularDamping: 0.2,
        userData: this,
      ),
    );
    b.createShape(
      Polygon.offsetBox(
        length / 2,
        thickness / 2,
        center: Vector2(length / 2, thickness / 2),
      ),
      ShapeDef(
        density: 10,
        filter: CollisionLayers.propFilter(),
        material: SurfaceMaterial(friction: 0.95),
        enableHitEvents: true,
      ),
    );
    b.massData = MassData(
      mass: massKg,
      center: Vector2(length / 2, thickness / 2),
      rotationalInertia: massKg * length * length / 12,
    );
    world.physicsWorld.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: _post,
        bodyB: b,
        enableLimit: true,
        lowerAngle: -math.pi / 2,
        upperAngle: 0,
      ),
    );
    // The chain from its far end back to the gatehouse wall.
    _chain = world.physicsWorld.createDistanceJoint(
      DistanceJointDef(
        bodyA: _post,
        bodyB: b,
        localAnchorA: Vector2(-0.8, -length),
        localAnchorB: Vector2(length, 0),
        length: 0.8,
        enableLimit: true,
        minLength: 0,
        maxLength: 0.8,
      ),
    );
    _ready = true;
    return b;
  }

  /// Lets the chain run.
  void lower() {
    final c = _chain;
    if (c == null) return;
    if (c.isValid) c.destroy();
    _chain = null;
    body.isAwake = true;
    cue('chain', at: hinge);
    cue('creak', weight: 0.8, at: hinge);
    // A nudge off the vertical, as the chain gives.
    body.angularVelocity = 0.3;
  }

  /// Raised again on its chain.
  void raise() {
    if (!isReady) return;
    if (wedged) {
      wedged = false;
      body.type = BodyType.dynamic;
    }
    _still = 0;
    body
      ..setTransform(hinge, Rot.fromAngle(-math.pi / 2))
      ..angularVelocity = 0
      ..linearVelocity = Vector2.zero();
    _chain ??= world.physicsWorld.createDistanceJoint(
      DistanceJointDef(
        bodyA: _post,
        bodyB: body,
        localAnchorA: Vector2(-0.8, -length),
        localAnchorB: Vector2(length, 0),
        length: 0.8,
        enableLimit: true,
        minLength: 0,
        maxLength: 0.8,
      ),
    );
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || wedged || !lowered) return;
    final double w = body.angularVelocity.abs();
    if (_turning > 1.0 && w < 0.4) {
      cue('wood', at: body.worldPoint(Vector2(length / 2, 0)), shake: 0.6);
      cue('gate', weight: 0.5, at: body.worldPoint(Vector2(length, 0)));
    }
    _turning = w;
    final bool flat = body.angle.abs() < 0.06;
    _still = flat && body.angularVelocity.abs() < 0.05 ? _still + dt : 0;
    if (_still > 0.25) {
      wedged = true;
      body.type = BodyType.static;
    }
  }

  @override
  void onRemove() {
    if (_ready && _post.isValid) world.destroyBody(_post);
    super.onRemove();
  }

  static final Paint _deck = Paint()..color = _wood;
  static final Paint _grain = Paint()..color = const Color(0x1AD8D0C0);
  static final Paint _chainPaint = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05;

  @override
  void renderTree(Canvas canvas) {
    if (!isReady) return;
    if (!lowered) {
      final Vector2 end = body.worldPoint(Vector2(length, 0));
      canvas.drawLine(
        end.toOffset(),
        (hinge + Vector2(-0.8, -length)).toOffset(),
        _chainPaint,
      );
    }
    super.renderTree(canvas);
  }

  @override
  void render(Canvas canvas) {
    canvas.drawRect(Rect.fromLTRB(0, 0, length, thickness), _deck);
    for (double x = 0.45; x < length; x += 0.45) {
      canvas.drawRect(Rect.fromLTRB(x, 0.02, x + 0.012, thickness), _grain);
    }
    // Iron bands across it.
    for (final t in const [0.2, 0.55, 0.9]) {
      canvas.drawRect(
        Rect.fromLTRB(
          length * t - 0.05,
          -0.03,
          length * t + 0.05,
          thickness + 0.03,
        ),
        _deck,
      );
    }
  }
}

/// An iron fire basket on a tall stand: a steady pool of firelight.
class Brazier extends Component with StageLight implements GlowingLight {
  Brazier({
    required this.x,
    required this.floorY,
    this.radius = 2.6,
    super.priority = 1,
  });

  final double x, floorY, radius;
  double _time = 0;
  bool lit = true;

  Offset get _bowl => Offset(x, floorY - 1.5);

  @override
  bool lights(Vector2 p) =>
      lit &&
      (p.x - x).abs() < radius &&
      p.y > floorY - 3.5 &&
      p.y < floorY + 0.3;

  @override
  void update(double dt) => _time += dt;

  @override
  void paintLight(Canvas canvas) {
    if (!lit) return;
    final double f = Glow.flicker(_time, (x * 3).round());
    Glow.round(canvas, _bowl, radius * 1.5, Palette.lampAmber, 0.45 + 0.05 * f);
  }

  static final Paint _metal = Paint()..color = _iron;

  @override
  void render(Canvas canvas) {
    canvas.drawRect(
      Rect.fromLTRB(x - 0.05, floorY - 1.45, x + 0.05, floorY),
      _metal,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x - 0.4, floorY)
        ..lineTo(x, floorY - 0.3)
        ..lineTo(x + 0.4, floorY)
        ..close(),
      _metal,
    );
    canvas.drawPath(
      Path()
        ..moveTo(x - 0.38, floorY - 1.7)
        ..lineTo(x + 0.38, floorY - 1.7)
        ..lineTo(x + 0.22, floorY - 1.42)
        ..lineTo(x - 0.22, floorY - 1.42)
        ..close(),
      _metal,
    );
    if (!lit) return;
    for (var i = 0; i < 5; i++) {
      Glow.flame(
        canvas,
        Offset(x - 0.24 + i * 0.12, floorY - 1.68),
        0.28 + 0.1 * math.sin(i * 1.7),
        Palette.lampAmber,
        Glow.flicker(_time, i + (x * 3).round()),
      );
    }
  }
}

/// A bridge of planks on ropes over a chasm: each plank a body, hinged to
/// the next, the ends tied to posts; it sags, sways in the wind and bucks
/// under him. [snap] cuts it loose at the far post: it falls.
class RopeBridge extends Component with OffScreenCulling {
  RopeBridge({
    required this.from,
    required this.to,
    this.planks = 14,
    this.sag = 0.06,
  });

  /// The deck's ends at the two posts.
  final Vector2 from, to;
  final int planks;

  /// How much longer than the span the planks run, as a fraction.
  final double sag;

  final List<Body> boards = [];
  final List<Joint> _joints = [];
  late Body _a, _b;
  Joint? _far;
  bool _built = false;
  bool snapped = false;

  double get _plank => (to - from).length * (1 + sag) / planks;

  @override
  Future<void> onLoad() async => _build();

  /// Whole again, hanging as it was built (after a death on it).
  void reset() {
    if (!_built) return;
    _destroy();
    _joints.clear();
    boards.clear();
    _far = null;
    snapped = false;
    _build();
  }

  void _destroy() {
    for (final b in [...boards, _a, _b]) {
      if (b.isValid) b.destroy();
    }
  }

  void _build() {
    final world = (findGame()! as Forge2DGame).world.physicsWorld;
    _a = world.createBody(BodyDef(position: from));
    _b = world.createBody(BodyDef(position: to));
    final Vector2 along = (to - from)..normalize();
    final double span = (to - from).length;
    Body previous = _a;
    for (var i = 0; i < planks; i++) {
      // Laid along a gentle curve, near where they will hang.
      final double t = (i + 0.5) / planks;
      final Vector2 at =
          from +
          along * (span * t) +
          Vector2(0, math.sin(t * math.pi) * span * sag * 1.2);
      final b = world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: at,
          angularDamping: 0.8,
          linearDamping: 0.1,
          userData: this,
        ),
      );
      b.createShape(
        Polygon.box(_plank / 2 - 0.01, 0.06),
        ShapeDef(
          density: 30,
          filter: CollisionLayers.propFilter(),
          material: SurfaceMaterial(friction: 0.95),
        ),
      );
      _joints.add(
        world.createRevoluteJoint(
          RevoluteJointDef(
            bodyA: previous,
            bodyB: b,
            localAnchorA: i == 0 ? Vector2.zero() : Vector2(_plank / 2, 0),
            localAnchorB: Vector2(-_plank / 2, 0),
          ),
        ),
      );
      boards.add(b);
      previous = b;
    }
    _far = world.createRevoluteJoint(
      RevoluteJointDef(
        bodyA: previous,
        bodyB: _b,
        localAnchorA: Vector2(_plank / 2, 0),
      ),
    );
    _built = true;
  }

  /// Cut loose at the far post, and broken in the middle.
  void snap() {
    if (snapped || !_built) return;
    snapped = true;
    cue('wood', at: to, shake: 0.5);
    cue('creak', at: (from + to) / 2);
    final Joint? far = _far;
    if (far != null && far.isValid) far.destroy();
    _far = null;
    final Joint mid = _joints[planks ~/ 2];
    if (mid.isValid) mid.destroy();
  }

  @override
  void onRemove() {
    if (_built) _destroy();
    super.onRemove();
  }

  static final Paint _deck = Paint()..color = _wood;
  static final Paint _rope = Paint()
    ..color = const Color(0xFF141414)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.035;

  @override
  void render(Canvas canvas) {
    if (!_built) return;
    if (!isOnScreen(
      Rect.fromLTRB(
        from.x - 1,
        math.min(from.y, to.y) - 2,
        to.x + 1,
        from.y + 6,
      ),
    )) {
      return;
    }
    // The posts.
    for (final p in [from, to]) {
      canvas.drawRect(
        Rect.fromLTRB(p.x - 0.1, p.y - 1.2, p.x + 0.1, p.y + 0.3),
        _deck,
      );
    }
    // The planks, and the hand ropes sagging from post to post through
    // their ends.
    final hand = Path()..moveTo(from.x, from.y - 1.0);
    for (final b in boards) {
      canvas.save();
      canvas.translate(b.position.x, b.position.y);
      canvas.rotate(b.angle);
      canvas.drawRect(
        Rect.fromLTRB(-_plank / 2, -0.06, _plank / 2, 0.06),
        _deck,
      );
      canvas.restore();
      if (!snapped) hand.lineTo(b.position.x, b.position.y - 0.9);
      canvas.drawLine(
        b.position.toOffset(),
        Offset(b.position.x, b.position.y - 0.9),
        _rope..strokeWidth = 0.02,
      );
    }
    _rope.strokeWidth = 0.035;
    if (!snapped) {
      hand.lineTo(to.x, to.y - 1.0);
      canvas.drawPath(hand, _rope);
    }
  }
}

/// Rocks breaking loose from a cliff above the path and bounding down it,
/// one every [every] seconds, a handful kept and thrown again. A rock
/// coming fast kills him.
class RockFall extends Component {
  RockFall({
    required this.from,
    this.every = 3.2,
    this.count = 4,
    this.radius = 0.38,
    this.firstAfter = 1.0,
    this.speed = 2.5,
    this.rounding = 0,
    this.deadly = 2.5,
  });

  /// How fast a stone must be coming to kill him, metres a second.
  final double deadly;

  /// How round its corners are, metres: rounded stones roll on down a
  /// gentle slope where sharp ones would stop.
  final double rounding;

  /// How fast each is thrown off the cliff, metres a second leftwards.
  final double speed;

  final Vector2 from;
  final double every, radius, firstAfter;
  final int count;

  final List<Body> rocks = [];
  final List<double> _spin = [];
  double _clock = 0;
  int _next = 0;
  bool active = false;
  bool _built = false;
  Stage? _stage;

  static const double _parkY = -80;

  @override
  Future<void> onLoad() async {
    _stage = ancestors().whereType<Stage>().firstOrNull;
    final world = (findGame()! as Forge2DGame).world.physicsWorld;
    final random = math.Random(5);
    for (var i = 0; i < count; i++) {
      final b = world.createBody(
        BodyDef(
          type: BodyType.dynamic,
          position: Vector2(from.x + i * 3, _parkY),
          angularDamping: 0.1,
          isBullet: true,
          isEnabled: false,
        ),
      );
      // A lumpy stone: seven points round a circle.
      final pts = [
        for (var k = 0; k < 7; k++)
          Vector2(
                math.cos(k * 2 * math.pi / 7),
                math.sin(k * 2 * math.pi / 7),
              ) *
              (radius * (0.8 + random.nextDouble() * 0.3)),
      ];
      b.createShape(
        rounding > 0
            ? Polygon([
                for (final p in pts)
                  p.normalized() * math.max(0.05, p.length - rounding),
              ], radius: rounding)
            : Polygon(pts),
        ShapeDef(
          density: 260,
          filter: CollisionLayers.propFilter(),
          material: SurfaceMaterial(friction: 0.7, restitution: 0.2),
        ),
      );
      rocks.add(b);
      _spin.add(random.nextDouble() * 2 - 1);
    }
    _clock = every - firstAfter;
    _built = true;
  }

  /// Stopped, its stones gathered up, the first to come [firstAfter]
  /// seconds after it is next set going.
  void reset() {
    stop();
    _clock = every - firstAfter;
  }

  void stop() {
    active = false;
    for (final r in rocks) {
      r
        ..setTransform(Vector2(r.position.x, _parkY), const Rot.identity())
        ..isEnabled = false;
    }
  }

  @override
  void update(double dt) {
    if (!_built || dt <= 0) return;
    if (active) {
      _clock += dt;
      if (_clock >= every) {
        _clock -= every;
        final r = rocks[_next];
        _next = (_next + 1) % rocks.length;
        cue('rumble', weight: 0.8, at: from);
        r
          ..isEnabled = true
          ..setTransform(from, Rot.fromAngle(_spin[_next]))
          ..linearVelocity = Vector2(-speed, 0)
          ..angularVelocity = -6;
      }
    }
    final Player? boy = _stage?.player;
    if (boy == null || !boy.isMounted || boy.isDead) return;
    final Vector2 p = boy.body.position;
    for (final r in rocks) {
      if (!r.isEnabled) continue;
      if (r.linearVelocity.length > deadly &&
          (r.position - p).length < radius + GameConfig.playerHeight * 0.45) {
        boy.die(
          push: r.linearVelocity * 0.7 + Vector2(0, -1.5),
          cause: DeathCause.crushing,
        );
        return;
      }
    }
  }

  @override
  void onRemove() {
    if (_built) {
      for (final r in rocks) {
        if (r.isValid) r.destroy();
      }
    }
    super.onRemove();
  }

  static final Paint _stone = Paint()..color = const Color(0xFF060606);

  @override
  void render(Canvas canvas) {
    for (final r in rocks) {
      if (!r.isEnabled) continue;
      final shape = r.shapes.first;
      final g = shape.geometry;
      if (g is! Polygon || g.points == null) continue;
      final path = Path();
      final pts = g.points!;
      for (var k = 0; k < pts.length; k++) {
        final Vector2 w = r.worldPoint(pts[k]);
        if (k == 0) {
          path.moveTo(w.x, w.y);
        } else {
          path.lineTo(w.x, w.y);
        }
      }
      canvas.drawPath(path..close(), _stone);
      if (g.radius > 0) {
        canvas.drawPath(
          path,
          Paint()
            ..color = _stone.color
            ..style = PaintingStyle.stroke
            ..strokeJoin = StrokeJoin.round
            ..strokeWidth = g.radius * 2,
        );
      }
    }
  }
}
