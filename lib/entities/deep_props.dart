import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../physics/collision_layers.dart';
import '../render/culling.dart';
import '../world/footprint.dart';
import '../world/stage.dart';
import 'physics_props.dart';
import 'player.dart';

const Color _black = Color(0xFF060606);

/// An iron cage on a chain, its floor a deck he stands on: set going, it
/// is wound up to the gallery above, and stays there.
class CageLift extends BodyComponent with OffScreenCulling {
  CageLift({
    required this.x,
    required this.bottom,
    required this.top,
    this.width = 2.2,
    this.height = 2.3,
  }) : super(renderBody: false, priority: 1);

  /// Its middle, and its deck's top at the bottom and the top of its run.
  final double x, bottom, top, width, height;
  bool rising = false;
  bool _ready = false;
  bool get isReady => _ready && body.isValid;

  /// The deck's top now.
  double get deck => isReady ? body.position.y : bottom;
  bool get isUp => deck <= top + 0.01;

  @override
  Body createBody() {
    final b = world.createBody(
      BodyDef(
        type: BodyType.kinematic,
        position: Vector2(x, bottom),
        userData: this,
      ),
    );
    b.createShape(
      Polygon.offsetBox(width / 2, 0.1, center: Vector2(0, 0.1)),
      ShapeDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        material: SurfaceMaterial(friction: 0.9),
      ),
    );
    _ready = true;
    return b;
  }

  /// Wound up, a little after it is set going.
  void rise() {
    if (rising) return;
    rising = true;
    _wait = 0.6;
    cue('chain', at: Vector2(x, deck));
    cue('gear', weight: 0.7, at: Vector2(x, deck));
  }

  double _wait = 0;

  void reset() => _put(bottom, rising: false);

  /// Already up there (past it, after a death further on).
  void restoreRaised() => _put(top, rising: true);

  void _put(double y, {required bool rising}) {
    this.rising = rising;
    _wait = 0;
    if (!isReady) return;
    body
      ..setTransform(Vector2(x, y), const Rot.identity())
      ..linearVelocity = Vector2.zero();
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isReady || dt <= 0) return;
    if (rising && _wait > 0) {
      _wait -= dt;
      return;
    }
    if (rising && !isUp) {
      body.linearVelocity = Vector2(0, -math.min(1.3, (deck - top) / dt));
    } else {
      body.linearVelocity = Vector2.zero();
    }
  }

  static final Paint _iron = Paint()..color = _black;
  static final Paint _bar = Paint()
    ..color = _black
    ..strokeWidth = 0.05;

  @override
  void render(Canvas canvas) {
    if (!isReady) return;
    final double hw = width / 2;
    // Centred on the deck's top: the deck, its bars, its roof and chain.
    canvas.drawRect(Rect.fromLTRB(-hw, 0, hw, 0.2), _iron);
    canvas.drawRect(Rect.fromLTRB(-hw, -height - 0.1, hw, -height), _iron);
    for (var i = 0; i <= 8; i++) {
      final double bx = -hw + 0.04 + i * (width - 0.08) / 8;
      // The side facing the way out is open.
      if (i == 8) continue;
      canvas.drawLine(Offset(bx, 0), Offset(bx, -height), _bar);
    }
    canvas.drawLine(Offset(0, -height), const Offset(0, -16), _bar);
  }
}

/// Stone teeth in a cave roof that let go as he goes under them: a crack,
/// a shiver, and down. Run under, never stop.
class StalactiteRow extends Component
    with OffScreenCulling
    implements HasFootprint {
  StalactiteRow({
    required this.xs,
    required this.ceiling,
    required this.floor,
    required this.stage,
    this.length = 0.95,
  }) : super(priority: 2);

  final List<double> xs;
  final double ceiling, floor, length;
  final Stage stage;
  late final List<_Tooth> _teeth = [for (final x in xs) _Tooth(x)];

  @override
  Rect get footprint =>
      Rect.fromLTRB(xs.first - 0.4, ceiling, xs.last + 0.4, floor);

  void reset() {
    for (final t in _teeth) {
      t
        ..state = 0
        ..timer = 0
        ..drop = 0
        ..speed = 0;
    }
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    final Player boy = stage.player;
    if (!boy.isMounted) return;
    final Vector2 p = boy.body.position;
    for (final t in _teeth) {
      switch (t.state) {
        case 0:
          final double ahead = t.x - p.x;
          if (!boy.isDead && ahead > -0.3 && ahead < 1.2) {
            t
              ..state = 1
              ..timer = 0.4;
            stage.cue('creak', weight: 0.6, at: Vector2(t.x, ceiling));
          }
        case 1:
          t.timer -= dt;
          if (t.timer <= 0) t.state = 2;
        case 2:
          t.speed += GameConfig.gravityMetersPerSecondSquared * dt;
          t.drop += t.speed * dt;
          final double tip = ceiling + t.drop + length;
          if (!boy.isDead &&
              (t.x - p.x).abs() < 0.32 &&
              tip > p.y - GameConfig.playerHeight / 2 &&
              ceiling + t.drop < p.y + GameConfig.playerHeight / 2) {
            boy.die();
          }
          if (tip >= floor) {
            t.state = 3;
            stage.cue('land', at: Vector2(t.x, floor), shake: 0.2);
          }
      }
    }
  }

  static final Paint _stone = Paint()..color = _black;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint.inflate(1))) return;
    for (final t in _teeth) {
      if (t.state == 3) {
        // Broken on the floor.
        canvas.drawPath(
          Path()
            ..moveTo(t.x - 0.32, floor + 0.02)
            ..lineTo(t.x - 0.1, floor - 0.2)
            ..lineTo(t.x + 0.05, floor - 0.08)
            ..lineTo(t.x + 0.22, floor - 0.16)
            ..lineTo(t.x + 0.34, floor + 0.02)
            ..close(),
          _stone,
        );
        continue;
      }
      final double shiver = t.state == 1 ? math.sin(t.timer * 90) * 0.03 : 0;
      final double y = ceiling + t.drop;
      canvas.drawPath(
        Path()
          ..moveTo(t.x - 0.2 + shiver, y - 0.05)
          ..lineTo(t.x + 0.2 + shiver, y - 0.05)
          ..lineTo(t.x + 0.03 + shiver, y + length)
          ..close(),
        _stone,
      );
    }
  }
}

