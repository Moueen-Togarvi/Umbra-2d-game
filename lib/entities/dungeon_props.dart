import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';

import '../world/footprint.dart';
import '../config/game_config.dart';
import '../config/palette.dart';
import '../render/light.dart';
import '../world/stage.dart';
import 'castle_props.dart';
import 'player.dart';

const Color _iron = Color(0xFF050505);

/// The barred front of a cell in the dungeon wall, behind the passage:
/// the bars slide up into the lintel when its cord is pulled.
class CellFront extends Component implements HasFootprint {
  CellFront({
    required this.left,
    required this.right,
    required this.floorY,
    this.height = 2.1,
    super.priority = -20,
  });

  final double left, right, floorY, height;
  double _raised = 0, _goal = 0;

  bool get isOpen => _raised > 0.85;

  @override
  Rect get footprint => Rect.fromLTRB(left, floorY - height, right, floorY);

  void open() => _goal = 1;

  /// Shut again.
  void shut() {
    _goal = 0;
    _raised = 0;
  }

  @override
  void update(double dt) {
    _raised += (_goal - _raised).clamp(-dt / 1.2, dt / 1.2);
  }

  static final Paint _stone = Paint()..color = const Color(0xFF080808);
  static final Paint _bars = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.05;
  static final Paint _dark = Paint()..color = const Color(0xC0030303);

  @override
  void render(Canvas canvas) {
    final double top = floorY - height;
    // The cell's dark inside, the stone round it.
    canvas.drawRect(Rect.fromLTRB(left, top, right, floorY), _dark);
    canvas.drawRect(
      Rect.fromLTRB(left - 0.3, top - 0.5, right + 0.3, top),
      _stone,
    );
    canvas.drawRect(Rect.fromLTRB(left - 0.3, top, left, floorY), _stone);
    canvas.drawRect(Rect.fromLTRB(right, top, right + 0.3, floorY), _stone);
    // The bars, slid up by how far it is open.
    final double lift = _raised * height * 0.92;
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(left, top, right, floorY));
    for (double x = left + 0.12; x < right - 0.05; x += 0.16) {
      canvas.drawLine(Offset(x, top - lift), Offset(x, floorY - lift), _bars);
    }
    for (final t in const [0.15, 0.55]) {
      final double y = top + height * t - lift;
      canvas.drawLine(
        Offset(left, y),
        Offset(right, y),
        _bars..strokeWidth = 0.07,
      );
    }
    _bars.strokeWidth = 0.05;
    canvas.restore();
  }
}

/// Burning oil spread on the floor. It catches where the lamp broke and
/// runs along the oil towards [spreadTo], burns for [seconds] and dies
/// down. It is light, so the vampires run from it, and anything of theirs
/// it reaches burns; it kills the boy too.
class Fire extends Component with StageLight implements GlowingLight {
  Fire({
    required double x,
    required this.floorY,
    double? spreadTo,
    this.seconds = 12,
    super.priority = 3,
  }) : _left = x - 0.9,
       _right = x + 0.9,
       _to = spreadTo ?? x + 0.9;

  final double floorY, seconds;
  double _left, _right;
  final double _to;
  double _time = 0;

  /// How strongly it burns, 0–1.
  double get strength {
    if (_time < 0.3) return _time / 0.3;
    final double end = seconds - _time;
    return end <= 0 ? 0 : math.min(1, end / 2);
  }

  bool get burning => strength > 0.05;
  (double, double) get extent => (_left, _right);

  @override
  bool lights(Vector2 p) =>
      burning &&
      p.x > _left - 2.2 * strength &&
      p.x < _right + 2.2 * strength &&
      p.y > floorY - 4.5;

  @override
  void update(double dt) {
    _time += dt;
    // Running along the spilt oil.
    if (_to > _right) _right = math.min(_to, _right + 3.6 * dt);
    if (_to < _left) _left = math.max(_to, _left - 3.6 * dt);
    final Player? boy = stage?.player;
    if (boy == null || !boy.isMounted || boy.isDead || strength < 0.3) return;
    final Vector2 p = boy.body.position;
    final double feet = p.y + GameConfig.playerHeight / 2;
    if (p.x > _left + 0.1 &&
        p.x < _right - 0.1 &&
        (feet - floorY).abs() < 0.6) {
      boy.die(cause: DeathCause.fire);
    }
    if (strength <= 0 && _time > seconds + 1) removeFromParent();
  }

  final Paint _flame = Paint();

