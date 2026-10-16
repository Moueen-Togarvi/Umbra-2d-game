import 'dart:math' as math;
import 'dart:ui';

/// One depth of forest standing in the fog, baked once into a small image.
///
/// [depth] is both how small things at that distance look and how slowly
/// they scroll: a layer at 0.3 is drawn at 30% of world scale and moves 30%
/// as fast as the ground under the boy's feet, which is what perspective
/// does. Content is laid out in "layer metres" along a tile [tileWidth] long
/// that repeats; v = 0 is the layer's ground line, negative is up.
///
/// The blur is baked in, and so the image can be stored at a low resolution:
/// a blurred picture has no fine detail to lose when it is scaled up.
class FogLayerSpec {
  const FogLayerSpec({
    required this.depth,
    required this.tone,
    required this.blur,
    required this.density,
    required this.tileWidth,
    required this.seed,
    required this.trunkSpacing,
    required this.trunkWidth,
    this.vines = false,
    this.foreground = false,
    this.rock = false,
  });

  final double depth;
  final Color tone;

  /// Gaussian blur, in baked pixels.
  final double blur;

  /// Baked pixels per layer metre.
  final double density;
  final double tileWidth;
  final int seed;

  /// Mean gap between trunks, and their (min, max) widths, in layer metres.
  final double trunkSpacing;
  final (double, double) trunkWidth;

  /// Hanging vines and moss from the branches.
  final bool vines;

  /// A layer in front of the world: sparse huge trunks and grass clumps
  /// along the bottom of the screen instead of a forest.
  final bool foreground;

  /// A cave instead of a forest: a roof hung with stalactites, a floor of
  /// stalagmites and the odd pillar joining them.
  final bool rock;
}

class FogLayer {
  FogLayer._(this.spec, this.image, this.vTop, this.vBottom);

  final FogLayerSpec spec;
  final Image image;

  /// The layer-metre span the image covers, top and bottom.
  final double vTop, vBottom;

  final Paint _paint = Paint()..filterQuality = FilterQuality.low;
  final Paint _fill = Paint();

  /// Bakes [spec] for a camera that shows [visibleHeight] metres and whose
  /// centre stays within [maxCameraRise] metres above the ground line.
  ///
  /// Two passes: the sharp forest is drawn with the layer-metre scale, then
  /// that image is blurred with no transform in effect. Impeller scales a
  /// layer's blur by transforms applied inside the layer, so doing both in
  /// one pass blurred the forest away entirely on Android.
  ///
  /// `toImageSync` keeps the result on the GPU. The asynchronous `toImage`
  /// gave the web renderer a CPU image that was uploaded again every frame,
  /// which cost about a quarter of the frame rate.
  static FogLayer bake(
    FogLayerSpec spec, {
    required double visibleHeight,
    required double maxCameraRise,
  }) {
    final double vTop = -maxCameraRise - visibleHeight / 2 / spec.depth - 1.5;
    final double vBottom = spec.foreground ? 4.0 : 2.0;
    final int width = (spec.tileWidth * spec.density).round();
    final int height = ((vBottom - vTop) * spec.density).round();
    // The sharp pass is padded on both sides with the neighbouring tiles'
    // content, so the blur wraps seamlessly at the ends.
    final int pad = (spec.blur * 4).ceil();

    final sharpRecorder = PictureRecorder();
    final sharpCanvas = Canvas(sharpRecorder);
    sharpCanvas.translate(pad.toDouble(), 0);
    sharpCanvas.scale(spec.density);
    sharpCanvas.translate(0, -vTop);
    for (final shift in [-spec.tileWidth, 0.0, spec.tileWidth]) {
      sharpCanvas.save();
      sharpCanvas.translate(shift, 0);
      _paintContent(sharpCanvas, spec, vTop);
      sharpCanvas.restore();
    }
    final sharpPicture = sharpRecorder.endRecording();
    final sharp = sharpPicture.toImageSync(width + pad * 2, height);
    sharpPicture.dispose();

    final blurRecorder = PictureRecorder();
    Canvas(blurRecorder).drawImage(
      sharp,
      Offset(-pad.toDouble(), 0),
      Paint()
        ..imageFilter = ImageFilter.blur(
          sigmaX: spec.blur,
          sigmaY: spec.blur,
          tileMode: TileMode.clamp,
        ),
    );
    final blurPicture = blurRecorder.endRecording();
    final image = blurPicture.toImageSync(width, height);
    blurPicture.dispose();
    // The blurred picture holds its own reference to the sharp pass.
    sharp.dispose();
    return FogLayer._(spec, image, vTop, vBottom);
  }

