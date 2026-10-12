import 'dart:math' as math;
import 'dart:ui';

import '../config/palette.dart';

/// The pose a [BoySilhouette] is drawn in. All values are 0..1 blends except
/// the angles, so a pose can ease between states without snapping.
class BoyPose {
  const BoyPose({
    this.facing = 1,
    this.walkPhase = 0,
    this.walk = 0,
    this.air = 0,
    this.fallLean = 0,
    this.blink = false,
    this.limp = 0,
  });

  /// +1 faces right, -1 faces left.
  final double facing;

  /// Progress through the stride, in radians.
  final double walkPhase;

  /// How much of the walking pose to show.
  final double walk;

  /// How much of the airborne pose to show.
  final double air;

  /// -1 rising .. +1 falling, for the airborne pose.
  final double fallLean;

  /// Eyes shut this frame.
  final bool blink;

  /// How much of the hanged, lifeless pose to show: head dropped, limbs
  /// straight down, eyes dark.
  final double limp;
}

/// The small boy the reference art is built around, drawn as strokes and
/// blobs in body-local metres.
///
/// Origin at the centre of a body [height] tall, y down: the crown is at
/// `-height/2`, the soles at `+height/2`. The proportions are the point: a
/// head nearly two fifths of the whole height, sitting straight on the
/// shoulders with no neck to speak of, a short soft body, short legs. That is
/// what makes the world around him look vast, and it is why a stick figure
/// with the same height never reads as the same character.
class BoySilhouette {
  BoySilhouette({required this.height});

  final double height;

  final Paint _fill = Paint()..color = Palette.silhouette;
  final Paint _limb = Paint()
    ..color = Palette.silhouette
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _eye = Paint()..color = Palette.eyes;
  final Paint _glow = Paint()..color = Palette.eyeGlow;

  // Proportions, as fractions of [height].
  static const double _headRadiusF = 0.185;
  static const double _hairF = 0.05;
  static const double _shoulderYF = -0.5 + 2 * _headRadiusF + _hairF - 0.06;
  static const double _hipYF = _shoulderYF + 0.27;
  static const double _shoulderHalfF = 0.115;
  static const double _hipHalfF = 0.085;
  static const double _upperArmF = 0.16;
  static const double _forearmF = 0.14;
  static const double _thighF = 0.19;
  static const double _shinF = 0.17;

  void draw(Canvas canvas, BoyPose pose) {
    final double h = height;
    final double headR = h * _headRadiusF;
    final double headY = -h / 2 + h * _hairF + headR;
    final double shoulderY = h * _shoulderYF;
    final double hipY = h * _hipYF;

    canvas.save();
    canvas.scale(pose.facing, 1);

    // Bob with the stride, breathe at rest, hang still when limp.
    final double alive = 1 - pose.limp;
    final double bob =
        alive *
        (pose.walk * math.sin(pose.walkPhase * 2).abs() * 0.022 * h +
            (1 - pose.walk) * math.sin(_clock * 1.5) * 0.004 * h);
    canvas.translate(0, -bob);
    final double lean =
        alive * (pose.walk * 0.08 + pose.air * 0.10 * pose.fallLean);
    canvas.rotate(lean);

    _drawLegs(canvas, pose, hipY, h);
    _drawArms(canvas, pose, shoulderY, h);
    _drawTorso(canvas, shoulderY, hipY, h);
    _drawHead(canvas, pose, headY, headR, h);

    canvas.restore();
  }

  /// A shared slow clock for the idle breath, advanced by whoever draws.
  static double _clock = 0;
  static void tick(double dt) => _clock += dt;

  void _drawTorso(Canvas canvas, double shoulderY, double hipY, double h) {
    final double sw = h * _shoulderHalfF;
    final double hw = h * _hipHalfF;
    // Soft-shouldered, tapering slightly to the hips; the top is tucked up
    // under the head so the two read as one mass.
    final Path torso = Path()
      ..moveTo(-sw, shoulderY + 0.02 * h)
      ..quadraticBezierTo(0, shoulderY - 0.07 * h, sw, shoulderY + 0.02 * h)
      ..lineTo(hw, hipY + 0.03 * h)
      ..quadraticBezierTo(0, hipY + 0.09 * h, -hw, hipY + 0.03 * h)
      ..close();
    canvas.drawPath(torso, _fill);
  }

