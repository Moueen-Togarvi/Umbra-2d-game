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
    this.bottom = GameConfig.levelHeight + 1,
    this.bare = false,
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

  /// How far down the bank's earth and its walls reach.
  final double bottom;

  /// A floor of stone flags, not earth: no grass, no roots, no clods.
  final bool bare;

  late final Path _outline = _buildOutline();
  late final List<_Root> _roots = bare ? const [] : _buildRoots();
  late final List<_Root> _lipBlades = bare ? const [] : _buildLipBlades();

  /// Clods hanging under the pit lips and stones half buried along the
  /// bank, built once.
  late final Path _details = bare ? Path() : _buildDetails();
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
    // Pebbles: every metre or so, a rounded bump of a few centimetres
    // that the feet stand on like the rest of the ground.
    final double cell = (x / 0.9).floorToDouble();
    if (_hash(cell) < 0.55) {
      final double centre = (cell + 0.2 + _hash(cell + 3.3) * 0.6) * 0.9;
      final double radius = 0.06 + _hash(cell + 5.1) * 0.10;
      final double d = (x - centre) / radius;
      if (d.abs() < 1) {
        y -= (0.015 + _hash(cell + 7.9) * 0.03) * math.sqrt(1 - d * d);
      }
    }
    return y;
  }

  /// The drawn ground height at [x], the collision surface plus [roughness].
  double drawnHeightAt(double x) => segment.heightAt(x) + roughness(x);

  Path _buildOutline() {
    final Path path = Path();
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
    // A pit's lip rounds off the last few centimetres (see [_cliff]).
    final double topEnd = pitOnRight ? right - 0.06 : right;
    for (double x = left + step; x < topEnd; x += step) {
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

  /// A pit face. The top of the bank rounds over the edge into a lip of
  /// turf that overhangs by a few centimetres, with earth crumbled away
  /// under it; below, the wall is broken soil — undercut, stepped where it
  /// has slumped, with stones standing out of it — that tapers back out to
  /// meet the floor of the pit. [direction] points into the bank. Below
  /// the lip it stays inside the collision wall, apart from a stone or two.
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
    Offset at(double inset, double depth) =>
        Offset(edgeX + direction * inset, lipY + depth);
    // The lip: the ground rounds over the edge, the turf sticks out, and
    // the earth under it has crumbled back.
    points.addAll([
      Offset(edgeX + direction * 0.06, drawnHeightAt(edgeX + direction * 0.06)),
      at(0.035, 0.004),
      at(0.008, 0.012),
      at(-0.022, 0.026),
      at(-0.03, 0.045),
      at(-0.012, 0.062),
      at(0.02, 0.078),
      at(0.035, 0.1),
    ]);
    // Embedded stones: a few rounded lumps standing out of the face.
    final stones = <(double, double, double)>[];
    for (var k = 0; k < 3; k++) {
      if (_hash(seed + k * 5.3) < 0.35) continue;
      stones.add((
        0.25 + _hash(seed + k * 2.9) * (pitDepth - 0.1),
        0.04 + _hash(seed + k * 7.1) * 0.05,
        0.025 + _hash(seed + k * 1.7) * 0.03,
      ));
    }
    const int count = 56;
    final double span = bottom - lipY;
    for (var i = 1; i <= count; i++) {
      final double depth = 0.1 + math.pow(i / count, 1.7) * (span - 0.1);
      final double t = depth / span;
      // Undercut most at mid-depth, back out at the bottom of the pit.
      final double belly = (depth / (pitDepth + 0.6)).clamp(0.0, 1.0);
      double inset = 0.035 + 0.13 * math.sin(belly * math.pi) * (1 - t * 0.4);
      // Slumped layers, a step every 30–40 cm.
      inset += 0.03 * math.sin(depth * 8.3 + seed);
      // Broken rock and packed roots, not a smooth curve.
      inset += (_hash(seed + i * 1.7) - 0.5) * 0.06;
      for (final (centre, radius, out) in stones) {
        final double d = (depth - centre) / radius;
        if (d.abs() < 1) inset -= out * math.sqrt(1 - d * d);
      }
      points.add(at(math.max(-0.05, inset), depth));
    }
    final ordered = rising ? points.reversed : points;
    for (final point in ordered) {
      path.lineTo(point.dx, point.dy);
    }
  }

  /// Roots hanging out of the pit faces into the dark: thick near the lip,
  /// some forked, swaying slowly.
  List<_Root> _buildRoots() {
    final roots = <_Root>[];
    for (final (edgeX, dir, has) in [
      (segment.left, 1.0, pitOnLeft),
      (segment.right, -1.0, pitOnRight),
    ]) {
      if (!has) continue;
      final double lipY = segment.heightAt(edgeX);
      final random = math.Random((edgeX * 977).round());
      final int count = 8 + random.nextInt(7);
      for (var i = 0; i < count; i++) {
        final double depth = 0.06 + math.pow(random.nextDouble(), 1.5) * 0.7;
        final double nearTop = 1 - (depth / 0.76).clamp(0.0, 1.0);
        roots.add(
          _Root(
            x: edgeX + dir * (0.03 + random.nextDouble() * 0.08),
            y: lipY + depth,
            length: 0.18 + random.nextDouble() * (0.5 + 0.6 * nearTop),
            curl: -dir * (0.15 + random.nextDouble() * 0.35),
            width: 0.008 + random.nextDouble() * 0.012 + 0.012 * nearTop,
            phase: random.nextDouble() * 6,
            fork: random.nextDouble() < 0.4
                ? 0.3 + random.nextDouble() * 0.4
                : 0,
          ),
        );
      }
    }
    return roots;
  }

  /// Grass on the lip that droops over the edge into the pit.
  List<_Root> _buildLipBlades() {
    final blades = <_Root>[];
    for (final (edgeX, dir, has) in [
      (segment.left, 1.0, pitOnLeft),
      (segment.right, -1.0, pitOnRight),
    ]) {
      if (!has) continue;
      final random = math.Random((edgeX * 613).round());
      final int count = 6 + random.nextInt(4);
      for (var i = 0; i < count; i++) {
        final double x = edgeX + dir * random.nextDouble() * 0.05;
        blades.add(
          _Root(
            x: x,
            y: drawnHeightAt(x) + 0.01,
            length: 0.07 + random.nextDouble() * 0.12,
            curl: -dir * (0.5 + random.nextDouble() * 0.6),
            width: 0.006 + random.nextDouble() * 0.006,
            phase: random.nextDouble() * 6,
          ),
        );
      }
    }
    return blades;
  }

  Path _buildDetails() {
    final details = Path();
    // Clods of earth hanging under each lip.
    for (final (edgeX, dir, has) in [
      (segment.left, 1.0, pitOnLeft),
      (segment.right, -1.0, pitOnRight),
    ]) {
      if (!has) continue;
      final double lipY = segment.heightAt(edgeX);
      final random = math.Random((edgeX * 331).round());
      final int clods = 2 + random.nextInt(3);
      for (var i = 0; i < clods; i++) {
        details.addOval(
          Rect.fromCircle(
            center: Offset(
              edgeX - dir * (0.01 + random.nextDouble() * 0.02),
              lipY + 0.05 + random.nextDouble() * 0.05,
            ),
            radius: 0.01 + random.nextDouble() * 0.016,
          ),
        );
      }
    }
    // Stones half buried along the bank, kept away from the pit lips.
    final double from = segment.left + (pitOnLeft ? 1.2 : 0.4);
    final double to = segment.right - (pitOnRight ? 1.2 : 0.4);
    for (double cell = (from / 1.1).ceilToDouble(); cell * 1.1 < to; cell++) {
      if (_hash(cell * 1.31 + 17.7) > 0.3) continue;
      final double cx = (cell + 0.2 + _hash(cell + 9.1) * 0.6) * 1.1;
      if (cx < from || cx > to) continue;
      final double width = 0.12 + math.pow(_hash(cell + 4.4), 2) * 0.34;
      final double tall = width * (0.45 + _hash(cell + 6.6) * 0.3);
      // Sunk to 40% of its height into the soil.
      final double baseY = drawnHeightAt(cx) + tall * 0.4;
      final stone = Path();
      const int sides = 11;
      for (var k = 0; k <= sides; k++) {
        final double a = math.pi + k / sides * math.pi;
        final double bump = 1 + (_hash(cell * 3.7 + k) - 0.5) * 0.22;
        final double x = cx + math.cos(a) * width / 2 * bump;
        // Flatter on top, like a weathered stone.
        final double y =
            baseY + math.sin(a) * tall * bump * (1 - 0.15 * math.sin(a).abs());
        k == 0 ? stone.moveTo(x, y) : stone.lineTo(x, y);
      }
      stone.close();
      details.addPath(stone, Offset.zero);
    }
    return details;
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
    canvas.drawPath(_details, paint);

    // Roots hanging into a pit, stirring slowly, and grass drooping over
    // the lips: tapered shapes, all in one path, so a pit costs one draw.
    // Built fresh each frame: the web renderer records drawn paths by
    // reference, so a path must not be changed once it has been drawn.
    bool seen(double x) =>
        visible == null || (x > visible.left - 1.5 && x < visible.right + 1.5);
    final hanging = Path();
    var any = false;
    for (final root in _roots) {
      if (!seen(root.x)) continue;
      any = true;
      final double sway = math.sin(wind.time * 0.9 + root.phase) * 0.04;
      final double endX = root.x + root.curl * root.length + sway;
      final double endY = root.y + root.length;
      _taperedCurve(
        hanging,
        Offset(root.x, root.y),
        Offset(
          root.x + root.curl * root.length * 0.5 + sway * 0.5,
          root.y + root.length * 0.5,
        ),
        Offset(endX, endY),
        root.width,
      );
      if (root.fork > 0) {
        // A thinner side root splitting off part way down.
        final double fx = root.x + (endX - root.x) * root.fork * 0.8;
        final double fy = root.y + root.length * root.fork;
        _taperedCurve(
          hanging,
          Offset(fx, fy),
          Offset(fx - root.curl * 0.12, fy + root.length * 0.2),
          Offset(fx - root.curl * 0.05 + sway * 0.6, fy + root.length * 0.35),
          root.width * 0.6,
        );
      }
    }
    for (final blade in _lipBlades) {
      if (!seen(blade.x)) continue;
      any = true;
      final double sway = math.sin(wind.time * 1.7 + blade.phase) * 0.012;
      _taperedCurve(
        hanging,
        Offset(blade.x, blade.y),
        Offset(
          blade.x + blade.curl * blade.length * 0.6,
          blade.y - blade.length * 0.35,
        ),
        Offset(
          blade.x + blade.curl * blade.length + sway,
          blade.y + blade.length * 0.45,
        ),
        blade.width,
      );
    }
    if (any) canvas.drawPath(hanging, paint);

    if (bare) return;
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

/// Adds to [path] a filled shape along the quadratic curve [a]–[b]–[c],
/// [width] wide at [a] and tapering to a point at [c].
void _taperedCurve(Path path, Offset a, Offset b, Offset c, double width) {
  const int samples = 6;
  final left = <Offset>[], right = <Offset>[];
  for (var i = 0; i <= samples; i++) {
    final double t = i / samples, u = 1 - t;
    final point = a * (u * u) + b * (2 * u * t) + c * (t * t);
    final tangent = (b - a) * (2 * u) + (c - b) * (2 * t);
    final double length = tangent.distance;
    final normal = length < 1e-9
        ? Offset.zero
        : Offset(-tangent.dy / length, tangent.dx / length);
    final double half = width / 2 * (1 - t * 0.9);
    left.add(point + normal * half);
    right.add(point - normal * half);
  }
  path.moveTo(left.first.dx, left.first.dy);
  for (final point in left.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  for (final point in right.reversed) {
    path.lineTo(point.dx, point.dy);
  }
  path.close();
}

class _Root {
  const _Root({
    required this.x,
    required this.y,
    required this.length,
    required this.curl,
    required this.width,
    required this.phase,
    this.fork = 0,
  });
  final double x, y, length, curl, width, phase;

  /// Where along it a side root splits off, or 0 for none.
  final double fork;
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
