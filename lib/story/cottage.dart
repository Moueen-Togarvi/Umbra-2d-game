import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/flame.dart';
import 'package:flame/game.dart' show FlameGame;

import '../config/palette.dart';
import '../render/mood.dart';
import '../world/stage.dart';
import 'figures.dart';

/// The boy's home: the baked cottage silhouette with its lamp lit inside.
///
/// The art has its windows and doorway cut out (see the bake config), and
/// this draws what shows through them: a warm lamp-lit room, the shadows
/// of the argument on the curtain of the upper window, and later his
/// mother in the doorway. The door is a hinge simulated in one dimension
/// (an angle, its speed, a stop at each end that it bounces off) and drawn
/// in perspective, because it swings out towards the camera.
///
/// The cottage sits in the play plane but a breath of fog lighter than the
/// boy, so his silhouette reads against its wall.
class Cottage extends Component {
  Cottage({required this.centreX, required this.groundY, this.height = 8.6})
    : super(priority: -6);

  static const String art = 'part1/ch1_cottage.png';

  /// The art's size in pixels, inside the transparent border the bake adds.
  static const double artWidth = 1171, artHeight = 728, artPad = 4;

  /// The art's width over its height, border included.
  static const double aspect =
      (artWidth + artPad * 2) / (artHeight + artPad * 2);

  /// Openings, as fractions of the art (left, top, right, bottom); they
  /// match the cut rectangles in `tools/part1_bake.json`.
  static const Rect doorFraction = Rect.fromLTRB(0.401, 0.742, 0.459, 0.953);
  static const List<Rect> windowFractions = [
    Rect.fromLTRB(0.322, 0.452, 0.378, 0.548),
    Rect.fromLTRB(0.557, 0.752, 0.598, 0.83),
    Rect.fromLTRB(0.667, 0.752, 0.709, 0.83),
  ];

  final double centreX, groundY, height;
  double get width => height * aspect;

  /// The art's bottom: sunk so the doorstep is level with the ground.
  double get baseY =>
      groundY +
      (1 -
              (doorFraction.bottom * artHeight + artPad) /
                  (artHeight + artPad * 2)) *
          height;
  Rect get bounds => Rect.fromLTRB(
    centreX - width / 2,
    baseY - height,
    centreX + width / 2,
    baseY,
  );

  /// [f] in fractions of the art (without its border) to world metres.
  Rect toWorld(Rect f) {
    final Rect b = bounds;
    double fx(double v) =>
        (v * artWidth + artPad) / (artWidth + artPad * 2) * b.width;
    double fy(double v) =>
        (v * artHeight + artPad) / (artHeight + artPad * 2) * b.height;
    return Rect.fromLTRB(
      b.left + fx(f.left),
      b.top + fy(f.top),
      b.left + fx(f.right),
      b.top + fy(f.bottom),
    );
  }

  Rect get door => toWorld(doorFraction);
  late final List<Rect> windows = [for (final f in windowFractions) toWorld(f)];

  /// How bright the lamp is, 0 (out) to 1.
  double lamp = 1;

  /// How hard the two shadows in the upper window are arguing (0 calm, 1
  /// shouting), and whether the boy's shadow is still in the room.
  double argue = 0;
  bool boyInRoom = true;
  double _boyShadowX = 0;

  /// The door: its angle (0 shut, about 1.95 thrown wide, swung out
  /// towards the camera), its angular speed, and whether something is
  /// pulling it shut.
  double doorAngle = 0;
  double doorSpeed = 0;
  bool closing = false;
  static const double doorMax = 1.95;
  int doorSlams = 0;

  final Mother mother = Mother();

  double _time = 0;
  Image? _art;
  Stage? _stage;
  CameraComponent? _camera;
  final Paint _paint = Paint();
  final Paint _image = Paint()..filterQuality = FilterQuality.medium;

  /// Throws the door open, as from a running push.
  void burstOpen() {
    closing = false;
    doorSpeed = 12;
  }

  /// Lets the door swing shut, pulled by its own weight on a leaning frame.
  void swingShut() => closing = true;

  @override
  Future<void> onLoad() async {
    final game = findGame();
    if (game is FlameGame) _camera = game.camera;
    _stage = ancestors().whereType<Stage>().firstOrNull;
    try {
      _art = await Flame.images.load(art);
    } catch (_) {}
  }

