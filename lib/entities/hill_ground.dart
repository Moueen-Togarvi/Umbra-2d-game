import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart' show FlameGame;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../physics/collision_layers.dart';
import '../world/terrain.dart';

/// An earth bank whose drawn top is its Box2D chain, vertex for vertex.
/// Sparse grass grows from that surface without changing where feet land.
class HillGround extends BodyComponent {
  HillGround({required this.segment, required this.pitDepth})
    : super(
        paint: Paint()..color = Palette.silhouette,
        renderBody: false,
        bodyDef: BodyDef(type: BodyType.static, position: Vector2.zero()),
      ) {
    // The foot sensor identifies what it stands on by userData; this must
    // be set before the body exists.
    bodyDef!.userData = this;
  }

  final TerrainSegment segment;

  /// How far the pit walls at each end reach down.
  final double pitDepth;

  late final Path _outline = _buildOutline();
  CameraComponent? _camera;
  double _time = 0;

  @override
  Body createBody() {
    final Body groundBody = super.createBody();

    // Box2D chains collide on the right of their winding. Flame's y axis
    // points down, so left-to-right surface segments face upward on screen.
    final List<Vector2> surface = segment.surface;
    final List<Vector2> points = [
      Vector2(surface.first.x, surface.first.y + pitDepth),
      for (final point in surface) point.clone(),
      Vector2(surface.last.x, surface.last.y + pitDepth),
    ];
    groundBody.createChain(
      ChainDef(
        filter: Filter(categoryBits: CollisionLayers.terrain),
        points: points,
        materials: [SurfaceMaterial(friction: 0.9)],
        // The player's foot sensor can only detect shapes that have opted
        // in to sensor events. Leaving this out is the single most common
        // reason a ground check "just doesn't work".
        enableSensorEvents: true,
        userData: this,
      ),
    );
    return groundBody;
  }

  @override
  Future<void> onLoad() async {
    await super.onLoad();
    final game = findGame();
    if (game is FlameGame) {
      _camera = game.camera;
    }
  }

  @override
  void update(double dt) {
    super.update(dt);
    _time += dt;
  }

  // ---------------------------------------------------------------------------
  // Drawing (world metres; the body sits at the origin)
  // ---------------------------------------------------------------------------

  Path _buildOutline() {
    final Path path = Path();
    final double bottom = GameConfig.levelHeight + 1;
    final List<Vector2> surface = segment.surface;
    path.moveTo(surface.first.x, bottom);
    for (final point in surface) {
      path.lineTo(point.x, point.y);
    }
    path.lineTo(surface.last.x, bottom);
    path.close();
    return path;
  }

  @override
  void render(Canvas canvas) {
    canvas.drawPath(_outline, paint);
    _renderGrass(canvas);
  }

  void _renderGrass(Canvas canvas) {
    const double spacing = 0.38;
    final Rect? visible = _camera?.visibleWorldRect;
    final double visLeft = (visible?.left ?? segment.left) - spacing;
    final double visRight = (visible?.right ?? segment.right) + spacing;
    final double left = math.max(segment.left, visLeft);
    final double right = math.min(segment.right, visRight);
    if (left >= right) return;

    double hash(double x) {
      final double value = math.sin(x * 127.1 + 17.7) * 43758.5453;
      return value - value.floor();
    }

    for (
      double x = (left / spacing).ceil() * spacing;
      x < right;
      x += spacing
    ) {
      final double seed = hash(x);
      if (seed < 0.48 || x < segment.left || x > segment.right) continue;
      final int blades = 3 + (seed * 4).floor();
      final double gust = math.sin(_time * 1.4 - x * 0.7) * 0.025;
      final Path tuft = Path();
      for (var blade = 0; blade < blades; blade++) {
        final double variation = hash(x + blade * 0.83);
        final double rootX = x + (blade / blades - 0.5) * 0.12;
        if (rootX < segment.left || rootX > segment.right) continue;
        final double rootY = segment.heightAt(rootX) + 0.015;
        final double height = 0.06 + variation * 0.28;
        final double lean = (blade / (blades - 1) - 0.5) * 0.15 + gust;
        tuft.moveTo(rootX - 0.006, rootY);
        tuft.quadraticBezierTo(
          rootX + lean * 0.2,
          rootY - height * 0.55,
          rootX + lean,
          rootY - height,
        );
        tuft.quadraticBezierTo(
          rootX + lean * 0.35,
          rootY - height * 0.4,
          rootX + 0.006,
          rootY,
        );
        tuft.close();
      }
      canvas.drawPath(tuft, paint);
    }
  }
}
