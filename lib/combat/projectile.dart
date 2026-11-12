import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame_forge2d/flame_forge2d.dart' as b2 show QueryFilter, World;

import '../physics/collision_layers.dart';
import '../world/stage.dart';
import 'combat_target.dart';
import 'weapons.dart';

/// A thrown star: it spins along a straight line until it meets something.
/// A target is struck through; a wall or the ground takes it, and it stays
/// stuck there a moment before it fades.
class Shuriken extends PositionComponent {
  Shuriken({
    required Vector2 from,
    required this.direction,
    required this.world,
    required this.stage,
    this.onHit,
  }) : _start = from.clone(),
       super(position: from, priority: 7);

  final double direction;
  final b2.World world;
  final Stage stage;

  /// Told when the star strikes a target, and whether that ended it.
  final void Function(CombatTarget target, bool killed)? onHit;

  final Vector2 _start;
  double _spin = 0;
  double _stuck = -1;
  static const double stuckSeconds = 2;
  static const String art = 'weapons/shuriken.png';

  static final b2.QueryFilter _solid = b2.QueryFilter(
    categoryBits: CollisionLayers.all,
    maskBits: CollisionLayers.terrain | CollisionLayers.prop,
  );
  static final Paint _fill = Paint()..color = const Color(0xFF060708);
  static final Paint _edge = Paint()
    ..color = const Color(0xCCEDEDE6)
    ..style = PaintingStyle.stroke
    ..strokeWidth = .018;
  final Paint _image = Paint()..filterQuality = FilterQuality.low;

  bool get isStuck => _stuck >= 0;

  @override
  void update(double dt) {
    super.update(dt);
    if (isStuck) {
      _stuck += dt;
      if (_stuck >= stuckSeconds) removeFromParent();
      return;
    }
    _spin += dt * 26 * direction;
    final step = Vector2(direction * AttackTiming.starSpeed * dt, 0);
    final from = position.clone();

    // A target first: the star goes through the air in front of a wall.
    for (final target in stage.descendants().whereType<CombatTarget>()) {
      if (!target.canReceiveCombatHit) continue;
      final at = target.combatPosition;
      final along = (at.x - from.x) * direction;
      if (along < -.3 || along > step.length + .3) continue;
      if ((at.y - from.y).abs() > .85) continue;
      final killed = target.killedByHit;
      target.receiveCombatHit(CombatHit(direction: direction));
      stage.combatFx?.sparks(Vector2(at.x - direction * .1, from.y), direction);
      onHit?.call(target, killed);
      removeFromParent();
      return;
    }

    // Then what it would fly into.
    double? wall;
    world.castRay(from, step, filter: _solid, (hit) {
      if (hit.shape.isSensor) return -1;
      if (wall == null || hit.fraction < wall!) wall = hit.fraction;
      return hit.fraction;
    });
    if (wall != null) {
      position = from + step * wall!;
      _stuck = 0;
      stage.combatFx?.sparks(position, -direction, count: 5);
      cue('tick', weight: .5, at: position);
      return;
    }
    position = from + step;
    if ((position - _start).length > AttackTiming.starRange) {
      removeFromParent();
    }
  }

  @override
  void render(Canvas canvas) {
    final fade = isStuck
        ? (1 - (_stuck - stuckSeconds + .4) / .4).clamp(0.0, 1.0)
        : 1.0;
    if (fade <= 0) return;
    canvas.save();
    canvas.rotate(isStuck ? .4 : _spin);
    if (Flame.images.containsKey(art)) {
      final image = Flame.images.fromCache(art);
      const size = .34;
      _image.color = Color.fromRGBO(255, 255, 255, fade);
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(-size / 2, -size / 2, size, size),
        _image,
      );
    } else {
      final path = starPath(.16, .05);
      _fill.color = Color.fromRGBO(6, 7, 8, fade);
      canvas.drawPath(path, _fill);
      _edge.color = Color.fromRGBO(237, 237, 230, .8 * fade);
      canvas.drawPath(path, _edge);
    }
    canvas.restore();
    if (!isStuck) {
      // A short pale smear behind it, so its path reads at speed.
      _edge.color = const Color(0x55EDEDE6);
      canvas.drawLine(Offset(-direction * .55, 0), Offset.zero, _edge);
    }
  }

  /// A four-pointed star, [outer] to the points and [inner] to the notches.
  static Path starPath(double outer, double inner) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final r = i.isEven ? outer : inner;
      final x = math.cos(a) * r, y = math.sin(a) * r;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    return path..close();
  }
}