  @override
  void update(double dt) {
    _time += dt;
    // The hinge: stiff old hinges, a pull towards shut when closing, and
    // the frame and the wall as stops it bounces a little off.
    double torque = -doorSpeed * 3.0;
    if (closing) torque -= 9 * math.max(0.25, math.sin(doorAngle));
    doorSpeed += torque * dt;
    doorAngle += doorSpeed * dt;
    if (doorAngle > doorMax) {
      doorAngle = doorMax;
      doorSpeed = -doorSpeed.abs() * 0.15;
    } else if (doorAngle < 0) {
      if (doorSpeed < -1.2) doorSlams++;
      doorAngle = 0;
      doorSpeed = doorSpeed.abs() * 0.22;
      if (doorSpeed < 0.25) doorSpeed = 0;
    }
    mother.update(dt);
    final double target = boyInRoom ? 0 : 1;
    _boyShadowX += (target - _boyShadowX) * math.min(1, dt * 1.6);
  }

  /// The lamp as it flickers now.
  double get _flame =>
      lamp *
      (0.9 +
          0.06 * math.sin(_time * 7.3) * math.sin(_time * 2.1 + 0.6) +
          0.04 * math.sin(_time * 17.9));

  @override
  void render(Canvas canvas) {
    final Rect b = bounds;
    final Rect? view = _camera?.visibleWorldRect;
    if (view != null && !view.inflate(2).overlaps(b)) return;
    final double flame = _flame;

    // 1. The lit rooms behind the openings.
    for (final w in [...windows, door]) {
      _room(canvas, w, flame);
    }
    _interior(canvas, door, flame);
    // The lamp itself, on the sill of the right window.
    _lampOnSill(canvas, windows[2], flame);

    // 2. The argument, as shadows on the upper window's curtain.
    _shadowPlay(canvas, windows[0], flame);

    // 3. The cottage, a little lighter than the boy.
    final Image? art = _art;
    if (art != null) {
      final Mood mood =
          _stage?.moods.at(_camera?.viewfinder.position.x ?? centreX) ??
          Mood.dusk;
      _image.colorFilter = ColorFilter.mode(
        Color.lerp(const Color(0xFF000000), mood.sky[2], 0.17)!,
        BlendMode.srcIn,
      );
      canvas.drawImageRect(
        art,
        Rect.fromLTWH(0, 0, art.width.toDouble(), art.height.toDouble()),
        b,
        _image,
      );
    }

    // 4. His mother in the doorway, in front of the light.
    mother.render(canvas, door);

    // 5. The door, swung out towards us.
    _door(canvas);

    // 6. Light bleeding out of the openings into the dusk.
    for (final w in windows) {
      _halo(canvas, w.center, 1.3, 0.16 * flame);
    }
    final double open = (math.sin(doorAngle.clamp(0, math.pi / 2))).toDouble();
    _halo(canvas, door.center, 1.6, 0.2 * flame * open);
  }

  void _room(Canvas canvas, Rect r, double flame) {
    final Rect fill = r.inflate(0.01);
    // Opaque: a shader paints at the paint colour's opacity.
    _paint.color = const Color(0xFFFFFFFF);
    _paint.shader = Gradient.radial(
      Offset(r.center.dx + r.width * 0.2, r.top + r.height * 0.35),
      math.max(r.width, r.height) * 0.9,
      [
        Color.lerp(
          const Color(0xFF3A2410),
          const Color(0xFFF4C27A),
          0.25 + 0.75 * flame,
        )!,
        Color.lerp(
          const Color(0xFF1A0F06),
          Palette.lampAmber,
          0.2 + 0.7 * flame,
        )!,
        Color.lerp(const Color(0xFF080503), const Color(0xFF5A3612), flame)!,
      ],
      const [0.0, 0.55, 1.0],
    );
    canvas.drawRect(fill, _paint);
    _paint.shader = null;
  }

  /// The room through the doorway, out of focus: the back of a chair and
  /// the edge of the table, darker shapes in the lamplight.
  void _interior(Canvas canvas, Rect d, double flame) {
    canvas.save();
    canvas.clipRect(d);
    _paint.color = Color.lerp(
      const Color(0xFF1C1006),
      const Color(0xFF7A4A18),
      0.35 * flame,
    )!;
    final double floor = d.bottom;
    // The table's far edge and a leg.
    canvas.drawRect(
      Rect.fromLTRB(
        d.left + d.width * 0.55,
        floor - 0.72,
        d.right,
        floor - 0.66,
      ),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(d.right - 0.08, floor - 0.66, d.right - 0.05, floor),
      _paint,
    );
    // A chair pushed back, its back slats.
    final double cx = d.left + d.width * 0.28;
    canvas.drawRect(
      Rect.fromLTRB(cx - 0.16, floor - 0.45, cx + 0.1, floor - 0.41),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(cx - 0.16, floor - 0.95, cx - 0.13, floor),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(cx + 0.07, floor - 0.41, cx + 0.1, floor),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTRB(cx - 0.16, floor - 0.9, cx - 0.03, floor - 0.86),
      _paint,
    );
    canvas.restore();
  }

