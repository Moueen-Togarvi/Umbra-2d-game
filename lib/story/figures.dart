import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/flame.dart';

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

/// The approved reaching portrait, with only its near arm articulated.
/// The gesture runs once per mother instance, then rests with her arm down.
class Mother {
  double presence = 0;
  double reach = 0;
  double grief = 0;

  final Calm _presence = Calm(0, hertz: 0.7);
  double? _gestureTime;
  static const double height = 1.48;
  static Image? _sharedArt;
  Image? _art;
  final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  // Coordinates in the portrait's authored display space. The cut follows
  // the skin at the shoulder; both draws use the same source pixels.
  static const _portrait = Rect.fromLTWH(0, 0, 1188, 1288);
  static const _shoulder = Offset(658, 306);
  static final Path _arm = Path()
    ..moveTo(660, 258)
    ..cubicTo(625, 270, 615, 335, 675, 354)
    ..lineTo(790, 380)
    ..lineTo(1170, 380)
    ..lineTo(1170, 80)
    ..lineTo(980, 80)
    ..lineTo(980, 220)
    ..lineTo(760, 250)
    ..close();
  static final Path _body = Path.combine(
    PathOperation.difference,
    Path()..addRect(_portrait),
    _arm,
  );

  bool get visible => _presence.value > 0.01;
  bool get hasArtwork => _art != null;
  bool get gestureComplete => (_gestureTime ?? 0) >= 3.55;

  /// One smooth lift, a short hold, then one lowering. Never loops, even
  /// when the cutscene leaves reach enabled or sends a second request.
  double get reachProgress {
    final t = _gestureTime;
    if (t == null || t >= 3.55) return 0;
    double ease(double x) => x * x * (3 - 2 * x);
    if (t < .85) return ease(t / .85);
    if (t <= 2.55) return 1;
    return 1 - ease((t - 2.55) / 1.0);
  }

  Future<void> load() async {
    _art = _sharedArt ??= await Flame.images.load(
      'characters/mother_reference.png',
    );
  }

  void update(double dt) {
    if (dt <= 0) return;
    _presence.step(presence, dt);
    if (_gestureTime == null && reach > 0) _gestureTime = 0;
    if (_gestureTime != null) {
      _gestureTime = math.min(3.55, _gestureTime! + dt);
    }
  }

  void render(Canvas canvas, Rect door) {
    final art = _art;
    if (!visible || art == null) return;
    final p = _presence.value;
    final x = door.left - .3 + (door.center.dx - .05 - door.left + .3) * p;
    final source = Rect.fromLTWH(
      0,
      0,
      art.width.toDouble(),
      art.height.toDouble(),
    );
    const scale = height / (1280 - 62);
    void placePortrait() {
      canvas.translate(x, door.bottom);
      canvas.scale(scale);
      canvas.translate(-620, -1280);
    }

    canvas.save();
    canvas.clipRect(door.inflate(.005));
    placePortrait();
    canvas.clipPath(_body);
    canvas.drawImageRect(art, source, _portrait, _paint);
    canvas.restore();

    // Keep the original shoulder cap under the rotating arm so lowering
    // cannot expose a transparent seam at its attachment.
    canvas.save();
    placePortrait();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: _shoulder, radius: 39)),
    );
    canvas.drawImageRect(art, source, _portrait, _paint);
    canvas.restore();

    canvas.save();
    placePortrait();
    canvas.translate(_shoulder.dx, _shoulder.dy);
    canvas.rotate((1 - reachProgress) * 1.27);
    canvas.translate(-_shoulder.dx, -_shoulder.dy);
    canvas.clipPath(_arm);
    canvas.drawImageRect(art, source, _portrait, _paint);
    canvas.restore();
  }
}
