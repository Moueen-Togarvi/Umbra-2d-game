import 'dart:math' as math;

import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../entities/player.dart';
import '../physics/collision_layers.dart';
import '../world/stage.dart';
import 'vampire.dart';

/// What the vampires stand and walk on, found by casting rays into the
/// physics world: the ground, steps, and anything lying on it (a crate, a
/// fallen bookcase). They are not bodies themselves; they read the world.
class _Footing {
  _Footing(this.world);
  final World world;

  static final QueryFilter _solid = QueryFilter(
    categoryBits: CollisionLayers.all,
    maskBits: CollisionLayers.terrain | CollisionLayers.prop,
  );

  /// The highest upward-facing surface at [x] below [from], within [down].
  double? surface(double x, double from, {double down = 7}) {
    double? best;
    double bestFraction = 2;
    world.castRay(Vector2(x, from), Vector2(0, down), filter: _solid, (hit) {
      if (hit.shape.isSensor || hit.normal.y > -0.5) return -1;
      // Only what the boy could stand on too: not a rope's end.
      if (hit.shape.filter.maskBits & CollisionLayers.player == 0) return -1;
      if (hit.fraction < bestFraction) {
        bestFraction = hit.fraction;
        best = hit.point.y;
      }
      return hit.fraction;
    });
    return best;
  }

  /// Whether something solid stands within [reach] of [x] at height [y],
  /// in direction [dir].
  bool blocked(double x, double y, double dir, double reach) {
    var hit = false;
    world.castRay(Vector2(x, y), Vector2(dir * reach, 0), filter: _solid, (h) {
      if (h.shape.isSensor) return -1;
      if (h.shape.filter.maskBits & CollisionLayers.player == 0) return -1;
      hit = true;
      return 0;
    });
    return hit;
  }
}

/// A vampire running the boy down.
///
/// He runs a little slower than the boy can, but he does not stop: he
/// climbs what is in his way (slowly, if it is tall), drops off edges and
/// leaps gaps up to [leap] metres. A wall, a shut gate or a wider gap
/// stops him, and he stands at it reaching. Anything that costs the boy
/// time lets him close in; within reach, he takes him.
class Pursuer {
  Pursuer(
    this.vampire, {
    required this.stage,
    this.speed = 2.8,
    this.leap = 3.2,
    this.catchReach = 0.8,
    this.burnsInLight = false,
  });

  /// Whether light that falls on him burns him (sunlight); otherwise it
  /// only stops him while it lasts (a lightning flash), shielding his face.
  final bool burnsInLight;

  final Vampire vampire;
  final Stage stage;
  double speed;
  final double leap, catchReach;

  bool active = false;

  /// Set once he has the boy.
  bool caught = false;

  /// Set while something stops him (a gap too wide, a wall, a gate).
  bool blocked = false;

  double _feet = 0;
  bool _air = false;
  double _vx = 0, _vy = 0;
  _Footing? _footing;

  /// Starts the chase from where he stands.
  void start() {
    active = true;
    caught = false;
    blocked = false;
    _air = false;
    _feet = vampire.groundY;
    vampire.walkSpeed = speed;
  }

  void stop() => active = false;

