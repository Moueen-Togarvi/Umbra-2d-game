import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart'
    show TextPainter, TextSpan, TextStyle, TextAlign, FontWeight;

import '../config/palette.dart';
import 'chapter_director.dart';

/// The card before a chapter: its number in small letter-spaced capitals,
/// its name large beneath, in the brand's Cinzel, fading in and out. On
/// black between chapters; laid over the scene, low and quiet, when the
/// story begins out of the title.
class ChapterCard extends Component {
  ChapterCard({required this.camera, required this.director})
    : super(priority: 10);

  final CameraComponent camera;
  final ChapterDirector director;
  final TextPainter _small = TextPainter(textDirection: TextDirection.ltr);
  final TextPainter _title = TextPainter(
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  );
  final Paint _paint = Paint();
  String _laidOut = '';
  double _laidOutHeight = 0;

  final TextPainter _caption = TextPainter(textDirection: TextDirection.ltr);
  bool _captionLaid = false;

  /// After the credits: black, and two red eyes opening in it.
  void _renderEyes(Canvas canvas, Vector2 view) {
    final double a = director.eyes.clamp(0.0, 1.0);
    final Rect full = Rect.fromLTWH(0, 0, view.x, view.y);
    _paint
      ..shader = null
      ..color = Palette.brandBlack;
    canvas.drawRect(full, _paint);
    final double unit = view.y / 100;
    final double open = director.eyesOpen.clamp(0.0, 1.0);
    for (final side in [-1.0, 1.0]) {
      final Offset c = Offset(view.x / 2 + side * unit * 6, view.y * 0.46);
      _paint
        ..color = const Color(0xFFFFFFFF)
        ..shader = Gradient.radial(c, unit * 9, [
          Palette.vampireRed.withValues(alpha: 0.4 * a),
          Palette.vampireRed.withValues(alpha: 0),
        ]);
      canvas.drawCircle(c, unit * 9, _paint);
      _paint
        ..shader = null
        ..color = Color.lerp(
          Palette.vampireRed,
          const Color(0xFFFFB0A0),
          0.3,
        )!.withValues(alpha: a);
      // Narrowed, the inner corners low: not a boy's eyes any more.
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-side * 0.2);
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: unit * 5,
          height: unit * 1.6 * open + 0.5,
        ),
        _paint,
      );
      canvas.restore();
    }
    final double cap = director.eyesCaption.clamp(0.0, 1.0);
    if (cap <= 0.01) return;
    if (!_captionLaid) {
      _captionLaid = true;
      _caption.text = TextSpan(
        text: 'UMBRA · II',
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: unit * 2.6,
          letterSpacing: unit * 1.2,
          color: Palette.brandInk,
        ),
      );
      _caption.layout();
    }
    canvas.saveLayer(full, Paint()..color = Color.fromRGBO(0, 0, 0, cap * 0.8));
    _caption.paint(
      canvas,
      Offset((view.x - _caption.width) / 2, view.y * 0.62),
    );
    canvas.restore();
  }

  @override
  void render(Canvas canvas) {
    if (director.eyes > 0.001) {
      final Vector2 v = camera.viewport.size;
      if (v.x > 0) _renderEyes(canvas, v);
      return;
    }
    final double alpha = director.cardAlpha.clamp(0.0, 1.0);
    if (alpha <= 0.001) return;
    final Vector2 view = camera.viewport.size;
    if (view.x <= 0) return;
    final String key = '${director.cardSmall}|${director.cardTitle}';
    if (key != _laidOut || view.y != _laidOutHeight) {
      _laidOut = key;
      _laidOutHeight = view.y;
      final double unit = view.y / 100;
      _small.text = TextSpan(
        text: director.cardSmall,
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: unit * 3.1,
          letterSpacing: unit * 1.1,
          fontWeight: FontWeight.w500,
          color: Palette.brandInk,
        ),
      );
      TextSpan title(double size) => TextSpan(
        text: director.cardTitle,
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: size,
          letterSpacing: size * 0.06,
          fontWeight: FontWeight.w400,
          color: Palette.brandInk,
        ),
      );
      _small.layout();
      _title
        ..text = title(unit * 8.5)
        ..layout();
      // A long line (a list of names in the credits) comes down in size
      // to fit across the screen.
      final double room = view.x * 0.9;
      if (_title.width > room) {
        _title
          ..text = title(unit * 8.5 * room / _title.width)
          ..layout();
      }
    }
    final bool onBlack = director.cardOnBlack;
    final Rect full = Rect.fromLTWH(0, 0, view.x, view.y);
    if (onBlack) {
      _paint
        ..shader = null
        ..color = Palette.brandBlack.withValues(alpha: alpha);
      canvas.drawRect(full, _paint);
    }
    // Over the scene, the words sit in the lower third on a soft shade.
    final double centre = onBlack ? view.y * 0.5 : view.y * 0.76;
    if (!onBlack) {
      _paint
        ..color = const Color(0xFF000000)
        ..shader = Gradient.linear(
          Offset(0, centre - view.y * 0.2),
          Offset(0, centre + view.y * 0.24),
          [
            const Color(0x00000000),
            Color.fromRGBO(0, 0, 0, 0.42 * alpha),
            const Color(0x00000000),
          ],
          const [0, 0.55, 1],
        );
      canvas.drawRect(full, _paint);
      _paint.shader = null;
    }
    canvas.saveLayer(full, Paint()..color = Color.fromRGBO(0, 0, 0, alpha));
    final double gap = view.y * 0.025;
    final double top = centre - (_small.height + gap + _title.height) / 2;
    _small.paint(canvas, Offset((view.x - _small.width) / 2, top));
    // A short amber rule between the lines: the lamp, the brand's mark.
    _paint.color = Palette.lampAmber.withValues(alpha: 0.85);
    final double ruleY = top + _small.height + gap * 0.45;
    canvas.drawRect(
      Rect.fromCenter(
        center: Offset(view.x / 2, ruleY),
        width: view.y * 0.06,
        height: view.y * 0.0035,
      ),
      _paint,
    );
    _title.paint(
      canvas,
      Offset((view.x - _title.width) / 2, top + _small.height + gap),
    );
    canvas.restore();
  }
}
