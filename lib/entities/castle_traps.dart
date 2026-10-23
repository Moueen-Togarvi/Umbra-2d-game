import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart' hide World;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../physics/collision_layers.dart';
import '../render/culling.dart';
import '../world/footprint.dart';
import '../world/stage.dart';
import 'player.dart';

const Color _black = Color(0xFF060606);

/// How a row of timed hazards looks: a stone dropping from the roof, a
/// hand out of a coffin in the floor, a jet of fire out of a grating.
enum HazardStyle { crusher, hands, flame, blade }

/// Things in a row that strike in turn, each on the same beat: under or
/// over each only while it is back.
class TimedHazardRow extends Component
    with OffScreenCulling
    implements HasFootprint {
  TimedHazardRow({
    required this.xs,
    required this.floor,
    required this.stage,
    required this.style,
    this.period = 3.4,
    this.width = 1.3,
    this.ceiling = 0,
  }) : super(priority: 2);

  final List<double> xs;
  final double floor, period, width;

  /// Where the crushers hang from (crusher only).
  final double ceiling;
  final Stage stage;
  final HazardStyle style;
  double _time = 0;
  final List<bool> _was = [];

  @override
  Rect get footprint => Rect.fromLTRB(
    xs.first - width - (style == HazardStyle.blade ? 2.5 : 0),
    style == HazardStyle.crusher || style == HazardStyle.blade
        ? ceiling
        : floor - 2.4,
    xs.last + width,
    floor,
  );

  void reset() => _time = 0;

  /// Where each one is in its beat, 0 to 1.
  double _phase(int i) => ((_time / period) + i * 0.37) % 1;

  /// How far out it is, 0 (back) to 1 (all the way: on the floor, or up).
  /// A blade's swing, radians from hanging straight down.
  double swing(int i) => math.sin(_phase(i) * math.pi * 2) * 1.05;

  double out(int i) {
    final double f = _phase(i);
    if (style == HazardStyle.blade) {
      return 1 - (swing(i).abs() / 1.05);
    }
    if (style == HazardStyle.crusher) {
      if (f < 0.07) return f / 0.07;
      if (f < 0.27) return 1;
      if (f < 0.65) return 1 - (f - 0.27) / 0.38;
      return 0;
    }
    if (f < 0.6) return 0;
    if (f < 0.66) return (f - 0.6) / 0.06;
    if (f < 0.92) return 1;
    return 1 - (f - 0.92) / 0.08;
  }

  bool deadly(int i) =>
      out(i) >
      switch (style) {
        HazardStyle.crusher => 0.55,
        HazardStyle.blade => 0.62,
        _ => 0.25,
      };

  /// Seconds before it next strikes (0 while it is out, or a crusher
  /// still low on its way back up).
  double clearFor(int i) {
    if (deadly(i)) return 0;
    if (style == HazardStyle.crusher && out(i) > 0.4) return 0;
    final double now = _time;
    var t = 0.0;
    for (; t < period; t += 0.05) {
      _time = now + t;
      if (deadly(i)) break;
    }
    _time = now;
    return t;
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    _time += dt;
    final Player boy = stage.player;
    while (_was.length < xs.length) {
      _was.add(false);
    }
    for (var i = 0; i < xs.length; i++) {
      final bool now = deadly(i);
      if (now && !_was[i] && isOnScreen(footprint)) {
        switch (style) {
          case HazardStyle.crusher:
            stage.cue('hammer', at: Vector2(xs[i], floor), shake: 0.3);
          case HazardStyle.hands:
            stage.cue('creak', weight: 0.7, at: Vector2(xs[i], floor));
          case HazardStyle.flame:
            stage.cue('fire', weight: 0.8, at: Vector2(xs[i], floor));
          case HazardStyle.blade:
            stage.cue('rope', weight: 0.5, at: Vector2(xs[i], floor - 1));
        }
      }
      _was[i] = now;
      if (!now || !boy.isMounted || boy.isDead) continue;
      final Vector2 p = boy.body.position;
      if (style == HazardStyle.blade) {
        final double len = floor - 0.9 - ceiling;
        final double bx = xs[i] + math.sin(swing(i)) * len;
        if ((p.x - bx).abs() < 0.75) boy.die();
        continue;
      }
      if ((p.x - xs[i]).abs() < width / 2 + 0.12 &&
          p.y + GameConfig.playerHeight / 2 > floor - 2.2) {
        boy.die();
      }
    }
  }

  static final Paint _stone = Paint()..color = _black;
  static final Paint _chain = Paint()
    ..color = _black
    ..strokeWidth = 0.05;
  static final Paint _fireOuter = Paint()..color = const Color(0xB0E8A040);
  static final Paint _fireInner = Paint()..color = const Color(0xE8FFE8B0);

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint)) return;
    for (var i = 0; i < xs.length; i++) {
      final double x = xs[i], o = out(i), hw = width / 2;
      switch (style) {
        case HazardStyle.blade:
          // A rod from the roof and a crescent of iron at its end.
          final double a = swing(i);
          final Offset pivot = Offset(x, ceiling);
          final double len = floor - 0.9 - ceiling;
          final Offset end =
              pivot + Offset(math.sin(a) * len, math.cos(a) * len);
          canvas.drawLine(pivot, end, _chain);
          canvas.save();
          canvas.translate(end.dx, end.dy);
          canvas.rotate(-a);
          canvas.drawPath(
            Path()
              ..moveTo(-0.75, -0.1)
              ..quadraticBezierTo(0, 0.75, 0.75, -0.1)
              ..quadraticBezierTo(0, 0.35, -0.75, -0.1)
              ..close(),
            _stone,
          );
          canvas.restore();
        case HazardStyle.crusher:
          final double bottom = ceiling + 0.9 + (floor - ceiling - 0.9) * o;
          canvas.drawLine(
            Offset(x - hw * 0.6, ceiling),
            Offset(x - hw * 0.6, bottom - 1.2),
            _chain,
          );
          canvas.drawLine(
            Offset(x + hw * 0.6, ceiling),
            Offset(x + hw * 0.6, bottom - 1.2),
            _chain,
          );
          canvas.drawRect(
            Rect.fromLTRB(x - hw, bottom - 1.2, x + hw, bottom),
            _stone,
          );
        case HazardStyle.hands:
          // The lid in the floor, and the arm out of it, reaching.
          canvas.drawRect(
            Rect.fromLTRB(x - hw, floor - 0.08, x + hw, floor + 0.05),
            _stone,
          );
          if (o > 0) {
            final double top = floor - 1.9 * o;
            for (final dx in const [-0.22, 0.2]) {
              canvas.drawPath(
                Path()
                  ..moveTo(x + dx - 0.07, floor)
                  ..lineTo(x + dx * 1.3 - 0.05, top + 0.25)
                  ..lineTo(x + dx * 1.5 - 0.12, top)
                  ..lineTo(x + dx * 1.3, top + 0.12)
                  ..lineTo(x + dx * 1.5 + 0.1, top - 0.02)
                  ..lineTo(x + dx * 1.3 + 0.07, top + 0.28)
                  ..lineTo(x + dx + 0.07, floor)
                  ..close(),
                _stone,
              );
            }
          }
        case HazardStyle.flame:
          canvas.drawRect(
            Rect.fromLTRB(x - hw, floor - 0.06, x + hw, floor + 0.05),
            _stone,
          );
          if (o > 0) {
            final double flicker = 0.85 + 0.15 * math.sin(_time * 31 + i);
            final double top = floor - 2.2 * o * flicker;
            for (final (paint, k) in [(_fireOuter, 1.0), (_fireInner, 0.45)]) {
              canvas.drawPath(
                Path()
                  ..moveTo(x - hw * k, floor)
                  ..quadraticBezierTo(
                    x - hw * 0.5 * k,
                    (floor + top) / 2,
                    x,
                    top + (1 - k) * 0.6,
                  )
                  ..quadraticBezierTo(
                    x + hw * 0.5 * k,
                    (floor + top) / 2,
                    x + hw * k,
                    floor,
                  )
                  ..close(),
                paint,
              );
            }
          }
      }
    }
  }
}

