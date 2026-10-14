import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;

import '../character/character_rig.dart';
export '../character/character_rig.dart'
    show CharacterPose, CharacterRigPose, RigJoint;

/// The boy: a soft black silhouette with a big round head, messy hair and
/// two small glowing eyes, drawn from one solved skeletal pose.
///
/// Every part is a smooth, anti-aliased closed curve rather than a stroked
/// line. Limbs are tapered capsules, so the joints read as one body instead
/// of a puppet's sticks.
///
/// There is deliberately no blur mask filter on the body: on the web
/// renderer a blurred *path* at this scale is not drawn at all (only the
/// eyes were left), and the plain anti-aliased edge already reads as soft
/// at gameplay size.
/// The same joint positions are handed to native articulated physics when
/// he goes limp.
class CharacterSilhouette {
  CharacterSilhouette({required this.height})
    : _rig = CharacterRig(height: height);

  final double height;
  final CharacterRig _rig;

  /// The body's colour: not quite black, so the ground stays the darkest
  /// thing on screen and his outline still reads against it.
  static const Color bodyColor = Color(0xFF0B0B0B);

  final Paint _body = Paint()
    ..color = bodyColor
    ..isAntiAlias = true;
  final Paint _eye = Paint()..color = const Color(0xFFFFFFFF);
  final Paint _glow = Paint();

  // Every shape is built in its own Path. The web renderer records a
  // reference to a drawn path rather than a copy, so rebuilding one shared
  // Path for several draws in a frame would draw the last shape each time.

  CharacterRigPose solve(CharacterPose pose) => _rig.solve(pose);

  void draw(Canvas canvas, CharacterPose pose) => drawRig(canvas, solve(pose));

  /// [hairSway] bends the hair tips backwards (positive) or forwards, in
  /// fractions of height, for a little follow-through on starts and stops.
  void drawRig(Canvas canvas, CharacterRigPose pose, {double hairSway = 0}) {
    final double h = pose.height;
    _arm(canvas, pose, front: false);
    _leg(canvas, pose, front: false);
    _torso(canvas, pose);
    _leg(canvas, pose, front: true);
    _taper(
      canvas,
      pose[RigJoint.neck],
      pose[RigJoint.neck] + (pose[RigJoint.head] - pose[RigJoint.neck]) * 0.55,
      h * 0.034,
      h * 0.036,
    );
    _head(canvas, pose, hairSway);
    _arm(canvas, pose, front: true);
  }

  // ---------------------------------------------------------------------------
  // Parts
  // ---------------------------------------------------------------------------

  void _leg(Canvas canvas, CharacterRigPose pose, {required bool front}) {
    final double h = pose.height;
    final hip = pose[front ? RigJoint.frontHip : RigJoint.backHip];
    final knee = pose[front ? RigJoint.frontKnee : RigJoint.backKnee];
    final ankle = pose[front ? RigJoint.frontAnkle : RigJoint.backAnkle];
    final heel = pose[front ? RigJoint.frontHeel : RigJoint.backHeel];
    final toe = pose[front ? RigJoint.frontToe : RigJoint.backToe];
    // Shorts: a blocky leg of cloth over the hip and the top half of the
    // thigh, wider than the bare leg that comes out of it.
    final Vector2 thighLine = knee - hip;
    final Vector2 up = thighLine.length > 1e-6
        ? thighLine.normalized() * (-h * 0.025)
        : Vector2.zero();
    final Vector2 hem = hip + thighLine * 0.55;
    _taper(canvas, hip + up, hem, h * 0.058, h * 0.052);
    // Bare legs: a sturdy knee and a shin narrowing to the ankle.
    _taper(canvas, hem, knee, h * 0.035, h * 0.031);
    _taper(canvas, knee, ankle, h * 0.031, h * 0.024);
    _boot(canvas, ankle, heel, toe, pose.side, h);
  }

