import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';

Filter _propFilter({bool collideWithPlayer = true}) => Filter(
  categoryBits: CollisionLayers.prop,
  maskBits:
      CollisionLayers.terrain |
      CollisionLayers.prop |
      CollisionLayers.ragdoll |
      (collideWithPlayer ? CollisionLayers.player : 0),
);

/// A real dynamic crate; density, mass and floor friction determine resistance.
class PhysicsCrate extends BodyComponent {
  PhysicsCrate({
    required Vector2 position,
    required Vector2 size,
    required this.massKg,
    this.friction = 0.25,
  }) : _initialPosition = position.clone(),
       size = size.clone(),
       super(renderBody: false);

  final Vector2 _initialPosition;
  final Vector2 size;

  /// Puts it back where it started, at rest (after a death undid his work).
  void resetToStart() {
    if (!isReady) return;
    body
      ..setTransform(_initialPosition.clone(), Rot.fromAngle(0))
      ..linearVelocity = Vector2.zero()
      ..angularVelocity = 0;
  }

  final double massKg;
  final double friction;
  bool _created = false;
  bool get isReady => _created && body.isValid;

  @override
  Body createBody() {
    final result = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: _initialPosition,
        // Crates can tip: pushed off an edge they tumble, and they settle
        // on uneven ground. A steady push at mid-height cannot topple one
        // on the flat: friction times the push height stays below half its
        // width times its weight.
        angularDamping: 0.4,
        linearDamping: 0.12,
        userData: this,
        isBullet: true,
      ),
    );
    const corner = 0.025;
    final area = size.x * size.y - (4 - math.pi) * corner * corner;
    result.createShape(
      Polygon.box(size.x / 2 - corner, size.y / 2 - corner, radius: corner),
      ShapeDef(
        density: massKg / area,
        filter: _propFilter(),
        material: SurfaceMaterial(friction: friction, restitution: 0),
        enableContactEvents: true,
        enableSensorEvents: true,
      ),
    );
    // Native rounded-polygon integration approximates the corner area. Keep
    // the chosen kilogram mass exact while preserving its computed inertia.
    result.massData = MassData(
      mass: massKg,
      center: result.localCenterOfMass,
      rotationalInertia: result.rotationalInertia * massKg / result.mass,
    );
    _created = true;
    return result;
  }

  static final Paint _wood = Paint()..color = const Color(0xFF0A0A0A);
  static final Paint _gap = Paint()..color = const Color(0x2EBDBDBD);
  static final Paint _iron = Paint()..color = const Color(0xFF050505);

  @override
  void render(Canvas canvas) {
    // A slatted wooden crate: horizontal planks with thin gaps the fog shows
    // through, nailed to corner posts. The heavy one is banded with iron.
    final double hw = size.x / 2, hh = size.y / 2;
    final rect = Rect.fromLTRB(-hw, -hh, hw, hh);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(0.02)),
      _wood,
    );
    final int planks = math.max(3, (size.y / 0.16).round());
    final double post = math.min(0.085, size.x * 0.12);
    for (var i = 1; i < planks; i++) {
      final double y = -hh + i * size.y / planks;
      // Gaps run between the posts, slightly uneven like hand-cut boards.
      final double wobble = ((i * 37) % 7 - 3) * 0.0025;
      canvas.drawRect(
        Rect.fromLTRB(-hw + post, y - 0.007 + wobble, hw - post, y + 0.006),
        _gap,
      );
    }
    // Knot holes and a split board, so it is wood and not a grille.
    canvas.drawCircle(Offset(hw * 0.35, -hh * 0.15), 0.012, _gap);
    canvas.drawRect(
      Rect.fromLTRB(-hw * 0.2, hh * 0.55, hw * 0.25, hh * 0.55 + 0.005),
      _gap,
    );
    if (massKg >= 25) {
      for (final x in [-hw * 0.45, hw * 0.45]) {
        canvas.drawRect(Rect.fromLTRB(x - 0.03, -hh, x + 0.03, hh), _iron);
        for (final y in [-hh * 0.8, 0.0, hh * 0.8]) {
          canvas.drawCircle(Offset(x, y), 0.009, _gap);
        }
      }
    }
  }
}

