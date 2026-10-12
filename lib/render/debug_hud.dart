import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame_forge2d/flame_forge2d.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import '../config/game_config.dart';
import '../entities/player.dart';

/// A toggleable readout of measured simulation state and timing.
class DebugHud extends Component {
  DebugHud({
    required this.camera,
    required this.player,
    required this.isVisible,
    required this.framesPerSecond,
    required this.physicsMilliseconds,
  }) : super(priority: 100);

  static const bool enabled = bool.fromEnvironment('UMBRA_DEBUG');

  final CameraComponent camera;
  final Player player;
  final bool Function() isVisible;
  final double Function() framesPerSecond, physicsMilliseconds;
  final TextPainter _text = TextPainter(textDirection: TextDirection.ltr);
  double _elapsed = 1;

  @override
  void update(double dt) => _elapsed += dt;

  @override
  void render(Canvas canvas) {
    if (!isVisible() || !player.isMounted) return;
    if (_elapsed >= 0.10) {
      _elapsed = 0;
      final v = player.velocity;
      _text.text = TextSpan(
        text:
            '${player.state.name}  |  preset ${player.presetIndex + 1}\n'
            'ground ${player.isOnGround}  |  ${player.interactionLabel}\n'
            'vx ${v.x.toStringAsFixed(2)}  vy ${v.y.toStringAsFixed(2)} m/s\n'
            '${framesPerSecond().toStringAsFixed(1)} FPS  |  '
            'physics ${physicsMilliseconds().toStringAsFixed(2)} ms/tick\n'
            'F1 debug  ·  Shift run  ·  E grab  ·  R reset  ·  K fall',
        style: const TextStyle(
          fontFamily: 'Roboto',
          color: Color(0xFF9EF4DD),
          fontSize: 12,
          height: 1.45,
        ),
      );
      _text.layout(maxWidth: camera.viewport.size.x - 32);
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(12, 12, _text.width + 20, _text.height + 16),
        const Radius.circular(6),
      ),
      Paint()..color = const Color(0xD900151B),
    );
    _text.paint(canvas, const Offset(22, 20));
  }
}

/// Uses Box2D's actual debug geometry, including contact points and joints.
class PhysicsDebugOverlay extends Component {
  PhysicsDebugOverlay({required this.world, required this.isVisible})
    : super(priority: 10000);
  final Forge2DWorld world;
  final bool Function() isVisible;
  final _CanvasPhysicsDraw _draw = _CanvasPhysicsDraw()
    ..drawMass = true
    ..drawJointExtras = true
    ..drawContacts = true
    ..drawContactNormals = true;
  @override
  void render(Canvas canvas) {
    if (!isVisible() || !world.physicsWorld.isValid) return;
    _draw.canvas = canvas;
    world.physicsWorld.draw(_draw);
  }
}

class _CanvasPhysicsDraw extends DebugDraw {
  late Canvas canvas;
  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.015;
  final Path _path = Path();
  Paint _color(int color) => _paint..color = Color(0xD0000000 | color);

  @override
  void drawPolygon(List<Vector2> vertices, int color) {
    if (vertices.isEmpty) return;
    _path.reset();
    _path.moveTo(vertices.first.x, vertices.first.y);
    for (final p in vertices.skip(1)) {
      _path.lineTo(p.x, p.y);
    }
    _path.close();
    canvas.drawPath(_path, _color(color));
  }

  @override
  void drawSolidPolygon(
    Transform transform,
    List<Vector2> vertices,
    double radius,
    int color,
  ) =>
      drawPolygon(vertices.map(transform.apply).toList(growable: false), color);
  @override
  void drawCircle(Vector2 center, double radius, int color) =>
      canvas.drawCircle(center.toOffset(), radius, _color(color));
  @override
  void drawSolidCircle(Transform transform, double radius, int color) =>
      drawCircle(transform.position, radius, color);
  @override
  void drawSolidCapsule(
    Vector2 point1,
    Vector2 point2,
    double radius,
    int color,
  ) {
    final Vector2 delta = point2 - point1;
    final Vector2 normal = Vector2(-delta.y, delta.x)..normalize();
    canvas.drawLine(
      (point1 + normal * radius).toOffset(),
      (point2 + normal * radius).toOffset(),
      _color(color),
    );
    canvas.drawLine(
      (point1 - normal * radius).toOffset(),
      (point2 - normal * radius).toOffset(),
      _color(color),
    );
    drawCircle(point1, radius, color);
    drawCircle(point2, radius, color);
  }

  @override
  void drawSegment(Vector2 point1, Vector2 point2, int color) =>
      canvas.drawLine(point1.toOffset(), point2.toOffset(), _color(color));
  @override
  void drawTransform(Transform transform) {
    drawSegment(
      transform.position,
      transform.apply(Vector2(0.20, 0)),
      0xFF7068,
    );
    drawSegment(
      transform.position,
      transform.apply(Vector2(0, 0.20)),
      0x7CA7FF,
    );
  }

  @override
  void drawPoint(Vector2 point, double size, int color) {
    canvas.drawCircle(
      point.toOffset(),
      size / GameConfig.metersToPixels / 2,
      Paint()..color = Color(0xFF000000 | color),
    );
  }
}
