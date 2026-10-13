import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart' show FlameGame;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../physics/collision_layers.dart';
import '../render/grass.dart';
import '../world/terrain.dart';

/// An earth bank. Its collision is a smooth Box2D chain, so feet stay
/// steady; its drawn edge is the same surface roughened by a couple of
/// centimetres of lumps, stones and roots, so it reads as soil and not as a
/// vector curve. Where it ends at a pit, the face drops away as a crumbling,
/// undercut cliff with roots hanging into the dark.
///
/// The dense grass behind the boy grows from this edge; the sparse grass in
/// front of his feet is [FrontGrass].
class HillGround extends BodyComponent {
  HillGround({
    required this.segment,
    required this.pitDepth,
    required this.wind,
    this.pitOnLeft = false,
    this.pitOnRight = false,
  }) : super(
         paint: Paint()..color = earthColor,
         renderBody: false,
         bodyDef: BodyDef(type: BodyType.static, position: Vector2.zero()),
       ) {
    // The foot sensor identifies what it stands on by userData; this must
    // be set before the body exists.
    bodyDef!.userData = this;
  }

  /// The darkest thing in the picture: the ground underfoot.
  static const Color earthColor = Color(0xFF060606);

  final TerrainSegment segment;

  /// How deep the pits at either end are, for shaping the cliff faces.
  final double pitDepth;
  final GrassWind wind;

  /// Whether each end drops into a pit (and so gets a cliff face).
  final bool pitOnLeft, pitOnRight;

  late final Path _outline = _buildOutline();
  late final List<_Root> _roots = _buildRoots();
  final Paint _rootPaint = Paint()
    ..color = earthColor
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;
  CameraComponent? _camera;

