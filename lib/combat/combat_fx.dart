import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

/// Short-lived marks of a fight, in world metres: the pale crescent a cut
/// leaves in the air, and the sparks where it lands. Each lasts a fraction
/// of a second, so the picture stays black and grey between blows.
class CombatFx extends Component {
  CombatFx() : super(priority: 6);

  final List<_Slash> _slashes = [];
  final List<_Spark> _sparks = [];
  final math.Random _random = math.Random(11);
  final Paint _arc = Paint();
  final Paint _streak = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static const double slashSeconds = .16;
  static const double sparkSeconds = .28;

  /// A crescent from [from] to [to] radians around [centre], [radius] out:
  /// angles measured as on screen (0 ahead, positive downwards), mirrored
  /// by [facing].
  void slash(Vector2 centre, double facing, double radius, double from, double to) {
    _slashes.add(_Slash(centre.clone(), facing, radius, from, to));
  }

  /// A burst of streaks at [at], thrown mostly along [direction].
  void sparks(Vector2 at, double direction, {int count = 10}) {
    for (var i = 0; i < count; i++) {
      final angle = (_random.nextDouble() - .5) * 2.2;
      final speed = 3 + _random.nextDouble() * 5;
      _sparks.add(
        _Spark(
          at.clone(),
          Vector2(
            direction * math.cos(angle) * speed,
            math.sin(angle) * speed - 1.2,
          ),
          .5 + _random.nextDouble() * .5,
        ),
      );
    }
  }

  bool get isQuiet => _slashes.isEmpty && _sparks.isEmpty;

  @override
  void update(double dt) {
    super.update(dt);
    for (final s in _slashes) {
      s.age += dt;
    }
    _slashes.removeWhere((s) => s.age >= slashSeconds);
    for (final s in _sparks) {
      s.age += dt;
      s.position += s.velocity * dt;
      s.velocity
        ..scale(math.pow(.02, dt).toDouble())
        ..y += 9 * dt;
    }
    _sparks.removeWhere((s) => s.age >= sparkSeconds * s.life);
  }

  @override
  void render(Canvas canvas) {
    for (final s in _slashes) {
      final t = (s.age / slashSeconds).clamp(0.0, 1.0);
      // The blade's path draws on fast, then thins away from its tail.
      final head = Curves.easeOut(math.min(1, t * 2.4));
      final tail = Curves.easeIn(t);
      final a0 = s.from + (s.to - s.from) * tail;
      final a1 = s.from + (s.to - s.from) * head;
      if ((a1 - a0).abs() < .02) continue;
      _arc.color = Color.fromRGBO(242, 242, 236, .85 * (1 - t));
      canvas.drawPath(_crescent(s, a0, a1), _arc);
    }
    for (final s in _sparks) {
      final t = (s.age / (sparkSeconds * s.life)).clamp(0.0, 1.0);
      _streak
        ..strokeWidth = .035 * (1 - t) + .01
        ..color = Color.fromRGBO(250, 250, 245, 1 - t);
      final tail = s.position - s.velocity * .025;
      canvas.drawLine(
        Offset(tail.x, tail.y),
        Offset(s.position.x, s.position.y),
        _streak,
      );
    }
  }

  /// A blade-shaped band: thick in the middle of the sweep, pointed at both
  /// ends, the outer edge a true circle and the inner one pulled in.
  Path _crescent(_Slash s, double a0, double a1) {
    const steps = 18;
    final outer = <Offset>[];
    final inner = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final u = i / steps;
      final a = a0 + (a1 - a0) * u;
      final thick = math.sin(u * math.pi) * .26;
      Offset at(double r) => Offset(
        s.centre.x + s.facing * math.cos(a) * r,
        s.centre.y + math.sin(a) * r,
      );
      outer.add(at(s.radius));
      inner.add(at(s.radius - thick));
    }
    final path = Path()..moveTo(outer.first.dx, outer.first.dy);
    for (final p in outer.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in inner.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    return path..close();
  }
}

class _Slash {
  _Slash(this.centre, this.facing, this.radius, this.from, this.to);
  final Vector2 centre;
  final double facing, radius, from, to;
  double age = 0;
}

class _Spark {
  _Spark(this.position, this.velocity, this.life);
  Vector2 position, velocity;
  final double life;
  double age = 0;
}

/// Easing for the effects without pulling in Flutter's animation library.
abstract final class Curves {
  static double easeOut(double t) => 1 - (1 - t) * (1 - t);
  static double easeIn(double t) => t * t;
}