/// Rotten planks across a pit: each one, stood on, gives a moment later
/// and goes down. Over them without stopping.
class CrumblingPlanks extends Component
    with OffScreenCulling
    implements HasFootprint {
  CrumblingPlanks({
    required this.left,
    required this.right,
    required this.top,
    required this.stage,
    this.count = 6,
    this.rise = 0,
  }) : super(priority: 1);

  final double left, right, top;

  /// How much higher each plank is than the one before (a stair).
  final double rise;
  double _topOf(int i) => top - rise * i;
  final int count;
  final Stage stage;
  final List<Body> _planks = [];
  final List<double> _timer = [];

  /// 0 whole, 1 giving, 2 gone.
  final List<int> _state = [];

  double get _step => (right - left) / count;

  @override
  Rect get footprint =>
      Rect.fromLTRB(left, top - rise * count - 0.2, right, top + 0.3);

  @override
  Future<void> onLoad() async => _build();

  void _build() {
    final world = (findGame()! as Forge2DGame).world.physicsWorld;
    for (var i = 0; i < count; i++) {
      final b = world.createBody(
        BodyDef(position: Vector2(left + _step * (i + 0.5), _topOf(i) + 0.09)),
      );
      b.createShape(
        Polygon.box(_step / 2 - 0.03, 0.09),
        ShapeDef(
          filter: Filter(categoryBits: CollisionLayers.terrain),
          material: SurfaceMaterial(friction: 0.9),
        ),
      );
      _planks.add(b);
      _timer.add(0);
      _state.add(0);
    }
  }

  /// Whole again (after a death in the pit).
  void reset() {
    for (final b in _planks) {
      if (b.isValid) b.destroy();
    }
    _planks.clear();
    _timer.clear();
    _state.clear();
    _build();
  }

  @override
  void onRemove() {
    for (final b in _planks) {
      if (b.isValid) b.destroy();
    }
    super.onRemove();
  }

  @override
  void update(double dt) {
    if (dt <= 0 || _planks.isEmpty) return;
    final Player boy = stage.player;
    final Vector2 p = boy.body.position;
    final double feet = p.y + GameConfig.playerHeight / 2;
    for (var i = 0; i < _planks.length; i++) {
      final double cx = left + _step * (i + 0.5);
      switch (_state[i]) {
        case 0:
          if (!boy.isDead &&
              (p.x - cx).abs() < _step / 2 + 0.2 &&
              (feet - _topOf(i)).abs() < 0.25) {
            _state[i] = 1;
            _timer[i] = 0.45;
            stage.cue('creak', weight: 0.8, at: Vector2(cx, _topOf(i)));
          }
        case 1:
          _timer[i] -= dt;
          if (_timer[i] <= 0) {
            _state[i] = 2;
            _planks[i]
              ..type = BodyType.dynamic
              ..angularVelocity = (i.isEven ? 1.5 : -1.5);
            stage.cue('wood', weight: 0.7, at: Vector2(cx, _topOf(i)));
          }
      }
    }
  }

  static final Paint _wood = Paint()..color = const Color(0xFF0A0908);
  static final Paint _grain = Paint()
    ..color = const Color(0x30C8BCA8)
    ..strokeWidth = 0.02;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint.inflate(4))) return;
    for (var i = 0; i < _planks.length; i++) {
      final b = _planks[i];
      if (!b.isValid) continue;
      final double shiver = _state[i] == 1
          ? math.sin(_timer[i] * 80) * 0.03
          : 0;
      canvas.save();
      canvas.translate(b.position.x + shiver, b.position.y);
      canvas.rotate(b.angle);
      final double hw = _step / 2 - 0.03;
      canvas.drawRect(Rect.fromLTRB(-hw, -0.09, hw, 0.09), _wood);
      canvas.drawLine(
        Offset(-hw + 0.1, -0.02),
        Offset(hw - 0.1, -0.03),
        _grain,
      );
      canvas.restore();
    }
  }
}