  void _lampOnSill(Canvas canvas, Rect w, double flame) {
    final double x = w.left + w.width * 0.3;
    final double sill = w.bottom;
    _paint.color = const Color(0xFF0A0603);
    // Base, glass chimney and handle, a few centimetres tall at this size.
    canvas.drawPath(
      Path()
        ..moveTo(x - 0.06, sill)
        ..lineTo(x - 0.04, sill - 0.04)
        ..lineTo(x - 0.015, sill - 0.05)
        ..lineTo(x - 0.03, sill - 0.13)
        ..lineTo(x + 0.03, sill - 0.13)
        ..lineTo(x + 0.015, sill - 0.05)
        ..lineTo(x + 0.04, sill - 0.04)
        ..lineTo(x + 0.06, sill)
        ..close(),
      _paint,
    );
    // Opaque: a shader paints at the paint colour's opacity.
    _paint.color = const Color(0xFFFFFFFF);
    _paint.shader = Gradient.radial(
      Offset(x, sill - 0.085),
      0.07,
      [
        Color.fromRGBO(255, 244, 214, flame),
        Color.fromRGBO(255, 190, 90, 0.6 * flame),
        const Color(0x00FF9A30),
      ],
      const [0, 0.4, 1],
    );
    canvas.drawCircle(Offset(x, sill - 0.085), 0.07, _paint);
    _paint.shader = null;
  }

  /// Two figures on the curtain: the mother, taller, on the left, and the
  /// boy on the right, both gesturing as hard as [argue].
  void _shadowPlay(Canvas canvas, Rect w, double flame) {
    if (argue <= 0.001 && _boyShadowX >= 0.999) return;
    canvas.save();
    canvas.clipRect(w);
    final double t = _time;
    final double a = argue;
    // A shadow on a curtain is soft and not quite black.
    _paint.color = Color.fromRGBO(20, 10, 4, 0.78);
    final double unit = w.height;
    final Offset mum = Offset(w.left + w.width * 0.3, w.bottom + unit * 0.05);
    final double mumWave = math.sin(t * 3.4) * a;
    _curtainFigure(
      canvas,
      mum,
      unit * 0.95,
      facing: 1,
      armRaise: 0.6 + 0.8 * a + 0.5 * mumWave,
      otherArm: 0.2 + 0.3 * a * math.sin(t * 1.7 + 1),
      lean: 0.06 * a * math.sin(t * 1.3),
      bun: true,
    );
    final double boyX = w.left + w.width * (0.72 + 0.6 * _boyShadowX);
    final double stomp = math.max(0, math.sin(t * 4.1)) * a;
    _curtainFigure(
      canvas,
      Offset(boyX, w.bottom + unit * 0.05 - stomp * unit * 0.03),
      unit * 0.7,
      facing: -1,
      armRaise: 0.3 + 0.9 * a * math.max(0, math.sin(t * 2.3 + 2)),
      otherArm: 0.1,
      lean: -0.08 * a,
      bun: false,
    );
    canvas.restore();
  }

  void _curtainFigure(
    Canvas canvas,
    Offset feet,
    double h, {
    required double facing,
    required double armRaise,
    required double otherArm,
    required double lean,
    required bool bun,
  }) {
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    canvas.rotate(lean);
    final double headR = h * 0.075;
    final Offset head = Offset(0, -h + headR);
    final Offset shoulder = Offset(0, -h * 0.78);
    canvas.drawCircle(head, headR, _paint);
    if (bun) {
      canvas.drawCircle(
        head + Offset(-facing * headR * 0.9, -headR * 0.4),
        headR * 0.55,
        _paint,
      );
    }
    canvas.drawPath(
      Path()
        ..moveTo(-h * 0.08, -h * 0.8)
        ..lineTo(h * 0.08, -h * 0.8)
        ..lineTo(h * (bun ? 0.17 : 0.07), 0)
        ..lineTo(-h * (bun ? 0.17 : 0.07), 0)
        ..close(),
      _paint,
    );
    final stroke = Paint()
      ..color = _paint.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = h * 0.045
      ..strokeCap = StrokeCap.round;
    for (final (raise, side) in [(armRaise, facing), (otherArm, -facing)]) {
      final double angle = math.pi / 2 - raise * 1.4;
      final Offset elbow =
          shoulder +
          Offset(side * math.cos(angle) * h * 0.2, math.sin(angle) * h * 0.2);
      final Offset hand =
          elbow +
          Offset(
            side * math.cos(angle - 0.4) * h * 0.2,
            math.sin(angle - 0.4) * h * 0.2,
          );
      canvas.drawPath(
        Path()
          ..moveTo(shoulder.dx, shoulder.dy)
          ..lineTo(elbow.dx, elbow.dy)
          ..lineTo(hand.dx, hand.dy),
        stroke,
      );
    }
    canvas.restore();
  }

