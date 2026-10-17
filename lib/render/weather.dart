import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart' show FlameGame;

import '../world/stage.dart';
import 'light.dart';

/// Rain driven slantwise across the picture, in front of everything.
class Rain extends Component {
  Rain({this.slant = -0.35, this.count = 260, super.priority = 60});

  /// Sideways drift per metre of fall (the wind).
  double slant;
  final int count;
  double _time = 0;
  CameraComponent? _camera;
  final Paint _drop = Paint()
    ..color = const Color(0x40C8CCD4)
    ..strokeWidth = 0.018
    ..strokeCap = StrokeCap.round;

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
  }

  @override
  void update(double dt) => _time += dt;

  @override
  void render(Canvas canvas) {
    final Rect? view = _camera?.visibleWorldRect;
    if (view == null) return;
    final double w = view.width + 4, h = view.height + 2;
    for (var i = 0; i < count; i++) {
      // Each drop falls at its own speed through the view and wraps.
      final double speed = 14 + (i * 37 % 9);
      final double u = (i * 0.6180339 % 1) * w;
      final double v = ((i * 0.4142 % 1) * h + _time * speed) % h;
      final double x = view.left - 2 + (u + v * -slant) % w;
      final double y = view.top - 1 + v;
      canvas.drawLine(Offset(x, y), Offset(x + slant * 0.5, y + 0.5), _drop);
    }
  }
}

/// Lightning: every few seconds the whole sky goes white for a moment and
/// everything stands lit. Long enough to stop a vampire in its tracks,
/// not to burn it. [flashed] counts the strikes; [strikeAt] calls one now.
class Lightning extends Component implements LightSource {
  Lightning({this.every = 5.5, this.firstAfter = 3, super.priority = 70});

  final double every, firstAfter;
  double _clock = 0;
  double _flash = 0;
  int flashed = 0;
  bool active = true;
  final math.Random _random = math.Random(13);
  double _next = 0;
  Vector2? _bolt;
  Stage? _stage;
  CameraComponent? _camera;

  /// How white the sky is now, 0–1.
  double get flash => _flash;

  @override
  bool lights(Vector2 point) => _flash > 0.45;

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
    _next = firstAfter;
  }

  @override
  void onMount() {
    super.onMount();
    _stage = ancestors().whereType<Stage>().firstOrNull;
    _stage?.lights.add(this);
  }

  @override
  void onRemove() {
    _stage?.lights.remove(this);
    super.onRemove();
  }

  /// A strike now, its bolt coming down at [at] (world metres) if given.
  void strikeAt([Vector2? at]) {
    _flash = 1;
    flashed++;
    _bolt = at;
    cue('thunder', shake: 0.3);
  }

  @override
  void update(double dt) {
    _flash = math.max(0, _flash - dt / 0.5);
    if (!active) return;
    _clock += dt;
    if (_clock >= _next) {
      _clock = 0;
      _next = every * (0.75 + _random.nextDouble() * 0.5);
      final Rect? view = _camera?.visibleWorldRect;
      strikeAt(
        view == null
            ? null
            : Vector2(
                view.left + view.width * (0.2 + _random.nextDouble() * 0.6),
                view.top + view.height * 0.55,
              ),
      );
    }
  }

  final Paint _sky = Paint();
  final Paint _boltPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  @override
  void render(Canvas canvas) {
    if (_flash <= 0.01) return;
    final Rect? view = _camera?.visibleWorldRect;
    if (view == null) return;
    // The flash: the air itself lit, a wash over everything.
    _sky.color = const Color(0xFFE6ECF4).withValues(alpha: 0.35 * _flash);
    canvas.drawRect(view.inflate(1), _sky);
    final Vector2? to = _bolt;
    if (to == null || _flash < 0.4) return;
    // The bolt, jagged, from above the picture down to where it struck.
    final random = math.Random(flashed * 31);
    final path = Path()..moveTo(to.x + 2, view.top - 1);
    double x = to.x + 2;
    for (double y = view.top - 1; y < to.y; y += 0.6) {
      x += (random.nextDouble() - 0.6) * 0.9;
      path.lineTo(x, y);
    }
    path.lineTo(to.x, to.y);
    _boltPaint
      ..color = const Color(0xFFF4F7FF).withValues(alpha: _flash)
      ..strokeWidth = 0.06;
    canvas.drawPath(path, _boltPaint);
  }
}

/// The sun coming up behind the hills on the right. Its light sweeps
/// across the land from the right as it rises: everything to the right of
/// [edge] stands in sunlight, and the edge moves left at [speed] once
/// [rising]. A vampire in it burns.
class Sunrise extends Component implements LightSource {
  Sunrise({required this.edge, this.speed = 2.6, super.priority = -36});

  double edge;
  final double speed;
  bool rising = false;
  Stage? _stage;
  CameraComponent? _camera;

  @override
  bool lights(Vector2 point) => point.x > edge;

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
  }

  @override
  void onMount() {
    super.onMount();
    _stage = ancestors().whereType<Stage>().firstOrNull;
    _stage?.lights.add(this);
  }

  @override
  void onRemove() {
    _stage?.lights.remove(this);
    super.onRemove();
  }

  @override
  void update(double dt) {
    if (rising) edge -= speed * dt;
  }

  final Paint _warm = Paint();

  @override
  void render(Canvas canvas) {
    final Rect? view = _camera?.visibleWorldRect;
    if (view == null || edge > view.right + 3) return;
    // Low warm light lying over the land right of the edge, its front
    // soft.
    final double left = math.max(view.left - 1, edge - 3);
    _warm
      ..color = const Color(0xFFFFFFFF)
      ..shader = Gradient.linear(Offset(edge - 3, 0), Offset(edge + 1.5, 0), [
        const Color(0x00FFD9A0),
        const Color(0x38FFD9A0),
      ]);
    canvas.drawRect(
      Rect.fromLTRB(left, view.top - 1, view.right + 1, view.bottom + 1),
      _warm,
    );
    _warm.shader = null;
  }
}