/// Kinematic motion uses velocity, so standing bodies inherit real movement.
class MovingPlatform extends BodyComponent {
  MovingPlatform({
    required Vector2 from,
    required Vector2 to,
    required Vector2 size,
    this.speed = 0.8,
  }) : from = from.clone(),
       to = to.clone(),
       size = size.clone(),
       super(renderBody: false);

  final Vector2 from, to, size;
  final double speed;
  bool _towardEnd = true;
  bool _created = false;
  bool get isReady => _created && body.isValid;

  @override
  Body createBody() {
    final result = world.createBody(
      BodyDef(type: BodyType.kinematic, position: from, userData: this),
    );
    result.createShape(
      Polygon.box(size.x / 2, size.y / 2),
      ShapeDef(
        filter: _propFilter(),
        material: SurfaceMaterial(friction: 0.7),
        enableContactEvents: true,
        enableSensorEvents: true,
      ),
    );
    _created = true;
    return result;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || dt <= 0) return;
    Vector2 delta = (_towardEnd ? to : from) - body.position;
    if (delta.length < 0.015) {
      _towardEnd = !_towardEnd;
      delta = (_towardEnd ? to : from) - body.position;
    }
    final distance = delta.length;
    body.linearVelocity = distance == 0
        ? Vector2.zero()
        : delta * (math.min(speed, distance / dt) / distance);
  }

  static final Paint _board = Paint()..color = const Color(0xFF0A0A0A);
  static final Paint _seam = Paint()..color = const Color(0x24BDBDBD);
  static final Paint _rope = Paint()
    ..color = const Color(0xFF101010)
    ..strokeWidth = 0.028
    ..strokeCap = StrokeCap.round;

  @override
  void render(Canvas canvas) {
    // Rough planks lashed side by side, hung from two ropes that run up out
    // of the picture to whatever winds them.
    final double hw = size.x / 2, hh = size.y / 2;
    for (final x in [-hw + 0.12, hw - 0.12]) {
      canvas.drawLine(Offset(x, -hh), Offset(x * 0.7, -hh - 14), _rope);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(-hw, -hh, hw, hh),
        const Radius.circular(0.02),
      ),
      _board,
    );
    for (double x = -hw + 0.3; x < hw - 0.1; x += 0.3) {
      canvas.drawRect(
        Rect.fromLTRB(x - 0.004, -hh + 0.03, x + 0.004, hh),
        _seam,
      );
    }
  }
}

/// A hanging rope, caught anywhere along it, swung on and climbed.
///
/// The physics is a static anchor and one dynamic bob — the point on the
/// rope being held, or its free end — on a real rope joint: it pulls when
/// taut and never pushes, so a slack rope lets the bob fall. Holding the
/// rope partway down moves the bob to that point and shortens the joint to
/// it; climbing changes that length.
///
/// What is drawn is a light chain of points along the whole rope, pinned at
/// the anchor, at the bob and, while the boy's feet clamp it, at his feet.
/// The rope below his hands keeps hanging and swinging with him.
class SwingRope extends BodyComponent {
  SwingRope({required Vector2 anchor, required this.length, this.tyre = false})
    : anchor = anchor.clone(),
      super(renderBody: false);

  final Vector2 anchor;
  final double length;

  /// An old tyre tied to the end: a swing in an orchard.
  final bool tyre;
  late Body bob;
  late DistanceJoint constraint;
  bool _created = false;
  bool get isReady => _created && body.isValid && bob.isValid;

  /// Where the rope is held (or, free, its end): the bob.
  Vector2 get grip => bob.position;

  /// The length of rope from the anchor to the bob.
  double get holdLength => _holdLength;
  double _holdLength = 0;

  /// The shortest hold, near the branch.
  static const double minimumHold = 0.5;