  void update(double dt) {
    if (!active || vampire.gone || dt <= 0) return;
    final Player boy = stage.player;
    if (!boy.isMounted) return;
    final footing = _footing ??= _Footing(boy.body.world);
    double x = vampire.x;
    if (stage.isLit(Vector2(x, _feet - 1.5))) {
      if (burnsInLight) {
        vampire.burn();
        active = false;
        return;
      }
      vampire
        ..shieldGoal = 1
        ..drive(x: x, groundY: _feet, dt: dt);
      return;
    }
    vampire.shieldGoal = 0;
    final double dir = boy.isDead
        ? 0
        : (boy.body.position.x - x).abs() < 0.05
        ? 0
        : (boy.body.position.x - x).sign;
    blocked = false;
    if (_air) {
      // Mid-leap, or dropping off an edge: a plain fall.
      x += _vx * dt;
      _vy += GameConfig.gravityMetersPerSecondSquared * dt;
      final double before = _feet;
      _feet += _vy * dt;
      final double? under = footing.surface(x, before - 0.3);
      if (_vy > 0 && under != null && _feet >= under) {
        _feet = under;
        _air = false;
      }
    } else if (dir != 0) {
      // The top of whatever is under him, from above his head.
      final double here = footing.surface(x, _feet - 2.3) ?? _feet;
      if (here > _feet + 0.05) {
        // The ground went from under him.
        _air = true;
        _vx = 0;
        _vy = 0;
      } else if (here < _feet - 0.08) {
        // Still hauling himself up onto it.
        final double rise = _feet - here;
        _feet = math.max(here, _feet - dt * 3.2);
        x += dir * speed * dt * (rise > 0.6 ? 0.2 : 0.6);
      } else {
        _feet = here;
        final double probe = x + dir * 0.45;
        final double? ahead = footing.surface(probe, _feet - 2.3);
        final bool wall =
            footing.blocked(x, _feet - 1.0, dir, 0.5) ||
            footing.blocked(x, _feet - 1.9, dir, 0.5);
        // Taller than he can haul himself over: a wall, a shut gate.
        final bool tall = wall && footing.blocked(x, _feet - 2.25, dir, 0.5);
        if (tall) {
          blocked = true;
        } else if (ahead != null && ahead < _feet - 0.08) {
          // Up onto it, hauling himself, slowed by its height.
          final double rise = _feet - ahead;
          _feet = math.max(ahead, _feet - dt * 3.2);
          x += dir * speed * dt * (rise > 0.6 ? 0.25 : 0.7);
        } else if (ahead == null || ahead > _feet + 1.2) {
          // An edge. Leap to the far side if he can see one in reach.
          double? land;
          double landAt = 0;
          for (double d = 0.8; d <= leap + 0.01; d += 0.1) {
            final double? s = footing.surface(x + dir * d, _feet - 1.5);
            if (s != null && (s - _feet).abs() < 1.0) {
              land = s;
              landAt = d;
              break;
            }
          }
          if (land == null) {
            if (ahead != null && ahead < _feet + 1.6) {
              // A step down: off he goes. (Not into a pit: he would not
              // get out.)
              x += dir * speed * dt;
              _air = true;
              _vx = dir * speed * 0.8;
              _vy = 0;
            } else {
              blocked = true;
            }
          } else {
            final double t = math.max(0.35, landAt / speed);
            _air = true;
            _vx = dir * landAt / t;
            _vy =
                ((land - _feet) -
                    0.5 * GameConfig.gravityMetersPerSecondSquared * t * t) /
                t;
          }
        } else {
          x += dir * speed * dt;
        }
      }
    }
    vampire.drive(x: x, groundY: _feet, dt: dt);
    final double gap = (boy.body.position.x - x).abs();
    vampire.reachGoal = blocked || gap < 2.6 ? 1 : 0.25;
    if (!boy.isDead && !caught) {
      final double boyFeet = boy.body.position.y + GameConfig.playerHeight / 2;
      if (gap < catchReach && (boyFeet - _feet).abs() < 1.3) {
        caught = true;
        active = false;
        vampire.seize();
        boy.die();
      }
    }
  }
}

/// A vampire that keeps to the dark.
///
/// Asleep on his feet until the boy comes within [wake] metres; then he
/// comes for him, but never into light: at its edge he stops and reaches.
/// Caught in light he shields his face and runs for the nearest dark; if
/// there is none between [left] and [right] (or it takes too long), he
/// burns away.
class Stalker {
  Stalker(
    this.vampire, {
    required this.stage,
    required this.ground,
    required this.left,
    required this.right,
    this.speed = 2.1,
    this.wake = 7,
    this.patrolA,
    this.patrolB,
  });

  final Vampire vampire;
  final Stage stage;

  /// The floor under him at x.
  final double Function(double x) ground;
  final double left, right;
  double speed;
  final double wake;

  /// Pacing between these until he wakes, if set.
  final double? patrolA, patrolB;
  double? _goal;

  bool awake = false;
  bool caught = false;
  double _lit = 0;

  bool get burning =>
      vampire.mode == VampireMode.burn ||
      vampire.mode == VampireMode.sink ||
      vampire.gone;