  void _door(Canvas canvas) {
    final Rect d = door;
    final double c = math.cos(doorAngle), s = math.sin(doorAngle);
    // The free edge comes towards the camera as it opens, so it looks a
    // little taller, and the panel narrows to its edge at a right angle.
    final double grow = 1 + 0.1 * s;
    final double hx = d.left;
    final double fx = hx + d.width * c;
    final double mid = d.center.dy;
    final double half = d.height / 2;
    _paint.color = const Color(0xFF040302);
    canvas.drawPath(
      Path()
        ..moveTo(hx, d.top)
        ..lineTo(fx, mid - half * grow)
        ..lineTo(fx, mid + half * grow)
        ..lineTo(hx, d.bottom)
        ..close(),
      _paint,
    );
    // Light round the edges of a shut door.
    if (doorAngle < 0.05) {
      _paint.color = Palette.lampAmber.withValues(alpha: 0.5 * _flame);
      canvas.drawRect(
        Rect.fromLTRB(d.right - 0.012, d.top + 0.02, d.right, d.bottom),
        _paint,
      );
      canvas.drawRect(
        Rect.fromLTRB(
          d.left + 0.03,
          d.bottom - 0.012,
          d.right - 0.02,
          d.bottom,
        ),
        _paint,
      );
    }
  }

  void _halo(Canvas canvas, Offset at, double radius, double alpha) {
    if (alpha <= 0.002) return;
    // Opaque: a shader paints at the paint colour's opacity.
    _paint.color = const Color(0xFFFFFFFF);
    _paint.shader = Gradient.radial(
      at,
      radius,
      [
        Palette.lampAmber.withValues(alpha: alpha),
        Palette.lampAmber.withValues(alpha: alpha * 0.35),
        Palette.lampAmber.withValues(alpha: 0),
      ],
      const [0, 0.35, 1],
    );
    canvas.drawCircle(at, radius, _paint);
    _paint.shader = null;
  }
}

/// The lamplight that falls out of the open door onto the yard, drawn over
/// the ground.
class DoorLight extends Component {
  DoorLight(this.cottage) : super(priority: 3);
  final Cottage cottage;
  final Paint _paint = Paint();

  @override
  void render(Canvas canvas) {
    final double open = math.sin(cottage.doorAngle.clamp(0.0, math.pi / 2));
    final double alpha = 0.32 * open * cottage.lamp;
    if (alpha <= 0.003) return;
    final Rect d = cottage.door;
    final Offset step = Offset(d.center.dx + 0.2, d.bottom + 0.03);
    // Opaque: a shader paints at the paint colour's opacity.
    _paint.color = const Color(0xFFFFFFFF);
    _paint.shader = Gradient.radial(
      step,
      2.4,
      [
        Palette.lampAmber.withValues(alpha: alpha),
        Palette.lampAmber.withValues(alpha: alpha * 0.3),
        Palette.lampAmber.withValues(alpha: 0),
      ],
      const [0, 0.4, 1],
      TileMode.clamp,
      // Squashed flat: light lying on the ground.
      Matrix4Like.squash(step, 1, 0.12),
    );
    canvas.drawRect(
      Rect.fromCenter(center: step, width: 5, height: 0.7),
      _paint,
    );
    _paint.shader = null;
  }
}

/// Column-major 4×4 matrices for gradient transforms.
abstract final class Matrix4Like {
  /// Scales about [at] by [sx], [sy].
  static Float64List squash(Offset at, double sx, double sy) =>
      Float64List.fromList([
        sx, 0, 0, 0, //
        0, sy, 0, 0, //
        0, 0, 1, 0, //
        at.dx * (1 - sx), at.dy * (1 - sy), 0, 1,
      ]);
}
