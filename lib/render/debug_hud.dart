import 'dart:ui';

import 'package:flame/components.dart';

import '../config/game_config.dart';
import '../entities/player.dart';

/// A machine-readable position readout, for automated play-testing.
///
/// Compiled in only when the build is given `--dart-define=UMBRA_DEBUG=true`;
/// in every other build [enabled] is a compile-time `false` and the component
/// is never created. It draws three bars in the top-left corner:
///
///  - row 0-3: white, `x / levelWidth` of the viewport width;
///  - row 4-7: white, `y / levelHeight` of the viewport width;
///  - row 8-11: white 8 px square if the player is on the ground.
///
/// A test reads them straight out of a screenshot, which is the only way to
/// observe the player on this machine: the native test runner cannot build
/// forge2d here, so the game is verified on a web build in a real browser.
class DebugHud extends Component {
  DebugHud({required this.camera, required this.player}) : super(priority: 100);

  static const bool enabled = bool.fromEnvironment('UMBRA_DEBUG');

  final CameraComponent camera;
  final Player player;

  final Paint _paint = Paint()..color = const Color(0xFFFFFFFF);

  @override
  void render(Canvas canvas) {
    if (!player.isMounted) return;
    final double width = camera.viewport.size.x;
    final Vector2 p = player.body.position;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, width * p.x / GameConfig.levelWidth, 4),
      _paint,
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 4, width * p.y / GameConfig.levelHeight, 4),
      _paint,
    );
    if (player.isOnGround) {
      canvas.drawRect(const Rect.fromLTWH(0, 8, 8, 4), _paint);
    }
  }
}