  /// A chunky little boot: rounded heel, flat sole, a rounded toe that
  /// turns up slightly, and an instep rising to the ankle. Oriented along
  /// the simulated heel-to-toe line, so its sole lies on whatever ground
  /// the foot is standing on.
  void _boot(
    Canvas canvas,
    Vector2 ankle,
    Vector2 heel,
    Vector2 toe,
    double facing,
    double h,
  ) {
    final Vector2 along = toe - heel;
    if (along.length < 1e-6) along.setValues(facing, 0);
    along.normalize();
    final Vector2 down = Vector2(-along.y * facing, along.x * facing);
    Offset at(double forward, double below) {
      final p = ankle + along * (forward * h) + down * (below * h);
      return Offset(p.x, p.y);
    }

    const double sole = CharacterRig.ankleHeight;
    final boot = Path();
    final start = at(-0.026, -0.016);
    boot.moveTo(start.dx, start.dy);
    // (control point, end point) pairs, back of the ankle round to the
    // instep, in boot coordinates: forward along the foot, down to the sole.
    for (final (control, end) in const [
      ((-0.040, 0.0), (-0.036, sole * 0.62)), // round heel
      ((-0.034, sole), (-0.022, sole)), // heel onto the sole
      ((0.021, sole), (0.064, sole)), // flat sole
      ((0.092, sole * 0.98), (0.095, sole * 0.55)), // rounded toe
      ((0.092, sole * 0.05), (0.068, 0.0)), // top of the toe
      ((0.036, -0.006), (0.016, -0.017)), // instep up to the ankle
    ]) {
      final c = at(control.$1, control.$2);
      final e = at(end.$1, end.$2);
      boot.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
    }
    boot.close();
    canvas.drawPath(boot, _body);
  }

  void _arm(Canvas canvas, CharacterRigPose pose, {required bool front}) {
    final double h = pose.height;
    final shoulder =
        pose[front ? RigJoint.frontShoulder : RigJoint.backShoulder];
    final elbow = pose[front ? RigJoint.frontElbow : RigJoint.backElbow];
    final hand = pose[front ? RigJoint.frontHand : RigJoint.backHand];
    _taper(canvas, shoulder, elbow, h * 0.033, h * 0.022);
    _taper(canvas, elbow, hand, h * 0.021, h * 0.017);
    final Vector2 along = hand - elbow;
    final Vector2 palm = along.length > 1e-6
        ? hand + along.normalized() * h * 0.012
        : hand;
    _circle(canvas, palm, h * 0.025);
  }

  void _torso(Canvas canvas, CharacterRigPose pose) {
    final double h = pose.height;
    final neck = pose[RigJoint.neck];
    final pelvis = pose[RigJoint.pelvis];
    final Vector2 spine = pelvis - neck;
    final double length = spine.length / h;
    canvas.save();
    canvas.translate(neck.x, neck.y);
    canvas.rotate(math.atan2(spine.y, spine.x) - math.pi / 2);
    // Mid-turn the chest narrows towards a front view, but a child seen
    // from the front is still a body, not a sliver.
    canvas.scale(h * pose.side * math.max(0.55, pose.facing.abs()), h);
    final double l = length;
    // A loose shirt: rounded shoulders, a fuller chest, and a hem that
    // hangs a little wider than the waist over the shorts.
    final shirt = Path()
      ..moveTo(-0.058, 0.020)
      ..quadraticBezierTo(0.000, -0.010, 0.056, 0.016)
      ..quadraticBezierTo(0.092, 0.040, 0.090, 0.110)
      ..quadraticBezierTo(0.084, l * 0.62, 0.080, l * 0.80)
      ..quadraticBezierTo(0.088, l * 0.93, 0.094, l + 0.014)
      ..quadraticBezierTo(0.004, l + 0.040, -0.090, l + 0.008)
      ..quadraticBezierTo(-0.084, l * 0.80, -0.082, l * 0.55)
      ..quadraticBezierTo(-0.088, 0.090, -0.058, 0.020)
      ..close();
    canvas.drawPath(shirt, _body);
    canvas.restore();
  }

