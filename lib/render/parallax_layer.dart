import 'dart:ui';

import 'package:flame/components.dart';

/// One tiling strip of silhouette art, drawn in screen space and scrolled
/// against the camera at a fraction of the camera's speed.
///
/// The image is black with the silhouette in its alpha channel, so the layer's
/// *distance* is nothing more than how opaque it is drawn: a far ridge is a
/// faint grey ghost, a near tree is almost solid. That is exactly how fog
/// works, which is why the reference art reads as deep with only two colours.
///
/// ## Why not Flame's ParallaxComponent
///
/// Flame's parallax is driven by a velocity over time, which suits an
/// endless runner. This game's backdrop has to track a camera that stops,
/// reverses and eases, so the offset is derived from the camera position each
/// frame instead. Doing it by hand is a few lines and leaves every number
/// tunable.
class ParallaxLayer {
  ParallaxLayer({
    required this.image,
    required this.speed,
    required this.opacity,
    required this.heightFraction,
    this.bottomFraction = 1.0,
    this.anchorTop = false,
    this.verticalSpeed = 0.0,
    this.tile = true,
    this.scaleToWidth = false,
    this.phase = 0.0,
  });

  /// The baked art. Black, silhouette in alpha.
  final Image image;

  /// How fast the layer scrolls relative to the camera. 0 is pinned to the
  /// horizon, 1 moves with the world, more than 1 is closer than the world.
  final double speed;

  /// How solid the layer is. Lower is further away.
  final double opacity;

  /// Height of the strip as a fraction of the viewport height.
  final double heightFraction;

  /// Where the bottom of the strip sits, as a fraction of the viewport
  /// height. Ignored when [anchorTop] is set.
  final double bottomFraction;

  /// Pin the strip's top to the top of the screen instead — for things that
  /// hang down, like a canopy.
  final bool anchorTop;

  /// How much the layer drifts vertically with the camera. Small values sell
  /// the depth when the camera rises to follow a jump.
  final double verticalSpeed;

  /// Repeat the strip horizontally. Off for a single framing image.
  final bool tile;

  /// Scale the image to cover the whole viewport rather than by height. Used
  /// with [tile] off for full-screen framing art.
  final bool scaleToWidth;

  /// A fixed horizontal shift in fractions of a tile, so two layers that share
  /// an image do not line up.
  final double phase;

  final Paint _paint = Paint()..filterQuality = FilterQuality.low;

  /// Draws the layer into a [viewport] of the given size, for a camera whose
  /// world position is [cameraPx] *in screen pixels*.
  void render(
    Canvas canvas,
    Vector2 viewport,
    Vector2 cameraPx, {
    double opacityScale = 1.0,
  }) {
    final double alpha = (opacity * opacityScale).clamp(0.0, 1.0);
    if (alpha <= 0.002) {
      return;
    }
    _paint.color = Color.fromRGBO(0, 0, 0, alpha);

    // "Cover" scaling for framing art: big enough on both axes that no edge
    // of the image is ever inside the viewport.
    final double scale = scaleToWidth
        ? (viewport.x / image.width > viewport.y / image.height
              ? viewport.x / image.width
              : viewport.y / image.height)
        : (viewport.y * heightFraction) / image.height;
    final double drawW = image.width * scale;
    final double drawH = image.height * scale;

    final double top = anchorTop
        ? -cameraPx.y * verticalSpeed
        : viewport.y * bottomFraction - drawH - cameraPx.y * verticalSpeed;

    final Rect src = Rect.fromLTWH(
      0,
      0,
      image.width.toDouble(),
      image.height.toDouble(),
    );

    if (!tile) {
      // A single image, slightly oversized so its edges never show when it
      // drifts with the camera.
      const double bleed = 1.06;
      final double w = drawW * bleed;
      final double h = drawH * bleed;
      final double x = -(w - viewport.x) / 2 - cameraPx.x * speed;
      final double y = -(h - viewport.y) / 2 - cameraPx.y * verticalSpeed;
      canvas.drawImageRect(image, src, Rect.fromLTWH(x, y, w, h), _paint);
      return;
    }

    // Tile from just left of the screen until just past its right edge. The
    // modulo keeps the start inside one tile of the origin, so scrolling for
    // an hour never accumulates a huge offset.
    // A layer hung from the top edge may be pushed down when the camera
    // rises; its top row is solid, so filling the gap it leaves with the same
    // colour is seamless.
    if (anchorTop && top > 0) {
      canvas.drawRect(Rect.fromLTWH(0, 0, viewport.x, top + 1), _paint);
    }

    final double offset = -cameraPx.x * speed + phase * drawW;
    double x = offset % drawW;
    if (x > 0) x -= drawW;
    while (x < viewport.x) {
      canvas.drawImageRect(
        image,
        src,
        Rect.fromLTWH(x, top, drawW + 0.5, drawH),
        _paint,
      );
      x += drawW;
    }
  }
}
