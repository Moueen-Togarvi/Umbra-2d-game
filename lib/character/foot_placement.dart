import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';

import 'character_rig.dart' show CharacterRig, Gait;
import 'ground_probe.dart';

/// Stance feet are stored in their support body's local coordinates. They stay
/// planted when the root accelerates and travel with a moving support.
///
/// The timing comes from [Gait], the same as the rig's: each foot is planted
/// for a stance fraction of the cycle and swings through the rest, kicking
/// the heel up behind the body before it reaches for the next contact.
///
/// A foot always stands on real, visible ground: on an earth bank that is the
/// drawn edge, not the collision line under it, and where the next step
/// would land over a gap the foot comes back onto the lip instead of
/// treading air. Each foot also reports the surface normal under it and how
/// far it has rolled: heel first at contact, flat, then up onto the toes.
class FootPlacement {
  final List<_Foot> _feet = [_Foot(), _Foot()];
  double _facing = 1;
  double _travelDirection = 1;
  bool _wasGrounded = false;
  int _stance = 0;

  /// Idle stance, as fractions of height ahead of the centre: one foot a
  /// little forward, one a little back, the way a child stands.
  static const double idleFront = 0.07, idleBack = -0.06;

  /// The stances he shifts between while standing about, the first being
  /// [idleFront] and [idleBack].
  static const List<(double, double)> _stances = [
    (idleFront, idleBack),
    (0.035, -0.09),
    (0.10, -0.035),
  ];

  /// A step in place (settling after a stop, or shifting his feet) takes
  /// this long and lifts the foot this far, as a fraction of height.
  static const double stepSeconds = 0.2, stepLift = 0.035;

  /// Shifts to another standing stance: the feet step there one at a time.
  void shiftStance() => _stance = (_stance + 1) % _stances.length;

  /// Whether a foot is stepping in place right now.
  bool get stepping => _feet.any((foot) => foot.stepping);

  /// Front foot first, then back foot, in world metres: where the sole
  /// touches (or, swinging, would touch) the ground.
  List<Vector2> get targets => [
    for (final foot in _feet) foot.position.clone(),
  ];

  /// Whether each foot is currently planted rather than swinging.
  List<bool> get planted => [for (final foot in _feet) foot.wasStance];

  /// What each foot stands on (null for the ground found by a probe, or a
  /// foot in the air).
  List<Body?> get supports => [for (final foot in _feet) foot.support];

  /// The ground normal under each foot, world space, pointing up.
  List<Vector2> get normals => [for (final foot in _feet) foot.normal.clone()];

  /// How far each foot has rolled, radians: positive lifts the toe (heel
  /// strike), negative lifts the heel (push-off).
  List<double> get rolls => [for (final foot in _feet) foot.roll];

  void reset() {
    _wasGrounded = false;
    for (final foot in _feet) {
      foot.support = null;
      foot.initialized = false;
      foot.stepping = false;
      foot.spotFor = double.nan;
      foot.roll = 0;
      foot.normal.setValues(0, -1);
    }
  }

