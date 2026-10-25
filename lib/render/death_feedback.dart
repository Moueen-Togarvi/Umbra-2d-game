import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import '../config/palette.dart';
import '../entities/player.dart';

/// A short, quiet explanation during the death fade. It names the readable
/// gameplay rule rather than showing a game-over panel.
class DeathFeedback extends Component {
  DeathFeedback({required this.camera, required this.player})
    : super(priority: 9000);

  final CameraComponent camera;
  final Player? Function() player;
  final TextPainter _text = TextPainter(textDirection: TextDirection.ltr);
  DeathCause? _cause;

  static String message(DeathCause cause) => switch (cause) {
    DeathCause.drowning => 'NO AIR',
    DeathCause.vampire => 'SEEN IN THE DARK',
    DeathCause.crushing => 'CRUSHED',
    DeathCause.spikes => 'THE SPIKES',
    DeathCause.fall => 'TOO FAR TO FALL',
    DeathCause.fire => 'THE FIRE',
    DeathCause.trap => 'THE TRAP',
    DeathCause.impact => 'A FATAL IMPACT',
  };

  @override
  void render(Canvas canvas) {
    final boy = player();
    if (boy == null || !boy.isMounted || !boy.isDead) return;
    final view = camera.viewport.size;
    if (view.x <= 0) return;
    if (_cause != boy.deathCause) {
      _cause = boy.deathCause;
      _text.text = TextSpan(
        text: message(_cause!),
        style: TextStyle(
          fontFamily: 'Cinzel',
          fontSize: (view.y * .028).clamp(12, 20),
          letterSpacing: view.y * .004,
          color: Palette.brandInk.withValues(alpha: .78),
        ),
      );
      _text.layout(maxWidth: view.x * .8);
    }
    _text.paint(canvas, Offset((view.x - _text.width) / 2, view.y * .72));
  }
}
