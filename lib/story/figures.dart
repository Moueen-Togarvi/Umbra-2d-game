import 'dart:math' as math;
import 'dart:ui';

/// Solves a two-bone limb from [root] towards [target] with bones [a] and
/// [b], bending to the side [bend] (+1 or −1); returns the middle joint.
Offset solveLimb(Offset root, Offset target, double a, double b, double bend) {
  Offset to = target - root;
  double d = to.distance;
  final double reach = (a + b) * 0.999;
  if (d > reach) {
    to = to / d * reach;
    d = reach;
  }
  if (d < 1e-6) return root + Offset(0, a);
  final double cosA = ((a * a + d * d - b * b) / (2 * a * d)).clamp(-1.0, 1.0);
  final double angle = math.atan2(to.dy, to.dx) + bend * math.acos(cosA);
  return root + Offset(math.cos(angle), math.sin(angle)) * a;
}

/// A value that follows its goal on a critically damped spring: smooth,
/// and never overshooting into a wobble.
class Calm {
  Calm(this.value, {this.hertz = 2});
  double value;
  double hertz;
  double _speed = 0;

  double step(double goal, double dt) {
    if (dt <= 0) return value;
    final double w = 2 * math.pi * hertz;
    final double x = value - goal;
    final double e = math.exp(-w * dt);
    final double next = (x + (_speed + w * x) * dt) * e;
    _speed = (_speed - w * (_speed + w * x) * dt) * e;
    value = goal + next;
    return value;
  }
}

/// The boy's mother, as she is seen: a silhouette in the lit doorway.
///
/// A slight woman in a long dress with her hair up. She can step into the
/// doorway from inside ([presence]), rest a hand on the frame, reach out
/// after him ([reach]) and bring her hands to her face ([grief]). Every
/// part follows its goal on a critically damped spring, so she moves
/// slowly and never jerks; the dress swings a little behind her body.
class Mother {
  /// 0 inside, out of sight; 1 standing in the doorway.
  double presence = 0;

  /// 0 arm at her side; 1 reaching out after him.
  double reach = 0;

  /// 0 hands down; 1 hands to her face.
  double grief = 0;

  final Calm _presence = Calm(0, hertz: 0.7);
  final Calm _reach = Calm(0, hertz: 0.9);
  final Calm _grief = Calm(0, hertz: 0.6);
  final Calm _hem = Calm(0, hertz: 1.1);
  double _time = 0;
  double _lastX = 0;

  static const double height = 1.48;
  final Paint _paint = Paint()..color = const Color(0xFF030201);
  final Paint _scarf = Paint()..color = const Color(0xFF202022);
  final Paint _limb = Paint()
    ..color = const Color(0xFF030201)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  bool get visible => _presence.value > 0.01;

  /// A limb as two tapered segments, rounded at the joints.
  void _taper(
    Canvas canvas,
    Offset a,
    Offset b,
    Offset c,
    double wa,
    double wc,
  ) {
    final double wb = (wa + wc) / 2;
    void segment(Offset p, Offset q, double wp, double wq) {
      final Offset d = q - p;
      final double len = d.distance;
      if (len < 1e-6) return;
      final Offset n = Offset(-d.dy / len, d.dx / len);
      canvas.drawPath(
        Path()
          ..moveTo(p.dx + n.dx * wp / 2, p.dy + n.dy * wp / 2)
          ..lineTo(q.dx + n.dx * wq / 2, q.dy + n.dy * wq / 2)
          ..lineTo(q.dx - n.dx * wq / 2, q.dy - n.dy * wq / 2)
          ..lineTo(p.dx - n.dx * wp / 2, p.dy - n.dy * wp / 2)
          ..close(),
        _paint,
      );
      canvas.drawCircle(q, wq / 2, _paint);
    }

    canvas.drawCircle(a, wa / 2, _paint);
    segment(a, b, wa, wb);
    segment(b, c, wb, wc);
  }

  void update(double dt) {
    _time += dt;
    _presence.step(presence, dt);
    _reach.step(reach, dt);
    _grief.step(grief, dt);
    final double moved = _presence.value - _lastX;
    _lastX = _presence.value;
    // The hem trails her movement and the reaching lean.
    _hem.step((-moved / math.max(dt, 1e-3)) * 0.06 + _reach.value * 0.03, dt);
  }