  // The drawn rope: points every [_segment] metres from the anchor.
  late final int _count = math.max(4, (length / 0.15).ceil());
  late final double _segment = length / _count;
  late final List<Vector2> _points = [
    for (var i = 0; i <= _count; i++) Vector2.zero(),
  ];
  late final List<Vector2> _previous = [
    for (var i = 0; i <= _count; i++) Vector2.zero(),
  ];

  /// Where the feet clamp the rope, if they do.
  Vector2? clamp;

  @override
  Body createBody() {
    final fixed = world.createBody(
      BodyDef(type: BodyType.static, position: anchor, userData: this),
    );
    fixed.createShape(
      Circle(radius: 0.06),
      ShapeDef(filter: _propFilter(collideWithPlayer: false)),
    );
    bob = world.createBody(
      BodyDef(
        type: BodyType.dynamic,
        position: anchor + Vector2(0, length),
        angularDamping: 0.1,
        userData: this,
        isBullet: true,
      ),
    );
    const radius = 0.085;
    bob.createShape(
      Circle(radius: radius),
      ShapeDef(
        density: 3 / (math.pi * radius * radius),
        filter: _propFilter(collideWithPlayer: false),
        material: SurfaceMaterial(friction: 0.4),
      ),
    );
    // A rope, not a rod: a spring of no stiffness, so nothing holds the bob
    // out, and a limit that stops it going further than the rope's length.
    constraint = world.physicsWorld.createDistanceJoint(
      DistanceJointDef(
        bodyA: fixed,
        bodyB: bob,
        length: length,
        enableSpring: true,
        hertz: 0,
        enableLimit: true,
        minLength: 0,
        maxLength: length,
      ),
    );
    _holdLength = length;
    for (var i = 0; i <= _count; i++) {
      _points[i].setFrom(anchor + Vector2(0, i * _segment));
      _previous[i].setFrom(_points[i]);
    }
    _created = true;
    return fixed;
  }

  /// Sets how much rope is between the anchor and the hold: climbing up
  /// shortens it, down lengthens it.
  set holdLength(double value) {
    _holdLength = value.clamp(minimumHold, length);
    if (constraint.isValid) {
      constraint.setLengthRange(min: 0, max: _holdLength);
    }
  }