/// A barrier of planks nailed across the way, too high to climb: only
/// something heavy coming fast breaks it.
class BreakableWall extends BodyComponent with OffScreenCulling {
  BreakableWall({
    required this.left,
    required this.right,
    required this.top,
    required this.bottom,
  }) : super(renderBody: false, priority: 1);

  final double left, right, top, bottom;
  bool broken = false;
  double _since = 0;

  @override
  Body createBody() {
    final b = world.createBody(
      BodyDef(position: Vector2((left + right) / 2, (top + bottom) / 2)),
    );
    b.createShape(
      Polygon.box((right - left) / 2, (bottom - top) / 2),
      ShapeDef(filter: Filter(categoryBits: CollisionLayers.terrain)),
    );
    return b;
  }

  void shatter() {
    if (broken) return;
    broken = true;
    _since = 0;
    body.isEnabled = false;
    cue('wood', at: Vector2(left, (top + bottom) / 2), shake: 0.5);
    cue('wood', weight: 0.7, at: Vector2(right, top));
  }

  void reset() {
    broken = false;
    if (body.isValid) body.isEnabled = true;
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (broken) _since += dt;
  }

  static final Paint _wood = Paint()..color = const Color(0xFF0A0908);

  @override
  void render(Canvas canvas) {
    final double hw = (right - left) / 2, hh = (bottom - top) / 2;
    if (!broken) {
      // Boards one above another, and a brace across.
      for (double y = -hh; y < hh - 0.05; y += 0.32) {
        canvas.drawRect(
          Rect.fromLTRB(-hw - 0.15, y, hw + 0.15, y + 0.27),
          _wood,
        );
      }
      canvas.drawLine(
        Offset(-hw, -hh),
        Offset(hw, hh),
        _wood..strokeWidth = 0.12,
      );
      return;
    }
    // Splinters thrown down the way, settling.
    final double t = math.min(1, _since * 1.5);
    for (var i = 0; i < 7; i++) {
      final double dx = 0.4 + i * 0.45 * t;
      final double dy = hh - 0.08 - (1 - t) * (0.6 + (i % 3) * 0.3);
      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(i * 0.9 + t * 2);
      canvas.drawRect(const Rect.fromLTRB(-0.35, -0.05, 0.35, 0.05), _wood);
      canvas.restore();
    }
  }
}

