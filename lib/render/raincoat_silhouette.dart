import 'dart:math' as math;
import 'dart:ui';

import 'package:flame_forge2d/flame_forge2d.dart' show Vector2;

import '../character/character_preset.dart';
import '../character/character_rig.dart';
export '../character/character_rig.dart'
    show RaincoatPose, CharacterRigPose, RigJoint;

/// Three readable original silhouettes drawn from one solved skeletal pose.
/// The same joint positions are handed to native articulated physics.
class RaincoatSilhouette {
  RaincoatSilhouette({
    required this.height,
    this.preset = CharacterPreset.raincoat,
  });
  final double height;
  CharacterPreset preset;
  static double _clock = 0;
  static void tick(double dt) => _clock += dt;

  final Paint _black = Paint()..color = const Color(0xFF030303);
  final Paint _cloth = Paint()..color = const Color(0xFF080808);
  final Paint _shade = Paint()..color = const Color(0xFF171717);
  final Paint _limb = Paint()
    ..color = const Color(0xFF030303)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _detail = Paint()
    ..color = const Color(0xFF2B2B2B)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.006
    ..strokeCap = StrokeCap.round;

  CharacterRigPose solve(RaincoatPose pose) {
    final rig = CharacterRig(height: height, preset: preset)..clock = _clock;
    return rig.solve(pose);
  }

  void draw(Canvas canvas, RaincoatPose pose) => drawRig(canvas, solve(pose));

  void drawRig(Canvas canvas, CharacterRigPose pose) {
    _leg(canvas, pose, false);
    _leg(canvas, pose, true);
    _arm(canvas, pose, false);
    _body(canvas, pose);
    _head(canvas, pose);
    _arm(canvas, pose, true);
  }

  Offset _offset(Vector2 v) => Offset(v.x, v.y);

  void _bone(Canvas canvas, Vector2 a, Vector2 b, double width) {
    _limb.strokeWidth = width;
    canvas.drawLine(_offset(a), _offset(b), _limb);
  }

  void _leg(Canvas canvas, CharacterRigPose pose, bool front) {
    final hip = pose[front ? RigJoint.frontHip : RigJoint.backHip];
    final knee = pose[front ? RigJoint.frontKnee : RigJoint.backKnee];
    final ankle = pose[front ? RigJoint.frontAnkle : RigJoint.backAnkle];
    _bone(canvas, hip, knee, pose.height * (front ? 0.054 : 0.050));
    _bone(canvas, knee, ankle, pose.height * (front ? 0.047 : 0.044));
    final heel = pose[front ? RigJoint.frontHeel : RigJoint.backHeel];
    final toe = pose[front ? RigJoint.frontToe : RigJoint.backToe];
    _bone(canvas, heel, toe, pose.height * 0.035);
  }