  /// The nearest point of the rope to [point], and how far along the rope
  /// it is, ignoring the first [from] metres.
  (Vector2, double) nearestOnRope(Vector2 point, {double from = 0}) {
    var best = _points.last.clone();
    var bestArc = length;
    var bestDistance = double.infinity;
    for (var i = 0; i < _count; i++) {
      final a = _points[i], b = _points[i + 1];
      final Vector2 d = b - a;
      final double l2 = d.length2;
      double t = l2 < 1e-12 ? 0 : ((point - a).dot(d) / l2).clamp(0.0, 1.0);
      if ((i + t) * _segment < from) {
        if ((i + 1) * _segment < from) continue;
        t = (from / _segment - i).clamp(0.0, 1.0);
      }
      final Vector2 at = a + d * t;
      final double distance = (at - point).length;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = at;
        bestArc = (i + t) * _segment;
      }
    }
    return (best, bestArc);
  }

  /// The point [arc] metres along the rope.
  Vector2 pointAt(double arc) {
    final double k = (arc / _segment).clamp(0.0, _count.toDouble());
    final int i = math.min(k.floor(), _count - 1);
    final double t = k - i;
    return _points[i] + (_points[i + 1] - _points[i]) * t;
  }

  /// Takes hold of the rope at [point] ([arc] metres down it): the bob
  /// moves there, keeping the rope's swing, and the joint shortens to it.
  void catchAt(Vector2 point, double arc) {
    if (!isReady) return;
    final double reach = (bob.position - anchor).length;
    final double hold = arc.clamp(minimumHold, length);
    final Vector2 velocity =
        bob.linearVelocity *
        (reach > 1e-3 ? (point - anchor).length / reach : 1);
    holdLength = hold;
    bob.setTransform(point, const Rot.identity());
    bob.linearVelocity = velocity;
  }

  /// Lets go: the bob goes back to being the rope's free end, where the
  /// rope's end hangs right now, moving as it moves.
  void letGo({double dt = 1 / 120}) {
    clamp = null;
    if (!isReady) return;
    if (_holdLength < length - 0.05) {
      bob.setTransform(_points.last, const Rot.identity());
      bob.linearVelocity = (_points.last - _previous.last) / dt;
    }
    holdLength = length;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady) return;
    // The drawn rope: points every [_segment] metres along it, with momentum
    // and weight, its segments never stretched, held at the anchor, at the
    // hold (which falls between two points) and at the feet.
    // The rope below the hand is heavier with damping, so its end sways
    // rather than flicks.
    final int heldPoint = (_holdLength / _segment).floor();
    final double keepAbove = math.exp(-1.6 * dt);
    final double keepBelow = math.exp(-3.5 * dt);
    final double fall = 18 * dt * dt;
    for (var i = 1; i <= _count; i++) {
      final p = _points[i], q = _previous[i];
      final double keep = i > heldPoint + 1 ? keepBelow : keepAbove;
      final double vx = (p.x - q.x) * keep, vy = (p.y - q.y) * keep;
      q.setFrom(p);
      p.x += vx;
      p.y += vy + fall;
    }
    final double at = _holdLength / _segment;
    final int k = math.min(at.floor(), _count - 1);
    final double t = at - k;
    final Vector2 grip = bob.position;
    final Vector2 span = grip - anchor;
    // Taut, the rope above the hold is a straight line, and runs straight
    // on through the hand.
    final bool taut = span.length >= _holdLength - 0.02;
    final Vector2? feet = clamp;
    final int clamped = feet == null || k + 2 > _count
        ? -1
        : ((_holdLength + (feet - grip).length) / _segment).round().clamp(
            k + 2,
            _count,
          );
    bool pinned(int i) =>
        i == 0 || (taut && i <= k) || i == k || i == k + 1 || i == clamped;
    for (var iteration = 0; iteration < 10; iteration++) {
      _points[0].setFrom(anchor);
      if (taut) {
        for (var i = 1; i <= k; i++) {
          _points[i]
            ..setFrom(span)
            ..scale(i * _segment / _holdLength)
            ..add(anchor);
        }
      }
      // Through the hand: the point above the hold on the rope's line, the
      // one below it hanging on from the hand, half way to straight down.
      final Vector2 before = _points[k];
      final Vector2 through = taut || k == 0 ? span : grip - before;
      if (through.length2 > 1e-12) {
        final Vector2 direction = through.normalized();
        if (!taut && k > 0) {
          before
            ..setFrom(direction)
            ..scale(-t * _segment)
            ..add(grip);
        }
        final Vector2 hang = (direction + Vector2(0, 1))..normalize();
        _points[k + 1]
          ..setFrom(hang)
          ..scale((1 - t) * _segment)
          ..add(grip);
      }
      if (clamped > 0) _points[clamped].setFrom(feet!);
      for (var i = 0; i < _count; i++) {
        final a = _points[i], b = _points[i + 1];
        final Vector2 d = b - a;
        final double l = d.length;
        if (l <= _segment || l < 1e-9) continue;
        final double wa = pinned(i) ? 0 : 1, wb = pinned(i + 1) ? 0 : 1;
        if (wa + wb == 0) continue;
        final Vector2 fix = d * ((l - _segment) / l / (wa + wb));
        a.addScaled(fix, wa);
        b.addScaled(fix, -wb);
      }
    }
    // A little stiffness: each free point below the hand is drawn a touch
    // towards the line of the two above it, so the rope bends in curves.
    for (var i = k + 3; i <= _count; i++) {
      if (i == clamped) continue;
      final Vector2 straight = _points[i - 1] * 2 - _points[i - 2];
      _points[i].add((straight - _points[i])..scale(0.08));
    }
  }

  static final Paint _branch = Paint()..color = const Color(0xFF0B0B0B);
  static final Paint _fastening = Paint()..color = const Color(0xFF242424);
  static final Paint _nail = Paint()..color = const Color(0xFF606060);
  static final Paint _cord = Paint()
    ..color = const Color(0xFF181818)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.032
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  static final Paint _fray = Paint()
    ..color = const Color(0xFF181818)
    ..strokeWidth = 0.012
    ..strokeCap = StrokeCap.round;
  static final Paint _knot = Paint()..color = const Color(0xFF181818);
  static final Paint _rubber = Paint()..color = const Color(0xFF070707);
  static final Paint _tread = Paint()
    ..color = const Color(0x24FFFFFF)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.012;

  /// A tyre hanging from the rope's end, along the rope's line, seen a
  /// little from the side so it is an ellipse with its hole showing.
  void _drawTyre(Canvas canvas, Offset end, Offset down) {
    final double angle = math.atan2(down.dx, down.dy);
    canvas.save();
    canvas.translate(end.dx, end.dy);
    canvas.rotate(-angle);
    const double r = 0.3;
    final Rect outer = Rect.fromCenter(
      center: const Offset(0, r - 0.02),
      width: r * 1.25,
      height: r * 2,
    );
    final Rect inner = Rect.fromCenter(
      center: const Offset(0.02, r - 0.02),
      width: r * 0.62,
      height: r * 1.22,
    );
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addOval(outer)
        ..addOval(inner),
      _rubber,
    );
    // Worn tread, faint.
    canvas.drawArc(outer.deflate(0.035), 0.4, 2.2, false, _tread);
    canvas.drawCircle(Offset.zero, 0.035, _knot);
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    if (!isReady) return;
    // A high branch exits the frame; the small visible fastening marks the
    // actual static anchor. It sits above the reachable character space.
    final support = Path()
      ..moveTo(-0.07, 0.025)
      ..lineTo(0.035, -0.12)
      ..quadraticBezierTo(0.70, -0.25, 1.28, -1.05)
      ..lineTo(3.60, -4.50)
      ..lineTo(3.88, -4.50)
      ..lineTo(1.48, -0.92)
      ..quadraticBezierTo(0.70, -0.04, 0.06, 0.09)
      ..close();
    canvas.drawPath(support, _branch);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-0.085, -0.065, 0.16, 0.11),
        const Radius.circular(0.025),
      ),
      _fastening,
    );
    canvas.drawCircle(const Offset(-0.012, -0.025), 0.016, _nail);
    // The rope, as a smooth curve through its points (this canvas is
    // centred on the anchor).
    Offset at(int i) =>
        Offset(_points[i].x - anchor.x, _points[i].y - anchor.y);
    final rope = Path()..moveTo(0, 0);
    for (var i = 1; i < _count; i++) {
      final a = at(i), b = at(i + 1);
      rope.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    }
    final end = at(_count);
    rope.lineTo(end.dx, end.dy);
    canvas.drawPath(rope, _cord);
    // A knot and a frayed end below it, rather than a ball; or the tyre.
    final Offset last = end - at(_count - 1);
    final double run = last.distance;
    if (tyre && run > 0) {
      _drawTyre(canvas, end, last / run);
    } else if (run > 0) {
      final Offset dir = last / run;
      canvas.drawCircle(end, 0.03, _knot);
      for (final splay in const [-0.25, 0.0, 0.3]) {
        final Offset tip =
            end +
            Offset(
                  dir.dx * math.cos(splay) - dir.dy * math.sin(splay),
                  dir.dx * math.sin(splay) + dir.dy * math.cos(splay),
                ) *
                0.09;
        canvas.drawLine(end, tip, _fray);
      }
    }
  }

  @override
  void onRemove() {
    if (_created) {
      if (constraint.isValid) constraint.destroy();
      if (bob.isValid) world.destroyBody(bob);
    }
    super.onRemove();
  }
}