  void render(Canvas canvas, Rect door) {
    if (!visible) return;
    final double p = _presence.value;
    final double h = height;
    // She stands a little to the hinge side, so the light shows past her.
    final double x =
        door.left - 0.3 + (door.center.dx - 0.05 - door.left + 0.3) * p;
    final Offset feet = Offset(x, door.bottom);
    final double breathe = math.sin(_time * 1.6) * 0.004;
    final double lean = 0.12 * _reach.value - 0.05 * _grief.value;

    // Head, neck and body, clipped to the doorway (she is inside it).
    canvas.save();
    canvas.clipRect(door.inflate(0.005));
    canvas.translate(feet.dx, feet.dy);
    canvas.rotate(lean * 0.35);
    final double headR = 0.088;
    final Offset head = Offset(0.01, -h + headR - breathe);
    canvas.drawOval(
      Rect.fromCenter(center: head, width: headR * 1.8, height: headR * 2.15),
      _paint,
    );
    // Hair gathered in a bun at the back, and a loose strand.
    canvas.drawCircle(
      head + Offset(-headR * 0.95, -headR * 0.35),
      0.06,
      _paint,
    );
    final double hem = _hem.value;
    final body = Path()
      // Neck
      ..moveTo(-0.025, head.dy + headR * 0.8)
      ..lineTo(0.03, head.dy + headR * 0.8)
      // Shoulder to waist
      ..lineTo(0.13, -h * 0.8)
      ..quadraticBezierTo(0.1, -h * 0.68, 0.075, -h * 0.58)
      // The skirt to the floor, flaring a little and trailing.
      ..quadraticBezierTo(0.13 + hem * 0.5, -h * 0.3, 0.2 + hem, -0.01)
      ..lineTo(0.1 + hem * 0.8, 0.0)
      ..lineTo(-0.08 + hem * 0.6, 0.0)
      ..lineTo(-0.18 + hem, -0.01)
      ..quadraticBezierTo(-0.12 + hem * 0.5, -h * 0.3, -0.075, -h * 0.58)
      ..quadraticBezierTo(-0.1, -h * 0.68, -0.12, -h * 0.8)
      ..close();
    canvas.drawPath(body, _paint);
    // Her long shawl and bun distinguish her from the other silhouettes.
    canvas.drawPath(
      Path()
        ..moveTo(-0.09, -h * 0.83)
        ..quadraticBezierTo(-0.19, -h * 0.8, -0.15, -h * 0.73)
        ..quadraticBezierTo(-0.2, -h * 0.48, -0.24 + hem, -h * 0.34)
        ..lineTo(-0.13 + hem, -h * 0.38)
        ..lineTo(-0.055, -h * 0.78)
        ..close(),
      _scarf,
    );
    // The near hand rests on the door frame as she leans out.
    _limb.strokeWidth = 0.048;
    final Offset backShoulder = Offset(-0.1, -h * 0.79);
    final Offset frame = Offset(door.left - feet.dx + 0.02, -h * 0.62);
    final Offset backHand = Offset.lerp(
      Offset(-0.17, -h * 0.46),
      Offset.lerp(frame, Offset(-0.02, head.dy + 0.05), _grief.value)!,
      math.max(p * 0.8, _grief.value),
    )!;
    final Offset backElbow = solveLimb(backShoulder, backHand, 0.25, 0.24, 1);
    _taper(canvas, backShoulder, backElbow, backHand, 0.075, 0.045);
    canvas.restore();

    // The reaching arm, which can come out past the frame.
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    canvas.rotate(lean * 0.35);
    final Offset shoulder = Offset(0.11, -h * 0.79);
    final Offset rest = Offset(0.16, -h * 0.47);
    final Offset out = Offset(0.58, -h * 0.84);
    final Offset face = Offset(0.05, head.dy + 0.06);
    Offset hand = Offset.lerp(rest, out, _reach.value)!;
    hand = Offset.lerp(hand, face, _grief.value)!;
    final Offset elbow = solveLimb(shoulder, hand, 0.25, 0.24, -1);
    _taper(canvas, shoulder, elbow, hand, 0.08, 0.047);
    // An open hand, fingers spread a little when reaching.
    final double spread = 0.2 + 0.6 * _reach.value;
    final Offset dir = hand - elbow;
    final double angle = math.atan2(dir.dy, dir.dx);
    canvas.drawOval(
      Rect.fromCenter(
        center: hand + Offset(math.cos(angle), math.sin(angle)) * 0.03,
        width: 0.075,
        height: 0.06,
      ),
      _paint,
    );
    _limb.strokeWidth = 0.017;
    for (var f = -2; f <= 2; f++) {
      final double a = angle + f * spread * 0.2;
      final Offset base =
          hand + Offset(math.cos(angle), math.sin(angle)) * 0.04;
      canvas.drawLine(
        base,
        base + Offset(math.cos(a), math.sin(a)) * (0.07 - f.abs() * 0.01),
        _limb,
      );
    }
    canvas.restore();
  }
}