  /// Whether the light falls on him (at the chest or the knees).
  bool litAt(double x) {
    final double g = ground(x);
    return stage.isLit(Vector2(x, g - 1.5)) || stage.isLit(Vector2(x, g - 0.5));
  }

  /// The nearest dark x to [from], going [away] (+1 or -1), between
  /// [left] and [right], or null. He never runs back past the boy and
  /// whatever light he brought.
  double? nearestDark(double from, double away) {
    for (double d = 0.2; d < 14; d += 0.2) {
      final double x = from + away * d;
      if (x < left || x > right) return null;
      if (!litAt(x)) return x;
    }
    return null;
  }

  void _moveTo(double target, double maxSpeed, double dt) {
    final double x = vampire.x;
    final double step = (target - x).clamp(-maxSpeed * dt, maxSpeed * dt);
    vampire.walkSpeed = maxSpeed;
    vampire.drive(x: x + step, groundY: ground(x + step), dt: dt);
  }

  void update(double dt) {
    if (burning || dt <= 0) return;
    final Player boy = stage.player;
    if (!boy.isMounted) return;
    final double x = vampire.x;
    if (litAt(x)) {
      _lit += dt;
      vampire
        ..shieldGoal = 1
        ..reachGoal = 0;
      final double away = boy.body.position.x > x ? -1 : 1;
      final double? dark = nearestDark(x, away);
      if (dark == null || _lit > 2.6) {
        vampire.burn();
        return;
      }
      awake = true;
      // Away from it, faster than the boy can run.
      _moveTo(dark + (dark - x).sign * 0.4, math.max(speed * 1.5, 4.2), dt);
      return;
    }
    _lit = 0;
    vampire.shieldGoal = 0;
    final Vector2 b = boy.body.position;
    final bool boyLit = stage.isLit(b);
    final double boyFeet = b.y + GameConfig.playerHeight / 2;
    // Only for him on its own floor: one above or below it can only watch.
    final bool level = (boyFeet - ground(b.x.clamp(left, right))).abs() < 1.2;
    if (!awake && level && !boy.isDead && (b.x - x).abs() < wake) {
      awake = true;
    }
    if (awake && !level && !boy.isDead) {
      vampire
        ..drive(x: x, groundY: ground(x), dt: dt)
        ..facing = (b.x - x).sign
        ..reachGoal = 0.6;
      return;
    }
    if (!awake || boy.isDead) {
      final double? a = patrolA, c = patrolB;
      if (a != null && c != null) {
        _goal ??= c;
        if ((x - _goal!).abs() < 0.05) _goal = _goal == a ? c : a;
        final double next = x + (_goal! - x).sign * 0.9 * dt;
        if (!litAt(next + (_goal! - x).sign * 0.4)) {
          _moveTo(_goal!, 0.9, dt);
        } else {
          _goal = _goal == a ? c : a;
        }
      } else {
        vampire.drive(x: x, groundY: ground(x), dt: dt);
      }
      vampire.reachGoal = 0;
      return;
    }
    final double target = b.x.clamp(left, right);
    final double dir = (target - x).sign;
    final double next = x + dir * speed * dt;
    // Up to the edge of any light, and no further.
    if (dir != 0 && litAt(next + dir * 0.35)) {
      vampire
        ..drive(x: x, groundY: ground(x), dt: dt)
        ..facing = (b.x - x).sign
        ..reachGoal = (b.x - x).abs() < 3 ? 0.9 : 0.3;
    } else {
      _moveTo(target, speed, dt);
      vampire.reachGoal = (b.x - x).abs() < 2.5 ? 0.8 : 0.2;
    }
    if (!caught &&
        !boyLit &&
        (b.x - vampire.x).abs() < 0.8 &&
        (boyFeet - vampire.groundY).abs() < 1.3) {
      caught = true;
      vampire.seize();
      boy.die();
    }
  }

  /// Back to how he was, at [x] (after a death undid the boy's work).
  void reset(double x) {
    awake = false;
    caught = false;
    _lit = 0;
    _goal = null;
    vampire
      ..revive()
      ..x = x
      ..groundY = ground(x);
  }
}