/// A chandelier of iron and candles hung over the floor: its cord let go,
/// it comes down on whatever is under it.
class FallingChandelier extends Component
    with OffScreenCulling
    implements HasFootprint {
  FallingChandelier({
    required this.x,
    required this.hangY,
    required this.floor,
    required this.stage,
    required this.onLanded,
  }) : super(priority: 2);

  final double x, hangY, floor;
  final Stage stage;
  final void Function() onLanded;

  /// 0 hanging, 1 falling, 2 down.
  int state = 0;
  double _y = 0, _v = 0, _time = 0;

  @override
  Rect get footprint => Rect.fromLTRB(x - 1.3, hangY - 0.6, x + 1.3, floor);

  void drop() {
    if (state != 0) return;
    state = 1;
    stage.cue('chain', at: Vector2(x, hangY));
  }

  void reset() {
    state = 0;
    _y = 0;
    _v = 0;
  }

  /// Already down (past it).
  void restoreDown() {
    state = 2;
    _y = floor - 0.45 - hangY;
  }

  @override
  void update(double dt) {
    _time += dt;
    if (state != 1 || dt <= 0) return;
    _v += GameConfig.gravityMetersPerSecondSquared * dt;
    _y += _v * dt;
    if (hangY + _y >= floor - 0.45) {
      _y = floor - 0.45 - hangY;
      state = 2;
      stage.cue('chain', weight: 0.9, at: Vector2(x, floor), shake: 0.6);
      stage.cue('hammer', weight: 0.8, at: Vector2(x, floor));
      onLanded();
    }
  }

  static final Paint _iron = Paint()..color = _black;
  static final Paint _flame = Paint()..color = const Color(0xE0FFD890);
  static final Paint _chainPaint = Paint()
    ..color = _black
    ..strokeWidth = 0.04;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint.inflate(1))) return;
    final double y = hangY + _y;
    if (state == 0) {
      canvas.drawLine(Offset(x, hangY - 8), Offset(x, y - 0.5), _chainPaint);
    }
    canvas.save();
    canvas.translate(x, y);
    if (state == 2) canvas.rotate(0.12);
    // A ring with arms, and candles on them.
    canvas.drawRect(const Rect.fromLTRB(-1.2, 0.0, 1.2, 0.1), _iron);
    canvas.drawPath(
      Path()
        ..moveTo(-1.2, 0.05)
        ..quadraticBezierTo(0, 0.6, 1.2, 0.05)
        ..lineTo(1.1, 0.1)
        ..quadraticBezierTo(0, 0.48, -1.1, 0.1)
        ..close(),
      _iron,
    );
    canvas.drawLine(const Offset(0, -0.5), const Offset(0, 0.4), _chainPaint);
    for (final cx in const [-1.0, -0.5, 0.0, 0.5, 1.0]) {
      canvas.drawRect(Rect.fromLTRB(cx - 0.03, -0.2, cx + 0.03, 0.0), _iron);
      if (state != 2) {
        final double f = 0.06 + 0.02 * math.sin(_time * 9 + cx * 5);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset(cx, -0.27),
            width: 0.06,
            height: f * 2,
          ),
          _flame,
        );
      }
    }
    canvas.restore();
  }
}