  void _head(Canvas canvas, CharacterRigPose pose, double hairSway) {
    final double h = pose.height;
    final head = pose[RigJoint.head];
    canvas.save();
    canvas.translate(head.x, head.y);
    canvas.rotate(pose.headAngle);
    // A head is round: from the front it is nearly as wide as in profile.
    canvas.scale(h * pose.side * math.max(0.88, pose.facing.abs()), h);

    // The skull: a slightly egg-shaped ball, fuller at the back, with a
    // small rounded chin at the front.
    final skull = Path()
      ..moveTo(0.0, -0.157)
      ..cubicTo(0.085, -0.160, 0.152, -0.105, 0.150, -0.025)
      ..cubicTo(0.149, 0.045, 0.128, 0.105, 0.075, 0.128)
      ..cubicTo(0.035, 0.145, -0.035, 0.140, -0.085, 0.118)
      ..cubicTo(-0.140, 0.092, -0.163, 0.035, -0.160, -0.025)
      ..cubicTo(-0.157, -0.105, -0.090, -0.160, 0.0, -0.157)
      ..close();
    canvas.drawPath(skull, _body);

    // Short, messy hair: a rounded mop a little bigger than the skull, a
    // fringe curling forward, a small cowlick and a soft point at the back.
    // The tips trail with [hairSway].
    Offset p(double x, double y) =>
        Offset(x + hairSway * math.max(0.0, -y - 0.10) * 2.2, y);
    final hair = Path();
    void q(double cx, double cy, double x, double y) {
      final c = p(cx, cy);
      final e = p(x, y);
      hair.quadraticBezierTo(c.dx, c.dy, e.dx, e.dy);
    }

    final start = p(0.138, -0.060);
    hair.moveTo(start.dx, start.dy);
    q(0.168, -0.085, 0.174, -0.126);
    q(0.152, -0.118, 0.142, -0.134);
    q(0.150, -0.180, 0.108, -0.196);
    q(0.080, -0.178, 0.050, -0.190);
    q(0.030, -0.214, 0.000, -0.201);
    q(-0.060, -0.200, -0.106, -0.172);
    q(-0.150, -0.152, -0.172, -0.114);
    q(-0.194, -0.100, -0.194, -0.072);
    q(-0.172, -0.064, -0.170, -0.040);
    q(-0.178, -0.012, -0.160, 0.010);
    hair
      ..lineTo(-0.100, 0.0)
      ..lineTo(0.100, -0.062)
      ..close();
    canvas.drawPath(hair, _body);

    if (!pose.blink) {
      // Two small white eyes close together at the front of the face, the
      // far one a touch smaller, in a faint halo of their own light. As the
      // face turns to the camera they slide to the middle of it, level and
      // the same size: the front view LIMBO's boy passes through as he
      // turns round. At the middle the two sides are mirror images, so the
      // flip of the drawing there cannot be seen.
      final double toCamera = math.max(
        1 - pose.facing.abs(),
        pose.headTurn.clamp(0.0, 1.0),
      );
      double mix(double a, double b) => a + (b - a) * toCamera;
      final glowCentre = Offset(mix(0.077, 0.0), mix(0.004, 0.004));
      _glow.shader = Gradient.radial(
        glowCentre,
        0.055,
        const [Color(0x40FFFFFF), Color(0x14FFFFFF), Color(0x00FFFFFF)],
        const [0, 0.45, 1],
      );
      canvas.drawCircle(glowCentre, 0.055, _glow);
      canvas.drawCircle(
        Offset(mix(0.100, 0.035), mix(0.006, 0.004)),
        mix(0.0135, 0.0125),
        _eye,
      );
      canvas.drawCircle(
        Offset(mix(0.054, -0.035), mix(0.001, 0.004)),
        mix(0.0115, 0.0125),
        _eye,
      );
    }
    canvas.restore();
  }

  // ---------------------------------------------------------------------------
  // Shape helpers (world metres unless the canvas is scaled)
  // ---------------------------------------------------------------------------

  void _circle(Canvas canvas, Vector2 centre, double radius) {
    canvas.drawCircle(Offset(centre.x, centre.y), radius, _body);
  }

  /// A capsule from [a] to [b] whose radius tapers from [ra] to [rb].
  void _taper(Canvas canvas, Vector2 a, Vector2 b, double ra, double rb) {
    final Vector2 d = b - a;
    final double length = d.length;
    if (length < 1e-6) {
      _circle(canvas, a, math.max(ra, rb));
      return;
    }
    final double ux = d.x / length, uy = d.y / length;
    final double nx = -uy, ny = ux;
    final limb = Path()
      ..moveTo(a.x + nx * ra, a.y + ny * ra)
      ..lineTo(b.x + nx * rb, b.y + ny * rb)
      ..arcToPoint(
        Offset(b.x - nx * rb, b.y - ny * rb),
        radius: Radius.circular(rb),
        clockwise: false,
      )
      ..lineTo(a.x - nx * ra, a.y - ny * ra)
      ..arcToPoint(
        Offset(a.x + nx * ra, a.y + ny * ra),
        radius: Radius.circular(ra),
        clockwise: false,
      )
      ..close();
    canvas.drawPath(limb, _body);
  }
}
