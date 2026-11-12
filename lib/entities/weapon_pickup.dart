import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import '../combat/combat_target.dart';
import '../combat/projectile.dart';
import '../world/stage.dart';

enum KitItem { sword, shuriken }

/// Chapter 1's two gifts, standing in the world rather than floating: the
/// sword stuck in a chopping stump, and a pouch of stars hung on a post.
/// Walking into one takes it; the stump and post stay where they are.
class KitPickup extends PositionComponent {
  KitPickup({
    required this.item,
    required this.stage,
    required this.enabled,
    required this.onCollected,
    required Vector2 groundPosition,
  }) : super(
         position: groundPosition,
         anchor: Anchor.bottomCenter,
         priority: -4,
       );

  final KitItem item;
  final Stage stage;
  final bool Function() enabled;
  final void Function(KitItem) onCollected;

  double _time = 0;

  /// Seconds since it was taken, or −1.
  double _taken = -1;
  bool get taken => _taken >= 0;

  static const String stumpArt = 'weapons/stump.png';
  static const String stumpEmptyArt = 'weapons/stump_empty.png';
  static const String pouchArt = 'weapons/pouch.png';
  static List<String> get arts => [stumpArt, stumpEmptyArt, pouchArt];

  /// Where the glint and the prompt sit, world metres.
  Vector2 get glintAt =>
      position + (item == KitItem.sword ? Vector2(.08, -1.05) : Vector2(.1, -1.0));

  static final Paint _ink = Paint()..color = const Color(0xFF060708);
  static final Paint _edge = Paint()
    ..color = const Color(0xE6F2F2EC)
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  final Paint _image = Paint()..filterQuality = FilterQuality.low;

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
    if (taken) {
      _taken += dt;
      return;
    }
    if (!enabled() || !stage.player.isMounted) return;
    final boy = stage.player.body.position;
    if ((boy.x - position.x).abs() < .55 && (boy.y - (position.y - .6)).abs() < 1.2) {
      _taken = 0;
      onCollected(item);
      cue(item == KitItem.sword ? 'slash' : 'throw', weight: .7, at: glintAt);
    }
  }

  /// Marks it as already taken (a later checkpoint, a replay).
  void markTaken() => _taken = 10;

  @override
  void render(Canvas canvas) {
    // Local frame: the bottom centre of its base at (width/2, height).
    canvas.save();
    canvas.translate(width / 2, height);
    if (item == KitItem.sword) {
      final name = taken && Flame.images.containsKey(stumpEmptyArt)
          ? stumpEmptyArt
          : stumpArt;
      if (!_drawArt(canvas, name, 1.25)) _drawStump(canvas);
      if (!taken && !Flame.images.containsKey(stumpArt)) _drawStuckSword(canvas);
    } else {
      if (!_drawArt(canvas, pouchArt, 1.55)) _drawPost(canvas);
    }
    _drawGlint(canvas);
    _drawRising(canvas);
    canvas.restore();
  }

  /// [name] scaled to [tall] metres, standing on the base. False if the
  /// art is not loaded.
  bool _drawArt(Canvas canvas, String name, double tall) {
    if (!Flame.images.containsKey(name)) return false;
    final image = Flame.images.fromCache(name);
    final w = tall * image.width / image.height;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(-w / 2, -tall, w, tall),
      _image,
    );
    return true;
  }

  /// A pale star of light on the hilt or the pouch, turning slowly, until
  /// it is taken: the one bright thing in the yard.
  void _drawGlint(Canvas canvas) {
    if (taken) return;
    final at = glintAt - position;
    final pulse = .55 + .45 * math.sin(_time * 3.2).abs();
    _edge
      ..strokeWidth = .022
      ..color = Color.fromRGBO(244, 244, 238, .85 * pulse);
    canvas.save();
    canvas.translate(at.x, at.y);
    canvas.rotate(_time * .8);
    final r = .12 + .06 * pulse;
    canvas.drawLine(Offset(-r, 0), Offset(r, 0), _edge);
    canvas.drawLine(Offset(0, -r * 1.4), Offset(0, r * 1.4), _edge);
    canvas.restore();
  }

  /// Taken, the sword or a star lifts away and fades.
  void _drawRising(Canvas canvas) {
    if (!taken || _taken > .5) return;
    final t = _taken / .5;
    final at = glintAt - position + Vector2(0, -t * .9);
    canvas.save();
    canvas.translate(at.x, at.y);
    _ink.color = Color.fromRGBO(6, 7, 8, 1 - t);
    if (item == KitItem.sword) {
      canvas.rotate(-math.pi / 2);
      canvas.drawRect(const Rect.fromLTWH(-.1, -.02, .7, .04), _ink);
    } else {
      canvas.rotate(t * 8);
      canvas.drawPath(Shuriken.starPath(.14, .045), _ink);
    }
    canvas.restore();
    _ink.color = const Color(0xFF060708);
  }

  void _drawStump(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(-.42, 0)
        ..lineTo(-.3, -.5)
        ..lineTo(.32, -.52)
        ..lineTo(.44, 0)
        ..close(),
      _ink,
    );
  }

  void _drawStuckSword(Canvas canvas) {
    _ink.color = const Color(0xFF060708);
    canvas.save();
    canvas.translate(.04, -.5);
    canvas.rotate(-.12);
    canvas.drawRect(const Rect.fromLTWH(-.02, -.62, .04, .5), _ink);
    canvas.drawRect(const Rect.fromLTWH(-.07, -.66, .14, .035), _ink);
    canvas.drawRect(const Rect.fromLTWH(-.022, -.86, .044, .2), _ink);
    canvas.restore();
  }

  void _drawPost(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(-.06, -1.5, .12, 1.5), _ink);
    canvas.drawOval(const Rect.fromLTWH(-.02, -1.12, .26, .3), _ink);
  }
}