/// An eye in the wall, as big as a door: it opens, looks, closes. Moving
/// while it is open is the end of him; standing still, he is not seen.
class WatchEye extends Component with OffScreenCulling implements HasFootprint {
  WatchEye({
    required this.at,
    required this.left,
    required this.right,
    required this.stage,
    this.open = 2.2,
    this.shut = 2.4,
  }) : super(priority: -2);

  /// The eye's middle, world metres; the stretch it watches.
  final Vector2 at;
  final double left, right, open, shut;
  final Stage stage;
  double _time = 0;
  double _caught = 0;

  double get _period => open + shut + 0.6;

  /// How open it is, 0 to 1.
  double get lid {
    final double t = _time % _period;
    if (t < shut) return 0;
    if (t < shut + 0.3) return (t - shut) / 0.3;
    if (t < shut + 0.3 + open) return 1;
    return 1 - (t - shut - 0.3 - open) / 0.3;
  }

  bool get watching => lid > 0.3;

  /// Seconds until it opens (0 while it is open).
  double get shutFor {
    final double t = _time % _period;
    return t < shut ? shut - t : (watching ? 0 : _period - t + shut);
  }

  @override
  Rect get footprint =>
      Rect.fromLTRB(at.x - 1.2, at.y - 0.8, at.x + 1.2, at.y + 0.8);

  void reset() {
    _time = 0;
    _caught = 0;
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    final double before = lid;
    _time += dt;
    if (before < 0.3 && lid >= 0.3) stage.cue('creak', weight: 0.6, at: at);
    final Player boy = stage.player;
    if (!boy.isMounted || boy.isDead) return;
    final Vector2 p = boy.body.position;
    final bool moving = boy.velocity.x.abs() > 0.3 || !boy.isOnGround;
    if (watching && p.x > left && p.x < right && moving) {
      _caught += dt;
      if (_caught > 0.25) {
        stage.cue('shriek', at: at);
        boy.die();
      }
    } else {
      _caught = 0;
    }
  }

  static final Paint _socket = Paint()..color = _black;
  static final Paint _white = Paint()..color = const Color(0xFFD8D6CC);

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint)) return;
    final double o = lid;
    canvas.drawOval(
      Rect.fromCenter(center: at.toOffset(), width: 2.3, height: 1.3),
      _socket,
    );
    if (o <= 0.02) return;
    canvas.drawOval(
      Rect.fromCenter(center: at.toOffset(), width: 1.8, height: 0.9 * o),
      _white,
    );
    // The pupil follows him.
    final Player boy = stage.player;
    final double look = boy.isMounted
        ? ((boy.body.position.x - at.x) / 12).clamp(-0.5, 0.5)
        : 0;
    canvas.drawCircle(
      at.toOffset() + Offset(look, 0),
      0.3 * o.clamp(0.4, 1),
      _socket,
    );
  }
}

