import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/flame.dart';

/// Eight isolated RGBA puppet parts, shared by every instance of a character.
/// Alpha bounds are measured once at load time; no pixel work occurs per frame.
class NpcAtlas {
  NpcAtlas._(this.image, this.parts);

  final Image image;
  final List<Rect> parts;
  static final Map<String, NpcAtlas> _ready = {};
  static final Map<String, Future<NpcAtlas>> _loading = {};

  static Future<NpcAtlas> load(String name) async {
    final ready = _ready[name];
    if (ready != null) return ready;
    try {
      final art = await (_loading[name] ??= _decode(name));
      _ready[name] = art;
      return art;
    } finally {
      // Do not retain a completed Future bound to an old game/test Zone.
      // Retain only the decoded atlas, whose owner is Flame's image cache.
      _loading.remove(name);
    }
  }

  static Future<NpcAtlas> _decode(String name) async {
    final image = await Flame.images.load('characters/${name}_rig.png');
    final data = await image.toByteData(format: ImageByteFormat.rawRgba);
    if (data == null) throw StateError('Cannot read $name puppet atlas');
    final parts = <Rect>[];
    for (var cell = 0; cell < 8; cell++) {
      final x0 = (cell % 4) * image.width ~/ 4;
      final y0 = (cell ~/ 4) * image.height ~/ 2;
      final x1 = ((cell % 4) + 1) * image.width ~/ 4;
      final y1 = ((cell ~/ 4) + 1) * image.height ~/ 2;
      int left = x1, top = y1, right = x0, bottom = y0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          if (data.getUint8((y * image.width + x) * 4 + 3) < 24) continue;
          left = math.min(left, x);
          top = math.min(top, y);
          right = math.max(right, x + 1);
          bottom = math.max(bottom, y + 1);
        }
      }
      if (right <= left || bottom <= top) {
        throw StateError('Empty $name puppet part $cell');
      }
      parts.add(
        Rect.fromLTRB(
          math.max(x0, left - 2).toDouble(),
          math.max(y0, top - 2).toDouble(),
          math.min(x1, right + 2).toDouble(),
          math.min(y1, bottom + 2).toDouble(),
        ),
      );
    }
    return NpcAtlas._(image, parts);
  }

  Rect _source(int part, Rect? region) {
    final source = parts[part];
    if (region == null) return source;
    return Rect.fromLTWH(
      source.left + region.left * source.width,
      source.top + region.top * source.height,
      region.width * source.width,
      region.height * source.height,
    );
  }

  void draw(
    Canvas canvas,
    int part,
    Rect target,
    Paint paint, {
    Rect? sourceUV,
  }) => canvas.drawImageRect(image, _source(part, sourceUV), target, paint);

  /// The part's neutral bone points down. Slight overlap hides the joints.
  void bone(
    Canvas canvas,
    int part,
    Offset from,
    Offset to,
    double width,
    Paint paint, {
    Offset? startAnchor,
    Offset? endAnchor,
    Rect? sourceUV,
  }) {
    final delta = to - from;
    if (delta.distanceSquared < 1e-12) return;
    if (startAnchor != null && endAnchor != null) {
      final source = _source(part, sourceUV);
      final start = Offset(
        startAnchor.dx * source.width,
        startAnchor.dy * source.height,
      );
      final end = Offset(
        endAnchor.dx * source.width,
        endAnchor.dy * source.height,
      );
      final axis = end - start;
      if (axis.distanceSquared < 1e-12) return;
      // Artwork is not necessarily centred or vertical inside its alpha
      // bounds. Match its two actual sockets to the two skeleton joints.
      canvas.save();
      canvas.translate(from.dx, from.dy);
      canvas.rotate(math.atan2(delta.dy, delta.dx) - math.pi / 2);
      canvas.scale(width / source.width, delta.distance / axis.distance);
      canvas.rotate(math.pi / 2 - math.atan2(axis.dy, axis.dx));
      canvas.translate(-start.dx, -start.dy);
      draw(
        canvas,
        part,
        Rect.fromLTWH(0, 0, source.width, source.height),
        paint,
        sourceUV: sourceUV,
      );
      canvas.restore();
      return;
    }
    canvas.save();
    canvas.translate(from.dx, from.dy);
    canvas.rotate(math.atan2(delta.dy, delta.dx) - math.pi / 2);
    draw(
      canvas,
      part,
      Rect.fromLTWH(-width / 2, -.025, width, delta.distance + .05),
      paint,
      sourceUV: sourceUV,
    );
    canvas.restore();
  }

  void hand(
    Canvas canvas,
    int part,
    Offset wrist,
    Offset elbow,
    double width,
    double length,
    Paint paint, {
    double curl = 0,
    Offset? wristAnchor,
    Offset? fingerAnchor,
  }) {
    final delta = wrist - elbow;
    if (wristAnchor != null && fingerAnchor != null) {
      final angle = math.atan2(delta.dy, delta.dx) + curl;
      bone(
        canvas,
        part,
        wrist,
        wrist + Offset(math.cos(angle), math.sin(angle)) * length,
        width,
        paint,
        startAnchor: wristAnchor,
        endAnchor: fingerAnchor,
      );
      return;
    }
    canvas.save();
    canvas.translate(wrist.dx, wrist.dy);
    canvas.rotate(math.atan2(delta.dy, delta.dx) - math.pi / 2 + curl);
    draw(canvas, part, Rect.fromLTWH(-width / 2, -.02, width, length), paint);
    canvas.restore();
  }
}
