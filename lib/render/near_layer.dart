import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart';

/// What hangs close to the camera in a place.
enum NearKind {
  /// Out in the open: branches and leaves.
  branches,

  /// In a cave: stalactites and roots.
  roots,

  /// In a castle: chains and the rags of old webs.
  chains,
}

/// Things very close to the camera and out of focus, hanging into the top
/// of the picture: drawn black and soft, and sliding past a little faster
/// than the world as the camera goes (they are nearer). Only along the
/// top, and only so far down, so nothing that matters is ever hidden.
class NearLayer extends Component {
  NearLayer({required this.kind, required this.width, this.seed = 0})
    : super(priority: 70);

  final NearKind kind;

  /// The chapter's width, metres: things are spread along all of it.
  final double width;
  final int seed;

  /// How much faster than the world they pass (they are this much nearer).
  static const double nearness = 0.4;

  /// The deepest anything reaches down, as a share of the view's height.
  static const double reach = 0.16;

  CameraComponent? _camera;
  late final List<(double, Path)> _items = _build();
  final Paint _solid = Paint()..color = const Color(0xFF050505);
  final Paint _soft = Paint()..color = const Color(0x66050505);

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
  }

  /// Each thing, at its x along the chapter, as a path hanging from y 0
  /// down to at most 1 (the [reach]), its width in the same units.
  List<(double, Path)> _build() {
    final random = math.Random(seed * 101 + kind.index);
    final items = <(double, Path)>[];
    var x = 6 + random.nextDouble() * 6;
    while (x < width - 4) {
      items.add((x, _shape(random)));
      x += 9 + random.nextDouble() * 14;
    }
    return items;
  }

  Path _shape(math.Random random) {
    final path = Path();
    switch (kind) {
      case NearKind.branches:
        // A bough across the top, sagging, with leaves hanging off it.
        final double span = 1.6 + random.nextDouble() * 1.4;
        final double sag = 0.25 + random.nextDouble() * 0.25;
        path
          ..moveTo(-span, -0.05)
          ..quadraticBezierTo(0, sag * 2, span, -0.05)
          ..lineTo(span, 0.04)
          ..quadraticBezierTo(0, sag * 2 + 0.12, -span, 0.04)
          ..close();
        for (var k = 0; k < 9; k++) {
          final double t = -0.8 + k * 0.2 + (random.nextDouble() - 0.5) * 0.1;
          final double lx = t * span;
          final double ly = sag * (1 - t * t) + 0.02;
          final double len = 0.12 + random.nextDouble() * 0.22;
          final double lean = (random.nextDouble() - 0.5) * 0.12;
          path
            ..moveTo(lx - 0.035, ly)
            ..quadraticBezierTo(
              lx - 0.06 + lean,
              ly + len * 0.6,
              lx + lean,
              ly + len,
            )
            ..quadraticBezierTo(
              lx + 0.06 + lean,
              ly + len * 0.6,
              lx + 0.035,
              ly,
            )
            ..close();
        }
      case NearKind.roots:
        // Stalactites from the roof, and a root or two between them.
        final int count = 2 + random.nextInt(3);
        for (var k = 0; k < count; k++) {
          final double cx = (k - (count - 1) / 2) * 0.32;
          final double w = 0.07 + random.nextDouble() * 0.09;
          final double len = 0.35 + random.nextDouble() * 0.6;
          path
            ..moveTo(cx - w, -0.05)
            ..quadraticBezierTo(cx - w * 0.4, len * 0.6, cx, len)
            ..quadraticBezierTo(cx + w * 0.4, len * 0.6, cx + w, -0.05)
            ..close();
        }
        path.addRect(Rect.fromLTRB(-0.8, -0.1, 0.8, 0.04));
        final double rx = (random.nextDouble() - 0.5) * 0.6;
        path
          ..moveTo(rx - 0.02, 0)
          ..cubicTo(rx + 0.1, 0.3, rx - 0.12, 0.5, rx + 0.03, 0.85)
          ..lineTo(rx + 0.045, 0.84)
          ..cubicTo(rx - 0.09, 0.5, rx + 0.13, 0.3, rx + 0.02, 0)
          ..close();
      case NearKind.chains:
        // A chain or two hanging down, and a torn web in a corner.
        final int count = 1 + random.nextInt(2);
        for (var k = 0; k < count; k++) {
          final double cx = (k - (count - 1) / 2) * 0.7;
          final double len = 0.5 + random.nextDouble() * 0.45;
          for (double y = 0; y < len; y += 0.07) {
            final bool flat = (y / 0.07).round().isEven;
            path.addOval(
              Rect.fromCenter(
                center: Offset(cx, y + 0.035),
                width: flat ? 0.07 : 0.03,
                height: 0.09,
              ),
            );
          }
        }
        final double wx = 0.6 + random.nextDouble() * 0.4;
        for (var k = 0; k < 5; k++) {
          final double a = k / 4 * math.pi / 2;
          path
            ..moveTo(wx, -0.02)
            ..lineTo(wx - math.cos(a) * 0.5, math.sin(a) * 0.4)
            ..lineTo(wx - math.cos(a) * 0.5 + 0.012, math.sin(a) * 0.4 + 0.012)
            ..lineTo(wx + 0.012, -0.008)
            ..close();
        }
    }
    return path;
  }

  @override
  void render(Canvas canvas) {
    final Rect? view = _camera?.visibleWorldRect;
    if (view == null) return;
    final double cx = view.center.dx;
    // Sized to the picture, not the world: as near as this, a thing fills
    // the same share of the screen whatever the zoom.
    final double scale = view.height * reach;
    for (final (x, path) in _items) {
      final double at = cx + (x - cx) * (1 + nearness);
      if (at < view.left - scale * 4 || at > view.right + scale * 4) continue;
      canvas
        ..save()
        ..translate(at, view.top)
        ..scale(scale);
      // Out of focus: a soft rim round a solid middle.
      canvas
        ..save()
        ..scale(1.04)
        ..drawPath(path, _soft)
        ..restore()
        ..drawPath(path, _solid)
        ..restore();
    }
  }
}