  void _body(Canvas canvas, CharacterRigPose pose) {
    final neck = pose[RigJoint.neck];
    final pelvis = pose[RigJoint.pelvis];
    final spine = pelvis - neck;
    final length = spine.length / pose.height;
    canvas.save();
    canvas.translate(neck.x, neck.y);
    canvas.rotate(math.atan2(spine.y, spine.x) - math.pi / 2);
    canvas.scale(pose.height * pose.facing, pose.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-0.025, -0.028, 0.058, 0.11),
        const Radius.circular(0.020),
      ),
      _black,
    );
    final bool raincoat = pose.preset == CharacterPreset.raincoat;
    final double hem = raincoat ? 0.055 : 0.018;
    final Path coat = Path()
      ..moveTo(-0.068, 0.060)
      ..quadraticBezierTo(0, 0.025, 0.075, 0.065)
      ..quadraticBezierTo(
        0.065,
        length * 0.6,
        raincoat ? 0.088 : 0.068,
        length + hem,
      )
      ..quadraticBezierTo(
        0,
        length + hem + 0.018,
        raincoat ? -0.094 : -0.065,
        length + hem,
      )
      ..quadraticBezierTo(-0.066, length * 0.5, -0.068, 0.060)
      ..close();
    canvas.drawPath(coat, _cloth);
    if (raincoat) {
      canvas.drawLine(
        const Offset(0.043, 0.08),
        Offset(0.052, length + hem - 0.02),
        _detail,
      );
    } else if (pose.preset == CharacterPreset.satchel) {
      _detail.strokeWidth = 0.012;
      canvas.drawLine(
        const Offset(0.045, 0.075),
        Offset(-0.075, length * 0.8),
        _detail,
      );
      _detail.strokeWidth = 0.006;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-0.12, length * 0.7, 0.09, 0.11),
          const Radius.circular(0.022),
        ),
        _black,
      );
    } else {
      final Path scarf = Path()
        ..moveTo(-0.035, 0.025)
        ..lineTo(-0.10, 0.065)
        ..quadraticBezierTo(
          -0.14,
          0.095,
          -0.17,
          0.075 + math.sin(_clock * 2.1) * 0.015,
        )
        ..lineTo(-0.13, 0.040)
        ..lineTo(-0.025, 0.010)
        ..close();
      canvas.drawPath(scarf, _shade);
    }
    canvas.restore();
  }

  void _head(Canvas canvas, CharacterRigPose pose) {
    final head = pose[RigJoint.head];
    canvas.save();
    canvas.translate(head.x, head.y);
    canvas.rotate(pose.headAngle);
    canvas.scale(pose.height * pose.facing * 0.90, pose.height * 0.90);
    if (pose.preset == CharacterPreset.raincoat) {
      final Path hood = Path()
        ..moveTo(-0.105, 0.13)
        ..quadraticBezierTo(-0.175, 0.03, -0.13, -0.105)
        ..quadraticBezierTo(-0.085, -0.17, 0.055, -0.15)
        ..quadraticBezierTo(0.115, -0.145, 0.15, -0.085)
        ..quadraticBezierTo(0.177, -0.055, 0.142, -0.035)
        ..lineTo(0.115, 0.105)
        ..quadraticBezierTo(0.018, 0.15, -0.105, 0.13)
        ..close();
      canvas.drawPath(hood, _black);
      final opening = Path()
        ..moveTo(0.075, -0.08)
        ..quadraticBezierTo(0.138, -0.07, 0.133, 0.02)
        ..quadraticBezierTo(0.13, 0.09, 0.083, 0.103)
        ..quadraticBezierTo(0.045, 0.025, 0.075, -0.08)
        ..close();
      canvas.drawPath(opening, _shade);
    } else {
      canvas.drawOval(const Rect.fromLTWH(-0.11, -0.12, 0.24, 0.25), _black);
      if (pose.preset == CharacterPreset.scarf) {
        final hair = Path()
          ..moveTo(-0.09, -0.03)
          ..quadraticBezierTo(-0.14, -0.13, -0.01, -0.14)
          ..lineTo(0.075, -0.16)
          ..lineTo(0.045, -0.125)
          ..lineTo(0.125, -0.125)
          ..lineTo(0.10, -0.095)
          ..quadraticBezierTo(0.03, -0.075, -0.09, -0.03)
          ..close();
        canvas.drawPath(hair, _black);
      } else {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTWH(-0.12, -0.14, 0.235, 0.115),
            const Radius.circular(0.075),
          ),
          _black,
        );
        _limb.strokeWidth = 0.025;
        canvas.drawLine(
          const Offset(0.025, -0.035),
          const Offset(0.16, -0.035),
          _limb,
        );
      }
    }
    if (!pose.blink) {
      canvas.drawCircle(
        Offset(pose.preset == CharacterPreset.raincoat ? 0.114 : 0.103, -0.002),
        0.006,
        Paint()..color = const Color(0xFF929292),
      );
    }
    canvas.restore();
  }

  void _arm(Canvas canvas, CharacterRigPose pose, bool front) {
    final shoulder =
        pose[front ? RigJoint.frontShoulder : RigJoint.backShoulder];
    final elbow = pose[front ? RigJoint.frontElbow : RigJoint.backElbow];
    final hand = pose[front ? RigJoint.frontHand : RigJoint.backHand];
    _bone(canvas, shoulder, elbow, pose.height * (front ? 0.038 : 0.034));
    _bone(canvas, elbow, hand, pose.height * 0.029);
    canvas.drawCircle(_offset(hand), pose.height * 0.020, _black);
    if (front &&
        pose.preset == CharacterPreset.raincoat &&
        pose.lanternVisible) {
      canvas.save();
      canvas.translate(hand.x, hand.y);
      canvas.scale(pose.height * pose.facing, pose.height);
      _lantern(canvas, pose.lanternSwing);
      canvas.restore();
    }
  }

  void _lantern(Canvas canvas, double swing) {
    canvas.save();
    canvas.translate(0.025, 0.01);
    canvas.rotate(swing);
    const light = Offset(0, 0.075);
    canvas.drawCircle(
      light,
      0.12,
      Paint()
        ..shader = Gradient.radial(light, 0.12, const [
          Color(0x35FFFFFF),
          Color(0x00FFFFFF),
        ]),
    );
    _limb.strokeWidth = 0.009;
    canvas.drawLine(Offset.zero, const Offset(0, 0.035), _limb);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-0.029, 0.033, 0.058, 0.081),
        const Radius.circular(0.006),
      ),
      _black,
    );
    canvas.drawRect(
      const Rect.fromLTWH(-0.018, 0.045, 0.036, 0.054),
      Paint()..color = const Color(0xFFE3E3E3),
    );
    canvas.drawLine(const Offset(0, 0.041), const Offset(0, 0.102), _limb);
    canvas.restore();
  }
}