class _Tooth {
  _Tooth(this.x);
  final double x;

  /// 0 hanging, 1 cracking, 2 falling, 3 down.
  int state = 0;
  double timer = 0, drop = 0, speed = 0;
}

/// The roof coming down behind him, stone after stone, faster than a walk:
/// he runs, and does not stop until it does.
class Collapse extends Component with OffScreenCulling implements HasFootprint {
  Collapse({
    required this.from,
    required this.to,
    required this.ceiling,
    required this.floor,
    required this.stage,
    this.speed = 2.7,
    this.flames = false,
    this.boulder = false,
  }) : super(priority: 3);

  /// A great stone ball rolling after him, not the roof coming down.
  final bool boulder;
  static const double _ball = 1.5;

  final double from, to, ceiling, floor, speed;

  /// Fire coming along the floor behind him, not the roof coming down.
  final bool flames;
  final Stage stage;
  bool active = false;
  late double front = from;
  double _rumble = 0, _time = 0;
  final math.Random _random = math.Random(4);
  final List<_Stone> _stones = [];

  @override
  Rect get footprint => Rect.fromLTRB(from, ceiling, to, floor);

  void reset() {
    active = false;
    front = from;
    _stones.clear();
  }

  void start() {
    if (active || front > from) return;
    active = true;
    stage.cue(
      flames ? 'fire' : 'rumble',
      at: Vector2(from, ceiling),
      shake: 0.4,
    );
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    for (final s in _stones) {
      s.v += GameConfig.gravityMetersPerSecondSquared * dt;
      s.y = math.min(floor - 0.15, s.y + s.v * dt);
    }
    if (!active) return;
    front = math.min(to, front + speed * dt);
    _rumble -= dt;
    if (_rumble <= 0) {
      _rumble = 0.9;
      stage.cue(
        flames ? 'fire' : 'rumble',
        weight: 0.7,
        at: Vector2(front, ceiling),
        shake: flames ? 0 : 0.3,
      );
    }
    if (!flames &&
        !boulder &&
        _stones.length < 90 &&
        _random.nextDouble() < dt * 14) {
      _stones.add(_Stone(front - _random.nextDouble() * 0.8, ceiling));
    }
    final Player boy = stage.player;
    final double edge = boulder ? front + _ball : front + 0.1;
    if (boy.isMounted && !boy.isDead && boy.body.position.x < edge) {
      boy.die();
    }
    if (front >= to) active = false;
  }

  static final Paint _stone = Paint()..color = _black;

  static final Paint _flameOuter = Paint()..color = const Color(0xA8E07A30);
  static final Paint _flameInner = Paint()..color = const Color(0xE0FFD890);
  static final Paint _char = Paint()..color = const Color(0xFF050404);

  void _renderFire(Canvas canvas) {
    // Charred floor behind, and a wall of flame at the front, licking.
    canvas.drawRect(
      Rect.fromLTRB(from, floor - 0.05, front, floor + 0.05),
      _char,
    );
    for (double x = math.max(from, front - 6); x <= front; x += 0.35) {
      final double near = 1 - (front - x) / 6;
      final double h =
          (0.6 + 1.6 * near) * (0.75 + 0.25 * math.sin(_time * 9 + x * 3.1));
      for (final (paint, k) in [(_flameOuter, 1.0), (_flameInner, 0.5)]) {
        canvas.drawPath(
          Path()
            ..moveTo(x - 0.3 * k, floor)
            ..quadraticBezierTo(
              x - 0.1,
              floor - h * k * 0.6,
              x + 0.05 * math.sin(_time * 7 + x),
              floor - h * k,
            )
            ..quadraticBezierTo(
              x + 0.1,
              floor - h * k * 0.6,
              x + 0.3 * k,
              floor,
            )
            ..close(),
          paint,
        );
      }
    }
  }