/// A straw dummy on a post in the yard. One cut splits it; a moment later
/// it stands whole again, so the cut can be tried as often as he likes.
class TrainingEffigy extends PositionComponent implements CombatTarget {
  TrainingEffigy({required Vector2 position})
    : super(position: position, anchor: Anchor.bottomCenter, priority: -3);

  static const String art = 'weapons/dummy.png';
  static const double tall = 1.75;

  /// Seconds since the last cut, or −1 while whole.
  double _cut = -1;
  double _cutDirection = 1;
  int cuts = 0;
  final Paint _image = Paint()..filterQuality = FilterQuality.low;
  static final Paint _ink = Paint()..color = const Color(0xFF060708);
  final math.Random _random = math.Random(3);
  final List<(Vector2, Vector2, double)> _straw = [];

  bool get isCut => _cut >= 0;

  @override
  Vector2 get combatPosition => position - Vector2(0, 1.0);

  @override
  bool get canReceiveCombatHit => isMounted && !isCut;

  @override
  bool get killedByHit => true;

  @override
  void receiveCombatHit(CombatHit hit) {
    if (isCut) return;
    _cut = 0;
    _cutDirection = hit.direction;
    cuts++;
    _straw.clear();
    for (var i = 0; i < 16; i++) {
      _straw.add((
        Vector2(0, -1.05 + (_random.nextDouble() - .5) * .3),
        Vector2(
          hit.direction * (1 + _random.nextDouble() * 3),
          -1 - _random.nextDouble() * 3,
        ),
        _random.nextDouble() * math.pi,
      ));
    }
    cue('wood', weight: .6, at: combatPosition, shake: .06);
  }

  @override
  void update(double dt) {
    super.update(dt);
    if (!isCut) return;
    _cut += dt;
    for (var i = 0; i < _straw.length; i++) {
      final (p, v, a) = _straw[i];
      _straw[i] = (p + v * dt, v + Vector2(0, 7 * dt), a + dt * 6);
    }
    if (_cut > 2.2) _cut = -1;
  }

  @override
  void render(Canvas canvas) {
    canvas.save();
    canvas.translate(width / 2, height);
    // The top half slides off along the cut and falls; it fades as the
    // whole dummy comes back.
    final fall = isCut ? math.min(1.0, _cut / .6) : 0.0;
    final back = isCut ? ((_cut - 1.8) / .4).clamp(0.0, 1.0) : 1.0;
    _drawHalf(canvas, lower: true, alpha: 1);
    if (!isCut) {
      _drawHalf(canvas, lower: false, alpha: 1);
    } else {
      canvas.save();
      canvas.translate(_cutDirection * fall * .55, fall * fall * .9);
      canvas.rotate(_cutDirection * fall * 1.1);
      _drawHalf(canvas, lower: false, alpha: 1 - fall);
      canvas.restore();
      if (back > 0) _drawHalf(canvas, lower: false, alpha: back);
      for (final (p, _, a) in _straw) {
        _ink.color = Color.fromRGBO(6, 7, 8, (1 - _cut / 1.2).clamp(0.0, 1.0));
        canvas.save();
        canvas.translate(p.x, p.y);
        canvas.rotate(a);
        canvas.drawRect(const Rect.fromLTWH(-.07, -.008, .14, .016), _ink);
        canvas.restore();
      }
      _ink.color = const Color(0xFF060708);
    }
    canvas.restore();
  }

  /// The dummy above (or below) the cut line, 1.05 m up.
  void _drawHalf(Canvas canvas, {required bool lower, required double alpha}) {
    if (alpha <= 0) return;
    const cutY = -1.05;
    canvas.save();
    canvas.clipRect(
      lower
          ? const Rect.fromLTRB(-2, cutY, 2, .1)
          : const Rect.fromLTRB(-2, -3, 2, cutY),
    );
    if (Flame.images.containsKey(art)) {
      final image = Flame.images.fromCache(art);
      final w = tall * image.width / image.height;
      _image.color = Color.fromRGBO(255, 255, 255, alpha);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        Rect.fromLTWH(-w / 2, -tall, w, tall),
        _image,
      );
    } else {
      _ink.color = Color.fromRGBO(6, 7, 8, alpha);
      canvas.drawRect(const Rect.fromLTWH(-.05, -1.75, .1, 1.75), _ink);
      canvas.drawOval(const Rect.fromLTWH(-.24, -1.38, .48, .78), _ink);
      canvas.drawCircle(const Offset(0, -1.55), .17, _ink);
      canvas.drawRect(const Rect.fromLTWH(-.55, -1.2, 1.1, .07), _ink);
      _ink.color = const Color(0xFF060708);
    }
    canvas.restore();
  }
}
