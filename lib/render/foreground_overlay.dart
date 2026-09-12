import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';

import '../config/palette.dart';

/// The lens the world is seen through.
///
/// Lives in `camera.viewport`, drawn after the world and before the touch
/// controls. Deliberately little: film grain so flat black is never dead
/// flat, a gentle vignette so the edges recede, and a few dust motes drifting
/// through the light. Anything more in front of the player — foliage, blurred
/// grass — crowds a scene whose whole point is emptiness.
class ForegroundOverlay extends Component {
  ForegroundOverlay({required this.camera}) : super(priority: -10);

  final CameraComponent camera;

  late final Image _grain;

  final math.Random _random = math.Random(3);
  final List<_Mote> _motes = [];
  double _time = 0;

  final Paint _vignettePaint = Paint();
  final Paint _grainPaint = Paint()
    ..color = const Color(0x0AFFFFFF)
    ..filterQuality = FilterQuality.none;
  final Paint _motePaint = Paint();

  @override
  Future<void> onLoad() async {
    _grain = Flame.images.fromCache('grain.png');

    for (var i = 0; i < 22; i++) {
      _motes.add(_Mote.random(_random));
    }
  }

  @override
  void update(double dt) {
    _time += dt;
    for (final mote in _motes) {
      mote.update(dt, _random);
    }
  }

  @override
  void render(Canvas canvas) {
    final Vector2 viewport = camera.viewport.size;
    if (viewport.x <= 0 || viewport.y <= 0) {
      return;
    }
    _renderMotes(canvas, viewport);
    _renderVignette(canvas, viewport);
    _renderGrain(canvas, viewport);
  }

  void _renderMotes(Canvas canvas, Vector2 viewport) {
    for (final mote in _motes) {
      final Offset p = Offset(mote.x * viewport.x, mote.y * viewport.y);
      final double twinkle =
          0.6 + 0.4 * math.sin(_time * mote.twinkle + mote.phase);
      final double alpha = mote.brightness * twinkle;
      // A soft dot: a faint wide halo under a small bright core. Two circles
      // are far cheaper than a blur filter and read the same at this size.
      _motePaint.color = Palette.dust.withValues(alpha: alpha * 0.18);
      canvas.drawCircle(p, mote.radius * 3.2, _motePaint);
      _motePaint.color = Palette.dust.withValues(alpha: alpha);
      canvas.drawCircle(p, mote.radius, _motePaint);
    }
  }

  void _renderVignette(Canvas canvas, Vector2 viewport) {
    final Rect full = Rect.fromLTWH(0, 0, viewport.x, viewport.y);
    _vignettePaint.shader = Gradient.radial(
      Offset(viewport.x * 0.5, viewport.y * 0.42),
      viewport.x * 0.72,
      const [Color(0x00000000), Color(0x00000000), Color(0xB3000000)],
      const [0.0, 0.45, 1.0],
    );
    canvas.drawRect(full, _vignettePaint);
  }

  void _renderGrain(Canvas canvas, Vector2 viewport) {
    // A different offset every frame is what makes it read as film grain
    // rather than as a dirty screen.
    final double ox = -_random.nextDouble() * _grain.width;
    final double oy = -_random.nextDouble() * _grain.height;
    final Rect src = Rect.fromLTWH(
      0,
      0,
      _grain.width.toDouble(),
      _grain.height.toDouble(),
    );
    // Drawn at 2x so the grain is coarse enough to see on a dense phone screen.
    final double tile = _grain.width * 2.0;
    for (double y = oy; y < viewport.y; y += tile) {
      for (double x = ox; x < viewport.x; x += tile) {
        canvas.drawImageRect(
          _grain,
          src,
          Rect.fromLTWH(x, y, tile, tile),
          _grainPaint,
        );
      }
    }
  }
}

/// One drifting speck of dust, in viewport fractions.
class _Mote {
  _Mote({
    required this.x,
    required this.y,
    required this.radius,
    required this.brightness,
    required this.driftX,
    required this.driftY,
    required this.twinkle,
    required this.phase,
  });

  factory _Mote.random(math.Random r) {
    return _Mote(
      x: r.nextDouble(),
      y: r.nextDouble(),
      radius: 1.0 + r.nextDouble() * 2.2,
      brightness: 0.18 + r.nextDouble() * 0.4,
      driftX: (r.nextDouble() - 0.3) * 0.012,
      driftY: (r.nextDouble() - 0.6) * 0.008,
      twinkle: 0.6 + r.nextDouble() * 1.4,
      phase: r.nextDouble() * math.pi * 2,
    );
  }

  double x, y;
  final double radius, brightness, twinkle, phase;
  double driftX, driftY;

  void update(double dt, math.Random r) {
    // A touch of wander so the motes do not all move in straight lines.
    driftX += (r.nextDouble() - 0.5) * 0.004 * dt;
    driftY += (r.nextDouble() - 0.5) * 0.004 * dt;
    driftX = driftX.clamp(-0.02, 0.02);
    driftY = driftY.clamp(-0.015, 0.015);
    x += driftX * dt;
    y += driftY * dt;
    if (x < -0.02) x += 1.04;
    if (x > 1.02) x -= 1.04;
    if (y < -0.02) y += 1.04;
    if (y > 1.02) y -= 1.04;
  }
}