  void _drawHead(
    Canvas canvas,
    BoyPose pose,
    double headY,
    double headR,
    double h,
  ) {
    canvas.save();
    // A hanged head drops forward and to the side.
    if (pose.limp > 0) {
      canvas.translate(0.02 * h, headY + headR * 0.6);
      canvas.rotate(0.55 * pose.limp);
      canvas.translate(-0.02 * h, -(headY + headR * 0.6));
    }
    final Offset centre = Offset(0.01 * h, headY);
    canvas.drawCircle(centre, headR, _fill);

    // Small uneven tufts over the crown and back. Keep them subtle at phone
    // scale so the head stays round instead of reading as a spiked helmet.
    final Path hair = Path();
    const int tufts = 5;
    for (var i = 0; i < tufts; i++) {
      final double a = -math.pi * 0.36 - i * (math.pi * 0.64 / (tufts - 1));
      final Offset base = centre + Offset(math.cos(a), math.sin(a)) * headR;
      final double len = headR * (0.13 + 0.05 * math.sin(i * 2.3));
      // Tufts lean back, away from the direction faced.
      final double lean = a - 0.35;
      final Offset tip = base + Offset(math.cos(lean), math.sin(lean)) * len;
      final Offset side1 =
          base + Offset(math.cos(a + 1.2), math.sin(a + 1.2)) * headR * 0.09;
      final Offset side2 =
          base + Offset(math.cos(a - 1.2), math.sin(a - 1.2)) * headR * 0.09;
      hair
        ..moveTo(side1.dx, side1.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(side2.dx, side2.dy)
        ..close();
    }
    canvas.drawPath(hair, _fill);

    // Eyes: two small bright points, close together on the front of the
    // face, the only light on him. Dark when he is not alive.
    if (pose.limp < 0.5) {
      final double open = pose.blink ? 0.15 : 1.0;
      for (final f in const [0.30, 0.60]) {
        final Offset eye = Offset(
          centre.dx + headR * f,
          centre.dy + headR * 0.02,
        );
        canvas.drawCircle(eye, headR * 0.16, _glow);
        canvas.save();
        canvas.translate(eye.dx, eye.dy);
        canvas.scale(1, open);
        canvas.drawCircle(Offset.zero, headR * 0.075, _eye);
        canvas.restore();
      }
    }
    canvas.restore();
  }

  void _drawArms(Canvas canvas, BoyPose pose, double shoulderY, double h) {
    _limb.strokeWidth = 0.052 * h;
    for (final side in const [-1.0, 1.0]) {
      // Angle from straight down, positive forward. A small swing when
      // walking, opposite to the leg on that side; a drift back in the air;
      // straight down and still when limp.
      final double swing = math.sin(pose.walkPhase + (side > 0 ? math.pi : 0));
      double a = 0.06 * side + pose.walk * swing * 0.35;
      a = _mix(a, -0.30 - pose.fallLean * 0.35 + side * 0.08, pose.air);
      a = _mix(a, 0.04 * side, pose.limp);
      final Offset shoulder = Offset(
        h * _shoulderHalfF * 0.8 * side,
        shoulderY + 0.03 * h,
      );
      final double bend =
          _mix(0.12, 0.48, pose.walk) * (0.5 + 0.5 * swing.abs());
      final Offset elbow = shoulder + _polar(math.pi / 2 - a, h * _upperArmF);
      final Offset hand = elbow + _polar(math.pi / 2 - a - bend, h * _forearmF);
      canvas.drawLine(shoulder, elbow, _limb);
      canvas.drawLine(elbow, hand, _limb);
      canvas.drawCircle(hand, 0.029 * h, _fill);
    }
  }

  void _drawLegs(Canvas canvas, BoyPose pose, double hipY, double h) {
    _limb.strokeWidth = 0.075 * h;
    final double thigh = h * _thighF;
    final double shin = h * _shinF;
    for (final side in const [-1.0, 1.0]) {
      final double swing = math.sin(pose.walkPhase + (side > 0 ? 0 : math.pi));
      final double lift =
          0.5 + 0.5 * math.cos(pose.walkPhase + (side > 0 ? 0 : math.pi));
      // Standing: legs a little apart. Walking: short quick strides, the
      // knee bending as the leg comes forward.
      double t = 0.10 * side + pose.walk * swing * 0.55;
      double k = pose.walk * 0.9 * lift * (swing > 0 ? 1 : 0.2);
      // Airborne: one leg tucked, one trailing, straightening into the fall.
      final double tuck = side > 0 ? 0.8 : -0.3;
      t = _mix(t, tuck - pose.fallLean * 0.4, pose.air);
      k = _mix(
        k,
        (side > 0 ? 1.2 : 0.3) * (1 - pose.fallLean.clamp(0.0, 1.0) * 0.6),
        pose.air,
      );
      // Hanged: straight down, toes pointed.
      t = _mix(t, 0.05 * side, pose.limp);
      k = _mix(k, 0.0, pose.limp);

      final Offset hip = Offset(h * 0.05 * side, hipY);
      final Offset knee = hip + _polar(math.pi / 2 - t, thigh);
      final Offset foot = knee + _polar(math.pi / 2 - t + k, shin);
      canvas.drawLine(hip, knee, _limb);
      canvas.drawLine(knee, foot, _limb);
      // A small foot, flat when standing, dangling when limp.
      final Offset toe =
          foot + Offset(0.07 * h * (1 - pose.limp), 0.03 * h * pose.limp);
      canvas.drawLine(foot, toe, _limb);
    }
  }

  static Offset _polar(double angle, double length) =>
      Offset(math.cos(angle) * length, math.sin(angle) * length);

  static double _mix(double a, double b, double t) => a + (b - a) * t;
}