  @override
  void render(Canvas canvas) {
    if (front <= from || !isOnScreen(footprint)) return;
    if (flames) {
      _renderFire(canvas);
      return;
    }
    if (boulder) {
      canvas.save();
      canvas.translate(front, floor - _ball);
      canvas.rotate((front - from) / _ball);
      canvas.drawCircle(Offset.zero, _ball, _stone);
      final crack = Paint()
        ..color = const Color(0x40C8C0B0)
        ..strokeWidth = 0.05
        ..style = PaintingStyle.stroke;
      canvas.drawArc(
        Rect.fromCircle(center: Offset.zero, radius: _ball * 0.7),
        0.4,
        1.6,
        false,
        crack,
      );
      canvas.drawLine(const Offset(-0.5, 0.3), const Offset(0.4, 0.9), crack);
      canvas.restore();
      return;
    }
    // Behind the front the way is choked: a slope of rubble up to the roof.
    canvas.drawPath(
      Path()
        ..moveTo(from, floor + 0.05)
        ..lineTo(from, ceiling)
        ..lineTo(math.max(from, front - 1.2), ceiling)
        ..lineTo(front, floor - 0.4)
        ..lineTo(front + 0.3, floor + 0.05)
        ..close(),
      _stone,
    );
    for (final (i, s) in _stones.indexed) {
      final double r = 0.12 + (i % 5) * 0.05;
      canvas.save();
      canvas.translate(s.x, s.y);
      canvas.rotate(_time * (i.isEven ? 3 : -2));
      canvas.drawRect(Rect.fromLTRB(-r, -r * 0.8, r, r * 0.8), _stone);
      canvas.restore();
    }
  }
}

class _Stone {
  _Stone(this.x, this.y);
  final double x;
  double y, v = 0;
}

/// A mark painted beside a cord, or a row of them on a gate: which to
/// pull, and in what order.
class Sign extends Component implements HasFootprint {
  Sign({required this.at, required this.marks, this.size = 0.32})
    : super(priority: -2);

  final Vector2 at;

  /// 0 a ring, 1 a triangle, 2 a bar, left to right.
  final List<int> marks;
  final double size;

  @override
  Rect get footprint => Rect.fromLTWH(
    at.x - 0.2,
    at.y - size,
    marks.length * size * 1.4 + 0.4,
    size * 2,
  );

  static final Paint _board = Paint()..color = const Color(0xFF0C0C0C);
  static final Paint _chalk = Paint()
    ..color = const Color(0xAAD8D4C8)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.035;

  @override
  void render(Canvas canvas) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(footprint, const Radius.circular(0.05)),
      _board,
    );
    for (final (i, m) in marks.indexed) {
      final Offset c = Offset(at.x + size * 0.5 + i * size * 1.4, at.y);
      final double r = size * 0.42;
      switch (m) {
        case 0:
          canvas.drawCircle(c, r, _chalk);
        case 1:
          canvas.drawPath(
            Path()
              ..moveTo(c.dx, c.dy - r)
              ..lineTo(c.dx + r, c.dy + r * 0.8)
              ..lineTo(c.dx - r, c.dy + r * 0.8)
              ..close(),
            _chalk,
          );
        default:
          canvas.drawLine(c - Offset(r, 0), c + Offset(r, 0), _chalk);
          canvas.drawLine(c - Offset(0, r), c + Offset(0, r), _chalk);
      }
    }
  }
}

/// A rope with fire at its top: taken hold of, it burns down, and soon
/// there is no rope. Across quickly, or down with it.
class BurningRope extends SwingRope {
  BurningRope({required super.anchor, required super.length, this.lasts = 1.9})
    : super(support: RopeSupport.ring);

  /// Seconds it holds once he is on it.
  final double lasts;
  double burning = 0;
  bool burnt = false;
  Stage? _stage;

  @override
  bool get isReady => !burnt && super.isReady;

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    _stage = ancestors().whereType<Stage>().firstOrNull;
  }

  void reset() {
    burnt = false;
    burning = 0;
  }

  @override
  void update(double dt) {
    super.update(dt);
    final Player? boy = _stage?.player;
    if (burnt || boy == null || !boy.isMounted) return;
    if (boy.interactions.attachedRope == this || burning > 0) {
      if (burning == 0) cue('fire', at: anchor);
      burning += dt;
      if (burning >= lasts) {
        burnt = true;
        cue('rope', at: anchor);
        if (boy.interactions.attachedRope == this) boy.interactions.release();
      }
    }
  }

  static final Paint _flame = Paint()..color = const Color(0xD8F0A050);

  @override
  void render(Canvas canvas) {
    if (burnt) return;
    super.render(canvas);
    if (burning <= 0) return;
    // The fire coming down it.
    final double down = length * (burning / lasts);
    final Vector2 at = pointAt(down) - anchor;
    final double f = 0.12 + 0.05 * math.sin(burning * 30);
    canvas.drawOval(
      Rect.fromCenter(center: at.toOffset(), width: f * 1.6, height: f * 3),
      _flame,
    );
  }
}