  /// Draws the layer for a camera centred on [camera] (world metres), with
  /// [ppm] screen pixels per world metre and the layer's ground line at
  /// world y [groundY].
  void render(
    Canvas canvas,
    Size screen,
    double cameraX,
    double cameraY,
    double ppm, {
    required double groundY,
    double opacity = 1,
    Color? tint,
  }) {
    final double k = spec.depth;
    final double scale = k * ppm;
    final double halfWidth = screen.width / 2 / scale;
    final double tileWidth = spec.tileWidth;
    final int first = ((cameraX - halfWidth) / tileWidth).floor();
    final int last = ((cameraX + halfWidth) / tileWidth).floor();
    final double top = screen.height / 2 + (groundY + vTop - cameraY) * scale;
    final double bottom =
        screen.height / 2 + (groundY + vBottom - cameraY) * scale;
    final Rect source = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );
    _paint.color = Color.fromRGBO(0, 0, 0, opacity);
    // Baked in its spec's tone; another mood recolours it on the way out.
    final bool recolour = tint != null && tint != spec.tone;
    _paint.colorFilter = recolour
        ? ColorFilter.mode(tint, BlendMode.srcIn)
        : null;
    for (var i = first; i <= last; i++) {
      final double left = screen.width / 2 + (i * tileWidth - cameraX) * scale;
      // A hair of overlap hides the seam between neighbouring tiles.
      canvas.drawImageRect(
        image,
        source,
        Rect.fromLTRB(left - 0.5, top, left + tileWidth * scale + 0.5, bottom),
        _paint,
      );
    }
    if (bottom < screen.height && !spec.foreground) {
      _fill.color = (tint ?? spec.tone).withValues(alpha: opacity);
      canvas.drawRect(
        Rect.fromLTRB(0, bottom - 1, screen.width, screen.height),
        _fill,
      );
    }
  }

  /// Screen y of this layer's ground line.
  double groundLine(
    Size screen,
    double cameraY,
    double ppm, {
    required double groundY,
  }) => screen.height / 2 + (groundY - cameraY) * spec.depth * ppm;

  void dispose() => image.dispose();

  // ---------------------------------------------------------------------------
  // Procedural content, in layer metres
  // ---------------------------------------------------------------------------

  static void _paintContent(Canvas canvas, FogLayerSpec spec, double vTop) {
    final random = math.Random(spec.seed);
    final paint = Paint()
      ..color = spec.tone
      ..isAntiAlias = true;
    final double tile = spec.tileWidth;
    double wave(double u, int cycles, double phase) =>
        math.sin(2 * math.pi * cycles * u / tile + phase);

    if (spec.foreground) {
      _paintForeground(canvas, spec, random, paint, vTop);
      return;
    }
    if (spec.rock) {
      _paintRock(canvas, spec, random, paint, vTop);
      return;
    }

    // The ground at this depth: a low, rolling ridge, periodic over the
    // tile so it wraps.
    final ground = Path()..moveTo(-1, 3);
    for (double u = -1; u <= tile + 1; u += 0.2) {
      final double v =
          0.30 * wave(u, 3, spec.seed * 0.7) +
          0.16 * wave(u, 8, spec.seed * 1.3) +
          0.06 * wave(u, 23, spec.seed * 2.1) -
          0.1;
      ground.lineTo(u, v);
    }
    ground
      ..lineTo(tile + 1, 3)
      ..close();
    canvas.drawPath(ground, paint);

    // Trunks, sparse: most of a LIMBO frame is empty fog.
    double u = random.nextDouble() * spec.trunkSpacing;
    while (u < tile) {
      final (minW, maxW) = spec.trunkWidth;
      final double w =
          minW + (maxW - minW) * math.pow(random.nextDouble(), 1.6);
      _trunk(canvas, paint, random, spec, u, w, vTop);
      u += spec.trunkSpacing * (0.45 + random.nextDouble() * 1.25);
    }
  }

  static void _trunk(
    Canvas canvas,
    Paint paint,
    math.Random random,
    FogLayerSpec spec,
    double u,
    double w,
    double vTop,
  ) {
    final double top = vTop - 1;
    final double lean = (random.nextDouble() - 0.5) * 0.05;
    final double bend = (random.nextDouble() - 0.5) * w * 0.8;
    const int steps = 28;
    final left = <Offset>[];
    final right = <Offset>[];
    for (var i = 0; i <= steps; i++) {
      final double t = i / steps;
      final double v = top + (0.4 - top) * t;
      final double centre =
          u + lean * v + bend * math.sin(t * math.pi) * (1 - t);
      // Root flare: the trunk spreads where it meets the ground.
      final double flare = v > -1.4 * w
          ? math.pow((v + 1.4 * w) / (1.4 * w), 2.2) * 0.9
          : 0.0;
      // Thicker towards the ground, like a real trunk.
      final double half = w / 2 * (0.78 + 0.25 * t + flare);
      final double bark = w * 0.035;
      left.add(Offset(centre - half + (random.nextDouble() - 0.5) * bark, v));
      right.add(Offset(centre + half + (random.nextDouble() - 0.5) * bark, v));
    }
    final path = Path()..moveTo(left.first.dx, left.first.dy);
    for (final p in left.skip(1)) {
      path.lineTo(p.dx, p.dy);
    }
    for (final p in right.reversed) {
      path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(path, paint);

    // At most a couple of branches, long and dead or snapped short.
    final int branches = random.nextDouble() < 0.45 ? 0 : 1 + random.nextInt(2);
    for (var b = 0; b < branches; b++) {
      final double v = top * (0.12 + random.nextDouble() * 0.5) - 2;
      if (v > -2.5) continue;
      final double side = random.nextBool() ? 1 : -1;
      final double angle = 0.35 + random.nextDouble() * 0.75;
      final double length =
          (random.nextDouble() < 0.4 ? 0.6 : 1.8) *
          (1 + random.nextDouble() * 1.6) *
          math.max(0.8, w);
      final double centre = u + lean * v;
      final Offset root = Offset(centre + side * w * 0.35, v);
      final Offset tip = Offset(
        root.dx + side * math.cos(angle) * length,
        v - math.sin(angle) * length,
      );
      _limb(canvas, paint, root, tip, w * 0.18, w * 0.03 + 0.03);
      if (spec.vines && random.nextDouble() < 0.35) {
        _vines(canvas, paint, random, root, tip);
      }
      if (random.nextDouble() < 0.3) {
        final Offset mid = Offset.lerp(root, tip, 0.55)!;
        final Offset twig = Offset(
          mid.dx + side * length * 0.3,
          mid.dy - length * (0.25 + random.nextDouble() * 0.3),
        );
        _limb(canvas, paint, mid, twig, w * 0.06, 0.02);
      }
    }
  }

  static void _vines(
    Canvas canvas,
    Paint paint,
    math.Random random,
    Offset from,
    Offset to,
  ) {
    final stroke = Paint()
      ..color = paint.color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final int count = 1 + random.nextInt(2);
    for (var i = 0; i < count; i++) {
      final Offset anchor = Offset.lerp(
        from,
        to,
        0.4 + random.nextDouble() * 0.5,
      )!;
      final double length = 0.8 + random.nextDouble() * 2.6;
      final double drift = (random.nextDouble() - 0.5) * 0.8;
      stroke.strokeWidth = 0.025 + random.nextDouble() * 0.03;
      // A vine sags from two points on the branch, or hangs free and curls.
      canvas.drawPath(
        Path()
          ..moveTo(anchor.dx, anchor.dy)
          ..cubicTo(
            anchor.dx + drift * 0.2,
            anchor.dy + length * 0.4,
            anchor.dx + drift,
            anchor.dy + length * 0.7,
            anchor.dx + drift * 0.6,
            anchor.dy + length,
          ),
        stroke,
      );
    }
  }

  /// A tapering limb from [a] to [b], [ra] and [rb] half-widths.
  static void _limb(
    Canvas canvas,
    Paint paint,
    Offset a,
    Offset b,
    double ra,
    double rb,
  ) {
    final Offset d = b - a;
    final double length = d.distance;
    if (length < 1e-6) return;
    final Offset n = Offset(-d.dy / length, d.dx / length);
    canvas.drawPath(
      Path()
        ..moveTo(a.dx + n.dx * ra, a.dy + n.dy * ra)
        ..lineTo(b.dx + n.dx * rb, b.dy + n.dy * rb)
        ..lineTo(b.dx - n.dx * rb, b.dy - n.dy * rb)
        ..lineTo(a.dx - n.dx * ra, a.dy - n.dy * ra)
        ..close(),
      paint,
    );
  }

  /// A cave at this depth: a roof hanging down from above the frame with
  /// stalactites dripping from it, a lumpy floor with stalagmites, and now
  /// and then a pillar where the two have grown together. Everything is
  /// periodic over the tile so it wraps.
  static void _paintRock(
    Canvas canvas,
    FogLayerSpec spec,
    math.Random random,
    Paint paint,
    double vTop,
  ) {
    final double tile = spec.tileWidth;
    double wave(double u, int cycles, double phase) =>
        math.sin(2 * math.pi * cycles * u / tile + phase);
    // The top of the frame with the camera at a middling height, and the
    // roof's lower edge a good way below it.
    final double frameTop = vTop + 3;
    final double roof = frameTop * 0.58;

    double roofAt(double u) =>
        roof +
        (-frameTop) *
            (0.07 * wave(u, 2, spec.seed * 0.9) +
                0.05 * wave(u, 5, spec.seed * 1.7) +
                0.015 * wave(u, 17, spec.seed * 2.3));
    double floorAt(double u) =>
        0.35 * wave(u, 3, spec.seed * 0.7) +
        0.2 * wave(u, 9, spec.seed * 1.3) +
        0.07 * wave(u, 26, spec.seed * 2.1) -
        0.15;

    final ceiling = Path()..moveTo(-1, vTop - 1);
    for (double u = -1; u <= tile + 1; u += 0.25) {
      ceiling.lineTo(u, roofAt(u));
    }
    ceiling
      ..lineTo(tile + 1, vTop - 1)
      ..close();
    canvas.drawPath(ceiling, paint);

    final floor = Path()..moveTo(-1, 3);
    for (double u = -1; u <= tile + 1; u += 0.2) {
      floor.lineTo(u, floorAt(u));
    }
    floor
      ..lineTo(tile + 1, 3)
      ..close();
    canvas.drawPath(floor, paint);

    // Stalactites: narrow, slightly crooked cones, in clusters.
    final double span = -roof;
    double u = random.nextDouble() * 2;
    while (u < tile) {
      final int cluster = 1 + random.nextInt(4);
      for (var i = 0; i < cluster; i++) {
        final double x = u + i * (0.3 + random.nextDouble() * 0.6);
        final double length =
            span * (0.05 + math.pow(random.nextDouble(), 2.2) * 0.32);
        final double width = 0.12 + length * (0.12 + random.nextDouble() * 0.1);
        _cone(canvas, paint, random, x, roofAt(x) - 0.2, width, length, 1);
      }
      u += spec.trunkSpacing * (0.3 + random.nextDouble() * 0.9);
    }

    // Stalagmites, shorter and stubbier.
    u = random.nextDouble() * 3;
    while (u < tile) {
      final double length =
          0.4 + math.pow(random.nextDouble(), 1.8) * span * 0.18;
      final double width = 0.3 + length * (0.3 + random.nextDouble() * 0.2);
      _cone(canvas, paint, random, u, floorAt(u) + 0.2, width, length, -1);
      u += spec.trunkSpacing * (0.5 + random.nextDouble() * 1.4);
    }

    // Pillars: a waisted column from floor to roof.
    u = random.nextDouble() * spec.trunkSpacing * 2;
    while (u < tile) {
      final (minW, maxW) = spec.trunkWidth;
      final double w = minW + (maxW - minW) * random.nextDouble();
      final double top = roofAt(u) - 0.5;
      final double bottom = floorAt(u) + 0.5;
      const int steps = 24;
      final left = <Offset>[];
      final right = <Offset>[];
      for (var i = 0; i <= steps; i++) {
        final double t = i / steps;
        final double v = top + (bottom - top) * t;
        // Wide where it meets roof and floor, narrowest a little below
        // the middle, where the drips met.
        final double waist = math.pow((t - 0.58).abs() / 0.58, 1.6).toDouble();
        final double half = w / 2 * (0.42 + 1.1 * waist);
        final double lump = w * 0.06 * math.sin(t * 19 + u);
        left.add(Offset(u - half + lump, v));
        right.add(Offset(u + half + lump * 0.6, v));
      }
      final path = Path()..moveTo(left.first.dx, left.first.dy);
      for (final p in left.skip(1)) {
        path.lineTo(p.dx, p.dy);
      }
      for (final p in right.reversed) {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path..close(), paint);
      u += spec.trunkSpacing * (1.6 + random.nextDouble() * 2.4);
    }
  }

  /// A crooked cone of rock [length] long from a base [width] wide at
  /// ([x], [base]), pointing down (`direction` 1) or up (-1).
  static void _cone(
    Canvas canvas,
    Paint paint,
    math.Random random,
    double x,
    double base,
    double width,
    double length,
    double direction,
  ) {
    final double kink = (random.nextDouble() - 0.5) * width * 0.5;
    final double tip = base + direction * length;
    final double mid = base + direction * length * 0.45;
    canvas.drawPath(
      Path()
        ..moveTo(x - width / 2, base)
        ..quadraticBezierTo(x - width * 0.2 + kink, mid, x + kink * 1.4, tip)
        ..quadraticBezierTo(x + width * 0.22 + kink, mid, x + width / 2, base)
        ..close(),
      paint,
    );
  }

  /// Huge out-of-focus shapes right in front of the lens: the odd trunk
  /// passing across the frame and clumps of grass along its bottom edge.
  static void _paintForeground(
    Canvas canvas,
    FogLayerSpec spec,
    math.Random random,
    Paint paint,
    double vTop,
  ) {
    final double tile = spec.tileWidth;
    double u = random.nextDouble() * spec.trunkSpacing;
    while (u < tile) {
      final (minW, maxW) = spec.trunkWidth;
      final double w = minW + (maxW - minW) * random.nextDouble();
      final double lean = (random.nextDouble() - 0.5) * 0.12;
      final double top = vTop - 1;
      canvas.drawPath(
        Path()
          ..moveTo(u - w / 2 + lean * top, top)
          ..lineTo(u + w / 2 + lean * top, top)
          ..lineTo(u + w * 0.62, 4)
          ..lineTo(u - w * 0.62, 4)
          ..close(),
        paint,
      );
      u += spec.trunkSpacing * (0.6 + random.nextDouble() * 0.9);
    }
    // Grass clumps: tall blades fanning up from below the frame.
    for (var c = 0; c < (tile / 14).round(); c++) {
      final double centre = random.nextDouble() * tile;
      final int blades = 6 + random.nextInt(8);
      for (var i = 0; i < blades; i++) {
        final double rootX = centre + (random.nextDouble() - 0.5) * 1.2;
        final double height = 0.4 + random.nextDouble() * 0.9;
        final double lean = (random.nextDouble() - 0.5) * 0.9;
        final double width = 0.05 + random.nextDouble() * 0.05;
        canvas.drawPath(
          Path()
            ..moveTo(rootX - width, 3.5)
            ..quadraticBezierTo(
              rootX + lean * height * 0.3,
              1.2 - height * 0.5,
              rootX + lean * height,
              1.4 - height,
            )
            ..quadraticBezierTo(
              rootX + lean * height * 0.3 + width,
              1.2 - height * 0.5,
              rootX + width,
              3.5,
            )
            ..close(),
          paint,
        );
      }
    }
  }
}