  @override
  Body createBody() {
    final Body groundBody = super.createBody();

    // Box2D chains collide on the right of their winding. Flame's y axis
    // points down, so left-to-right surface segments face upward on screen.
    // The walls run all the way down past the pit floor, so nothing that
    // falls into a pit — a limp body included — can slip under a bank.
    //
    // An open Box2D v3 chain uses its first and last points only as ghost
    // anchors that smooth the ends; the segments touching them do not
    // collide. So each wall gets one extra point below it, as its ghost,
    // and the walls themselves are solid.
    final List<Vector2> surface = segment.surface;
    const double bottom = GameConfig.levelHeight + 1;
    final List<Vector2> points = [
      Vector2(surface.first.x, bottom + 1),
      Vector2(surface.first.x, bottom),
      for (final point in surface) point.clone(),
      Vector2(surface.last.x, bottom),
      Vector2(surface.last.x, bottom + 1),
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

  // ---------------------------------------------------------------------------
  // The drawn edge (world metres; the body sits at the origin)
  // ---------------------------------------------------------------------------

  static double _hash(double x) {
    final double value = math.sin(x * 91.7 + 47.3) * 43758.5453;
    return value - value.floorToDouble();
  }

  /// How far the drawn surface sits from the collision surface at [x]:
  /// positive is lower. Mostly a centimetre or two of crumbs, with the
  /// occasional stone or clod standing a few centimetres proud.
  static double roughness(double x) {
    double y =
        0.007 * math.sin(x * 9.3) +
        0.005 * math.sin(x * 23.9 + 1.7) +
        0.003 * math.sin(x * 57.1 + 0.4) +
        0.004;
    // Stones: every metre or so, a rounded bump of a few centimetres.
    final double cell = (x / 0.9).floorToDouble();
    if (_hash(cell) < 0.45) {
      final double centre = (cell + 0.2 + _hash(cell + 3.3) * 0.6) * 0.9;
      final double radius = 0.05 + _hash(cell + 5.1) * 0.09;
      final double d = (x - centre) / radius;
      if (d.abs() < 1) {
        y -= (0.012 + _hash(cell + 7.9) * 0.022) * math.sqrt(1 - d * d);
      }
    }
    return y;
  }

  /// The drawn ground height at [x], the collision surface plus [roughness].
  double drawnHeightAt(double x) => segment.heightAt(x) + roughness(x);

  Path _buildOutline() {
    final Path path = Path();
    final double bottom = GameConfig.levelHeight + 1;
    final double left = segment.left;
    final double right = segment.right;
    final double leftY = segment.heightAt(left);
    final double rightY = segment.heightAt(right);

    path.moveTo(left + (pitOnLeft ? 0.12 : 0), bottom);
    if (pitOnLeft) {
      _cliff(path, left, leftY, bottom, direction: 1, rising: true);
    } else {
      path.lineTo(left, leftY);
    }
    const double step = 0.06;
    for (double x = left + step; x < right; x += step) {
      path.lineTo(x, drawnHeightAt(x));
    }
    if (pitOnRight) {
      _cliff(path, right, rightY, bottom, direction: -1, rising: false);
    } else {
      path
        ..lineTo(right, rightY)
        ..lineTo(right, bottom);
    }
    path.close();
    return path;
  }

  /// A pit face: a lip of turf that overhangs by a few centimetres, then a
  /// crumbling, undercut wall. [direction] points into the bank.
  void _cliff(
    Path path,
    double edgeX,
    double lipY,
    double bottom, {
    required double direction,
    required bool rising,
  }) {
    final double seed = edgeX * 3.1;
    final points = <Offset>[];
    for (var i = 0; i <= 40; i++) {
      final double depth = math.pow(i / 40, 1.6) * (bottom - lipY);
      final double t = depth / (bottom - lipY);
      // Lip overhang, then the undercut belly above the stakes, then back
      // out again where the bank meets the pit floor.
      final double belly = math.min(1, depth / (pitDepth + 0.5));
      double inset =
          -0.035 * math.exp(-depth * 8) +
          0.09 * math.sin(belly * math.pi) * (1 - t * 0.5);
      // Jagged, like broken rock and packed roots, not a smooth curve.
      inset += (_hash(seed + i * 1.7) - 0.5) * 0.09 * math.min(1, depth * 3);
      points.add(Offset(edgeX + direction * inset, lipY + depth));
    }
    final ordered = rising ? points.reversed : points;
    for (final point in ordered) {
      path.lineTo(point.dx, point.dy);
    }
  }

  List<_Root> _buildRoots() {
    final roots = <_Root>[];
    for (final (edgeX, dir, has) in [
      (segment.left, 1.0, pitOnLeft),
      (segment.right, -1.0, pitOnRight),
    ]) {
      if (!has) continue;
      final double lipY = segment.heightAt(edgeX);
      final random = math.Random((edgeX * 977).round());
      final int count = 4 + random.nextInt(4);
      for (var i = 0; i < count; i++) {
        final double depth = 0.05 + random.nextDouble() * 0.5;
        roots.add(
          _Root(
            x: edgeX + dir * (0.02 + random.nextDouble() * 0.12),
            y: lipY + depth,
            length: 0.25 + random.nextDouble() * 0.9,
            curl: (random.nextDouble() - 0.5) * 0.5,
            width: 0.01 + random.nextDouble() * 0.018,
            phase: random.nextDouble() * 6,
          ),
        );
      }
    }
    return roots;
  }

  @override
  void render(Canvas canvas) {
    // A bank wholly off screen draws nothing: its outline has hundreds of
    // vertices, and on the web every drawn path costs real CPU time.
    final Rect? visible = _camera?.visibleWorldRect;
    if (visible != null &&
        (segment.right + 0.6 < visible.left ||
            segment.left - 0.6 > visible.right)) {
      return;
    }
    canvas.drawPath(_outline, paint);

    // Roots hanging into a pit, stirring slowly.
    for (final root in _roots) {
      final double sway = math.sin(wind.time * 0.9 + root.phase) * 0.04;
      // A fresh Path per root: the web renderer keeps a reference to a drawn
      // path, so rebuilding one object would redraw only the last root.
      final rootPath = Path()
        ..moveTo(root.x, root.y)
        ..quadraticBezierTo(
          root.x + root.curl * root.length * 0.5 + sway * 0.5,
          root.y + root.length * 0.5,
          root.x + root.curl * root.length + sway,
          root.y + root.length,
        );
      _rootPaint.strokeWidth = root.width;
      canvas.drawPath(rootPath, _rootPaint);
    }

    final double left = math.max(segment.left, (visible?.left ?? -1e9) - 0.6);
    final double right = math.min(segment.right, (visible?.right ?? 1e9) + 0.6);
    if (left >= right) return;
    // Built fresh each frame: the web renderer records drawn paths by
    // reference, so a path must not be changed once it has been drawn.
    final grass = Path();
    GrassPainter.addBlades(
      grass,
      left: left,
      right: right,
      surface: (x) =>
          x < segment.left || x > segment.right ? null : drawnHeightAt(x),
      style: GrassStyle.back,
      wind: wind,
    );
    canvas.drawPath(grass, paint);
  }
}

class _Root {
  const _Root({
    required this.x,
    required this.y,
    required this.length,
    required this.curl,
    required this.width,
    required this.phase,
  });
  final double x, y, length, curl, width, phase;
}

/// The sparse, short grass that grows in front of the boy and hides his
/// feet, drawn after everything else in the level.
class FrontGrass extends Component {
  FrontGrass({required this.banks, required this.wind}) : super(priority: 50);

  final List<HillGround> banks;
  final GrassWind wind;
  final Paint _paint = Paint()..color = HillGround.earthColor;
  CameraComponent? _camera;

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
  }

  @override
  void render(Canvas canvas) {
    final Rect? visible = _camera?.visibleWorldRect;
    // Built fresh each frame: the web renderer records drawn paths by
    // reference, so a path must not be changed once it has been drawn.
    final path = Path();
    for (final bank in banks) {
      final segment = bank.segment;
      final double left = math.max(segment.left, (visible?.left ?? -1e9) - 0.3);
      final double right = math.min(
        segment.right,
        (visible?.right ?? 1e9) + 0.3,
      );
      if (left >= right) continue;
      GrassPainter.addBlades(
        path,
        left: left,
        right: right,
        surface: (x) => x < segment.left || x > segment.right
            ? null
            : bank.drawnHeightAt(x) + 0.03,
        style: GrassStyle.front,
        wind: wind,
      );
    }
    canvas.drawPath(path, _paint);
  }
}