  @override
  void paintLight(Canvas canvas) {
    if (!burning) return;
    final double s = strength;
    final double f = Glow.flicker(_time, 5);
    final double mid = (_left + _right) / 2;
    final double w = _right - _left;
    Glow.round(
      canvas,
      Offset(mid, floorY - 0.6),
      (w / 2 + 2.8) * (1 + 0.04 * f),
      Palette.lampAmber,
      0.5 * s,
    );
  }

  @override
  void render(Canvas canvas) {
    if (!burning) return;
    final double s = strength;
    // Tongues of flame along it, each its own height and flicker.
    final path = Path();
    for (double x = _left; x < _right; x += 0.18) {
      final int k = (x * 7).round();
      final double h = (0.35 + 0.45 * Glow.flicker(_time * 1.3, k)) * s;
      final double sway = math.sin(_time * 6 + k) * 0.05;
      path
        ..moveTo(x - 0.11, floorY)
        ..quadraticBezierTo(x - 0.08, floorY - h * 0.6, x + sway, floorY - h)
        ..quadraticBezierTo(x + 0.08, floorY - h * 0.6, x + 0.11, floorY)
        ..close();
    }
    _flame
      ..color = const Color(0xFFFFFFFF)
      ..shader = Gradient.linear(
        Offset(0, floorY),
        Offset(0, floorY - 0.9),
        [
          const Color(0xFFFFE0A0).withValues(alpha: 0.95 * s),
          Palette.lampAmber.withValues(alpha: 0.85 * s),
          const Color(0xFFC0401A).withValues(alpha: 0),
        ],
        const [0, 0.45, 1],
      );
    canvas.drawPath(path, _flame);
    _flame.shader = null;
  }
}

/// An iron oil lamp hung high on a chain, its small flame lighting only
/// itself. Let fall ([drop]), it breaks on the floor and the oil catches:
/// a [Fire] that runs on along the spilt oil to [spreadTo].
class OilLamp extends Component {
  OilLamp({
    required this.anchor,
    required this.chain,
    required this.floorY,
    this.spreadTo,
    this.burnSeconds = 12,
    super.priority = 2,
  });

  final Vector2 anchor;
  final double chain, floorY, burnSeconds;
  final double? spreadTo;

  double _y = 0, _v = 0, _time = 0;
  bool falling = false;
  Fire? fire;

  /// Where it hangs or falls, world metres.
  Vector2 get lamp => Vector2(anchor.x, anchor.y + chain + _y);

  bool get broken => fire != null;

  void drop() {
    if (!falling && fire == null) falling = true;
  }

  /// Hung up again, lit (after a death undid the boy's work).
  void rehang() {
    falling = false;
    _y = 0;
    _v = 0;
    fire?.removeFromParent();
    fire = null;
  }

  @override
  void update(double dt) {
    _time += dt;
    if (!falling || fire != null) return;
    _v += GameConfig.gravityMetersPerSecondSquared * dt;
    _y += _v * dt;
    if (lamp.y >= floorY - 0.15) {
      falling = false;
      cue('wood', weight: 0.6, at: lamp);
      cue('fire', at: lamp, shake: 0.15);
      final f = fire = Fire(
        x: anchor.x,
        floorY: floorY,
        spreadTo: spreadTo,
        seconds: burnSeconds,
      );
      parent?.add(f);
    }
  }

  static final Paint _metal = Paint()..color = _iron;
  static final Paint _chainPaint = Paint()
    ..color = _iron
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.03;

  @override
  void render(Canvas canvas) {
    if (fire != null) return;
    final Vector2 l = lamp;
    if (!falling) {
      canvas.drawLine(anchor.toOffset(), l.toOffset(), _chainPaint);
    }
    canvas.save();
    canvas.translate(l.x, l.y);
    // A bowl of iron on three short chains, its wick lit.
    canvas.drawPath(
      Path()
        ..moveTo(-0.3, 0)
        ..lineTo(0.3, 0)
        ..quadraticBezierTo(0.25, 0.28, 0, 0.32)
        ..quadraticBezierTo(-0.25, 0.28, -0.3, 0)
        ..close(),
      _metal,
    );
    for (final x in const [-0.26, 0.0, 0.26]) {
      canvas.drawLine(Offset(x, 0), const Offset(0, -0.4), _chainPaint);
    }
    Glow.round(canvas, const Offset(0, -0.05), 0.55, Palette.lampAmber, 0.35);
    Glow.flame(
      canvas,
      const Offset(0, -0.02),
      0.12,
      Palette.lampAmber,
      Glow.flicker(_time, 9),
    );
    canvas.restore();
  }
}