  void update({
    required Forge2DWorld world,
    required Body body,
    required double height,
    required double phase,
    required double gait,
    required double facing,
    required bool grounded,
    required double speed,
    required double dt,
    bool bracing = false,
    bool sliding = false,
    double low = 0,
  }) {
    if (!grounded) {
      reset();
      return;
    }
    if (sliding) {
      // Sliding on his feet: both soles stay on the ground and travel with
      // him, the front foot a little ahead down the slope.
      _facing = facing;
      _wasGrounded = true;
      final soleY = body.position.y + height / 2;
      for (var i = 0; i < _feet.length; i++) {
        final foot = _feet[i];
        _plant(
          world,
          body,
          foot,
          body.position.x + (i == 0 ? 0.06 : -0.05) * height * facing,
          soleY,
          height,
        );
        foot.stepping = false;
        foot.wasStance = true;
        foot.roll = 0;
        foot.swingFrom = foot.position.x - body.position.x;
      }
      return;
    }
    final moving = speed.abs() > 0.12;
    final travelDirection = moving ? speed.sign : facing;
    if (!_wasGrounded ||
        facing != _facing ||
        (moving && travelDirection != _travelDirection)) {
      reset();
    }
    _facing = facing;
    _travelDirection = travelDirection;
    _wasGrounded = true;
    final bool backwards = moving && travelDirection != facing;
    final root = body.position;
    final soleY = root.y + height / 2;
    final stanceFraction = Gait.stanceFraction(gait);
    final reach = Gait.reachMeters(speed, gait) * strideScale(bracing, low);
    // Leaning on a crate, the short steps land a little behind the hips,
    // so the legs drive the body into it instead of stepping in under it.
    final double land = reach - (bracing ? height * 0.04 : 0);
    double idleXOf(int i) =>
        root.x +
        (i == 0 ? _stances[_stance].$1 : _stances[_stance].$2) *
            height *
            facing;
    if (moving) {
      for (final foot in _feet) {
        foot.stepping = false;
      }
    } else if (!stepping) {
      // Standing, the foot furthest from where it should stand steps
      // there: a real little step, not a slide.
      int? worst;
      var worstError = 0.025;
      for (var i = 0; i < _feet.length; i++) {
        final foot = _feet[i];
        if (!foot.initialized || !foot.wasStance) continue;
        // Compared with where the foot can actually stand: at a lip its
        // usual spot may be over the drop.
        final double idleX = idleXOf(i);
        if ((foot.spotFor - idleX).abs() > 0.01) {
          foot.spotFor = idleX;
          foot.spotX = _findSpot(world, body, idleX, soleY, height).$1;
        }
        final error = (foot.position.x - foot.spotX).abs();
        if (error > worstError) {
          worst = i;
          worstError = error;
        }
      }
      if (worst != null) {
        final foot = _feet[worst];
        foot.stepFrom.setFrom(foot.position);
        _plant(world, body, foot, idleXOf(worst), soleY, height);
        foot.stepTo.setFrom(foot.position);
        foot.position.setFrom(foot.stepFrom);
        foot.stepTime = 0;
        foot.stepping = true;
      }
    }
    for (var i = 0; i < _feet.length; i++) {
      final foot = _feet[i];
      final cycle = (phase / (math.pi * 2) + i * 0.5) % 1;
      final stance = !moving || cycle < stanceFraction;
      final idleX = idleXOf(i);
      if (foot.stepping) {
        foot.stepTime += dt;
        final double t = math.min(1, foot.stepTime / stepSeconds);
        if (t >= 1) {
          foot.stepping = false;
          foot.position.setFrom(
            (foot.support?.isValid ?? false)
                ? foot.support!.worldPoint(foot.localAnchor)
                : foot.stepTo,
          );
          foot.roll = 0;
          foot.wasStance = true;
        } else {
          final double s = _smooth(t);
          foot.position
            ..setFrom(foot.stepFrom + (foot.stepTo - foot.stepFrom) * s)
            ..y -= math.sin(math.pi * t) * stepLift * height;
          // The heel comes up first, and the foot is put down flat.
          foot.roll = -0.35 * math.sin(math.pi * t) * (1 - t);
          foot.wasStance = false;
        }
        continue;
      }
      if (!foot.initialized) {
        final x = moving
            ? root.x +
                  travelDirection *
                      reach *
                      (1 - 2 * (cycle / stanceFraction).clamp(0.0, 1.0))
            : idleX;
        _plant(world, body, foot, x, soleY, height);
        foot.wasStance = stance;
        foot.swingFrom = foot.position.x - root.x;
      }
      if (stance) {
        if (!foot.wasStance && !moving) {
          // Still swinging when he stops: the foot steps down where it is,
          // from where it is in the air, and settles into place from there.
          foot.stepFrom.setFrom(foot.position);
          _plant(world, body, foot, foot.position.x, soleY, height);
          foot.stepTo.setFrom(foot.position);
          foot.position.setFrom(foot.stepFrom);
          foot.stepTime = 0;
          foot.stepping = true;
          foot.wasStance = false;
          continue;
        } else if (!foot.wasStance) {
          _plant(
            world,
            body,
            foot,
            root.x + travelDirection * land,
            soleY,
            height,
          );
        } else if (foot.support?.isValid ?? false) {
          foot.position.setFrom(foot.support!.worldPoint(foot.localAnchor));
        }
        if ((foot.position.x - root.x).abs() > height * 0.32 ||
            (foot.position.y - soleY).abs() > height * 0.3) {
          _plant(world, body, foot, idleX, soleY, height);
        }
        // Heel strike, flat foot, then up onto the toes before toe-off.
        final t = moving ? cycle / stanceFraction : 0.5;
        // Walking backwards (dragging a crate), the toes land first and
        // the heel comes up last: the roll runs the other way.
        foot.roll = gait * _stanceRoll(t) * (backwards ? -1 : 1);
      } else {
        // A swinging foot travels with the body: it starts where it left
        // the ground relative to the hips, trails behind with the heel kicked
        // up, then sweeps through to land a stride's reach ahead.
        if (foot.wasStance) foot.swingFrom = foot.position.x - root.x;
        final t = (cycle - stanceFraction) / (1 - stanceFraction);
        // Creeping low, the foot is carried straight through, close to the
        // ground: no heel kicked up behind.
        final double progress =
            Gait.swingProgress(t) + (_smooth(t) - Gait.swingProgress(t)) * low;
        final x =
            root.x +
            foot.swingFrom +
            (travelDirection * land - foot.swingFrom) * progress;
        final hit = _surface(world, body, x, soleY, height);
        foot.position.setValues(
          x,
          (hit?.point.y ?? soleY) -
              Gait.swingLift(t, gait) *
                  height *
                  (backwards ? 0.6 : 1) *
                  (1 - 0.55 * low),
        );
        foot.normal.setValues(0, -1);
        foot.support = null;
        // Toes trail down after push-off and come up for the next heel
        // strike.
        foot.roll = gait * (-0.8 + 1.12 * _smooth(t)) * (backwards ? -0.5 : 1);
      }
      foot.wasStance = stance;
    }
  }

