import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';

import '../physics/collision_layers.dart';

/// Stance feet are stored in their support body's local coordinates. They stay
/// planted when the root accelerates and travel with a moving support.
class FootPlacement {
  final List<_Foot> _feet = [_Foot(), _Foot()];
  double _facing = 1;
  double _travelDirection = 1;
  bool _wasGrounded = false;

  List<Vector2> get targets => [
    for (final foot in _feet) foot.position.clone(),
  ];

  void reset() {
    _wasGrounded = false;
    for (final foot in _feet) {
      foot.support = null;
      foot.initialized = false;
    }
  }

  void update({
    required Forge2DWorld world,
    required Body body,
    required double height,
    required double phase,
    required double stride,
    required double facing,
    required bool grounded,
    required double speed,
    required double dt,
  }) {
    if (!grounded) {
      reset();
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
    final root = body.position;
    final soleY = root.y + height / 2;
    for (var i = 0; i < _feet.length; i++) {
      final foot = _feet[i];
      final cycle = (phase / (math.pi * 2) + i * 0.5) % 1;
      final stance = !moving || cycle < 0.5;
      final reach = stride / 4;
      final idleX = root.x + (i == 0 ? 0.055 : -0.055) * height * facing;
      if (!foot.initialized) {
        final x = moving
            ? root.x + travelDirection * reach * (1 - 4 * cycle.clamp(0.0, 0.5))
            : idleX;
        _plant(world, body, foot, x, soleY, height);
        foot.wasStance = stance;
        foot.swingStart.setFrom(foot.position);
      }
      if (stance) {
        if (!foot.wasStance) {
          _plant(
            world,
            body,
            foot,
            root.x + travelDirection * reach,
            soleY,
            height,
          );
        } else if (foot.support?.isValid ?? false) {
          foot.position.setFrom(foot.support!.worldPoint(foot.localAnchor));
        }
        // Settle a final step after braking, without tying a planted foot to
        // every millimetre of root motion during the gait.
        if (!moving && (foot.position.x - idleX).abs() > 0.025) {
          final x =
              foot.position.x +
              (idleX - foot.position.x) * (1 - math.exp(-9 * dt));
          _plant(world, body, foot, x, soleY, height);
        }
        if ((foot.position.x - root.x).abs() > height * 0.32 ||
            (foot.position.y - soleY).abs() > height * 0.3) {
          _plant(world, body, foot, idleX, soleY, height);
        }
      } else {
        if (foot.wasStance) foot.swingStart.setFrom(foot.position);
        final t = (cycle - 0.5) * 2;
        final eased = t * t * (3 - 2 * t);
        final landingX = root.x + travelDirection * reach;
        final hit = _surface(world, body, landingX, soleY, height);
        final landing = hit?.point ?? Vector2(landingX, soleY);
        foot.position.setFrom(
          foot.swingStart + (landing - foot.swingStart) * eased,
        );
        foot.position.y -= math.sin(t * math.pi) * height * 0.12;
        foot.support = null;
      }
      foot.wasStance = stance;
    }
  }

  void _plant(
    Forge2DWorld world,
    Body body,
    _Foot foot,
    double x,
    double soleY,
    double height,
  ) {
    final hit = _surface(world, body, x, soleY, height);
    foot.position.setFrom(hit?.point ?? Vector2(x, soleY));
    foot.support = hit?.shape.body;
    if (foot.support != null) {
      foot.localAnchor.setFrom(foot.support!.localPoint(foot.position));
    }
    foot.initialized = true;
  }

  RayHit? _surface(
    Forge2DWorld world,
    Body body,
    double x,
    double soleY,
    double height,
  ) {
    RayHit? result;
    world.castRay(
      Vector2(x, soleY - height * 0.25),
      Vector2(0, height * 0.45),
      (hit) {
        if (hit.shape.body == body ||
            hit.shape.isSensor ||
            hit.normal.y > -0.6) {
          return -1;
        }
        result = hit;
        return hit.fraction;
      },
      filter: QueryFilter(maskBits: CollisionLayers.solid),
    );
    return result;
  }
}

class _Foot {
  final position = Vector2.zero();
  final localAnchor = Vector2.zero();
  final swingStart = Vector2.zero();
  Body? support;
  bool initialized = false;
  bool wasStance = false;
}
