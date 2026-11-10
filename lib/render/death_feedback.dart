import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flutter/painting.dart' show TextPainter, TextSpan, TextStyle;

import '../config/palette.dart';
import '../entities/player.dart';
import '../world/checkpoint_service.dart';

/// A short, quiet explanation during the death fade. It names the readable
/// gameplay rule rather than showing a game-over panel.
class DeathFeedback extends Component {
  DeathFeedback({
    required this.camera,
    required this.player,
    required this.checkpoints,
  }) : super(priority: 9000);

  final CameraComponent camera;
  final Player? Function() player;
  final CheckpointService Function() checkpoints;
  final TextPainter _text = TextPainter(textDirection: TextDirection.ltr);
  DeathCause? _cause;
  int _shownDeaths = -1;

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

  static String hint(DeathCause cause) => switch (cause) {
    DeathCause.drowning => 'SURFACE BEFORE THE AIR RUNS OUT',
    DeathCause.vampire => 'BREAK SIGHT OR HIDE LOW IN SHADOW',
    DeathCause.crushing => 'WAIT FOR THE MECHANISM TO CLEAR',
    DeathCause.spikes => 'JUMP BEFORE THE EDGE',
    DeathCause.fall => 'LOOK FOR A LOWER LANDING',
    DeathCause.fire => 'WATCH THE FLAME RHYTHM',
    DeathCause.trap => 'WATCH FOR WIRES AND MOVING PARTS',
    DeathCause.impact => 'LET THE MOVING OBJECT PASS',
  };

  @override
  void render(Canvas canvas) {
    final boy = player();
    if (boy == null || !boy.isMounted || !boy.isDead) return;
    final view = camera.viewport.size;
    if (view.x <= 0) return;
    final deathCount = checkpoints().deathsFor(boy.deathCause);
    if (_cause != boy.deathCause || _shownDeaths != deathCount) {
      _cause = boy.deathCause;
      _shownDeaths = deathCount;
      final repeated = checkpoints().deathsFor(_cause!) >= 2;
      _text.text = TextSpan(
        text: repeated
            ? '${message(_cause!)}\n${hint(_cause!)}'
            : message(_cause!),
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