  /// Steps are shorter, and so quicker, while leaning on a crate, and
  /// creeping low ([low] 1).
  static double strideScale(bool bracing, [double low = 0]) =>
      (bracing ? 0.7 : 1) * (1 - 0.25 * low);

  static double _smooth(double t) {
    final double x = t.clamp(0.0, 1.0);
    return x * x * (3 - 2 * x);
  }

  static double _stanceRoll(double t) {
    if (t < 0.15) return 0.32 * (1 - t / 0.15);
    if (t > 0.55) return -0.8 * math.pow((t - 0.55) / 0.45, 1.4).toDouble();
    return 0;
  }

  /// Puts [foot] on the ground near [x]. Where the whole foot would not be
  /// on the ground — the step would land over a pit, or with its toes or
  /// heel over the lip — it comes back towards the body, a few centimetres
  /// at a time, until heel and toe both stand on it.
  void _plant(
    Forge2DWorld world,
    Body body,
    _Foot foot,
    double x,
    double soleY,
    double height,
  ) {
    final (double spot, GroundContact? hit) = _findSpot(
      world,
      body,
      x,
      soleY,
      height,
    );
    foot.position.setFrom(hit?.point ?? Vector2(spot, soleY));
    foot.normal.setFrom(hit?.normal ?? Vector2(0, -1));
    foot.support = hit?.body;
    if (foot.support != null) {
      foot.localAnchor.setFrom(foot.support!.localPoint(foot.position));
    }
    foot.initialized = true;
  }

  /// The nearest place to [x] a foot can stand, and the ground there.
  (double, GroundContact?) _findSpot(
    Forge2DWorld world,
    Body body,
    double x,
    double soleY,
    double height,
  ) {
    // The nearest spot where the whole foot stands, looking back towards
    // the body first — though the body itself may be over the gap when the
    // capsule rests on the lip, so the other way too.
    final double toward = x == body.position.x
        ? -_travelDirection
        : (body.position.x - x).sign;
    GroundContact? hit = _wholeFoot(world, body, x, soleY, height);
    final double wanted = x;
    for (var tries = 1; hit == null && tries <= 16; tries++) {
      for (final direction in [toward, -toward]) {
        final double candidate = wanted + direction * tries * 0.03;
        hit = _wholeFoot(world, body, candidate, soleY, height);
        if (hit != null) {
          x = candidate;
          break;
        }
      }
    }
    // Nowhere for the whole foot: at least the sole, back towards the body.
    for (var tries = 0; hit == null && tries <= 16; tries++) {
      x = wanted + toward * tries * 0.03;
      hit = _surface(world, body, x, soleY, height);
    }
    return (x, hit);
  }

  /// The ground under the sole at [x], if there is ground under the heel
  /// and the toe too, at about the same height.
  GroundContact? _wholeFoot(
    Forge2DWorld world,
    Body body,
    double x,
    double soleY,
    double height,
  ) {
    final hit = _surface(world, body, x, soleY, height);
    if (hit == null) return null;
    for (final reach in [
      CharacterRig.toeReach * height * _facing,
      -CharacterRig.heelReach * height * _facing,
    ]) {
      final end = _surface(world, body, x + reach, soleY, height);
      if (end == null || (end.point.y - hit.point.y).abs() > 0.08) return null;
    }
    return hit;
  }

  GroundContact? _surface(
    Forge2DWorld world,
    Body body,
    double x,
    double soleY,
    double height,
  ) =>
      probeGround(world, x, soleY - height * 0.25, height * 0.45, ignore: body);
}

class _Foot {
  final position = Vector2.zero();
  final localAnchor = Vector2.zero();
  final normal = Vector2(0, -1);
  double roll = 0;

  /// Where the foot left the ground, relative to the hips.
  double swingFrom = 0;
  Body? support;
  bool initialized = false;
  bool wasStance = false;

  /// A step in place, from [stepFrom] to [stepTo].
  bool stepping = false;
  double stepTime = 0;

  /// Where the foot can actually stand nearest its standing spot, and the
  /// spot that was for.
  double spotX = double.nan, spotFor = double.nan;
  final stepFrom = Vector2.zero();
  final stepTo = Vector2.zero();
}