/// Fine wire strung across the way at the ankle, and a slot in the wall
/// ahead: a foot on the wire, and arrows come out of the slot at chest
/// height. Over it at a jump, or low enough for them to pass over.
class ArrowTrap extends Component
    with OffScreenCulling
    implements HasFootprint {
  ArrowTrap({
    required this.wires,
    required this.slotX,
    required this.floor,
    required this.stage,
  }) : super(priority: 3);

  final List<double> wires;
  final double slotX, floor;
  final Stage stage;
  final List<double> _arrows = [];
  final List<double> _wait = [];
  final List<bool> _tripped = [];
  double _lastFeetX = double.nan;

  static const double height = 1.05;

  @override
  Rect get footprint =>
      Rect.fromLTRB(wires.first - 1, floor - 2, slotX + 0.6, floor);

  void reset() {
    _arrows.clear();
    _wait.clear();
    _tripped
      ..clear()
      ..addAll(List.filled(wires.length, false));
    _lastFeetX = double.nan;
  }

  @override
  Future<void> onLoad() async => reset();

  void _fire() {
    stage.cue('chain', weight: 0.6, at: Vector2(slotX, floor - height));
    for (var i = 0; i < 3; i++) {
      _wait.add(i * 0.22);
    }
  }

  @override
  void update(double dt) {
    if (dt <= 0) return;
    final Player boy = stage.player;
    if (boy.isMounted && !boy.isDead) {
      final Vector2 p = boy.body.position;
      final double feet = p.y + GameConfig.playerHeight / 2;
      for (var i = 0; i < wires.length; i++) {
        final double w = wires[i];
        final bool crossed =
            !_lastFeetX.isNaN && (_lastFeetX - w).sign != (p.x - w).sign;
        if (!_tripped[i] && crossed && feet > floor - 0.3) {
          _tripped[i] = true;
          stage.cue('tick', at: Vector2(w, floor));
          _fire();
        }
      }
      _lastFeetX = p.x;
    }
    for (var i = _wait.length - 1; i >= 0; i--) {
      _wait[i] -= dt;
      if (_wait[i] <= 0) {
        _wait.removeAt(i);
        _arrows.add(slotX - 0.3);
      }
    }
    for (var i = _arrows.length - 1; i >= 0; i--) {
      _arrows[i] -= 14 * dt;
      if (_arrows[i] < wires.first - 8) {
        _arrows.removeAt(i);
        continue;
      }
      if (!boy.isMounted || boy.isDead) continue;
      final Vector2 p = boy.body.position;
      final double top = boy.isLow
          ? p.y + GameConfig.playerHeight / 2 - 0.94
          : p.y - GameConfig.playerHeight / 2;
      if ((_arrows[i] - p.x).abs() < 0.3 && top < floor - height + 0.04) {
        boy.die();
      }
    }
  }

  static final Paint _wire = Paint()
    ..color = const Color(0x90C8C4B8)
    ..strokeWidth = 0.015;
  static final Paint _iron = Paint()..color = _black;

  @override
  void render(Canvas canvas) {
    if (!isOnScreen(footprint.inflate(8))) return;
    for (var i = 0; i < wires.length; i++) {
      final double w = wires[i];
      // Two pegs, and the wire between, slack once it has been caught.
      canvas.drawRect(
        Rect.fromLTRB(w - 0.06, floor - 0.32, w - 0.02, floor),
        _iron,
      );
      canvas.drawRect(
        Rect.fromLTRB(w + 0.02, floor - 0.32, w + 0.06, floor),
        _iron,
      );
      final double y = floor - (_tripped[i] ? 0.05 : 0.25);
      canvas.drawLine(Offset(w - 0.04, y), Offset(w + 0.04, y), _wire);
      canvas.drawLine(
        Offset(w - 0.04, floor - 0.25),
        Offset(w - 0.5, y + 0.04),
        _wire,
      );
    }
    // The slot in the wall.
    canvas.drawRect(
      Rect.fromLTRB(
        slotX - 0.1,
        floor - height - 0.1,
        slotX + 0.5,
        floor - height + 0.1,
      ),
      _iron,
    );
    for (final a in _arrows) {
      canvas.drawLine(
        Offset(a, floor - height),
        Offset(a + 0.7, floor - height),
        _iron..strokeWidth = 0.04,
      );
      canvas.drawPath(
        Path()
          ..moveTo(a - 0.12, floor - height)
          ..lineTo(a, floor - height - 0.05)
          ..lineTo(a, floor - height + 0.05)
          ..close(),
        _iron,
      );
    }
  }
}
