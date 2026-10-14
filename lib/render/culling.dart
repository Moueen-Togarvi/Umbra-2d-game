import 'dart:ui';

import 'package:flame/components.dart';
import 'package:flame/game.dart' show FlameGame;

/// Lets a world component skip drawing when it is off screen.
///
/// Every drawn path costs real CPU time on the web, even one the camera
/// cannot see, so props, logs and pits along the whole level are culled
/// against the camera's view, as the banks already are.
mixin OffScreenCulling on Component {
  CameraComponent? _cullingCamera;

  /// Whether any of [worldBounds] (world metres) is within the camera's
  /// view, with a little margin. True when there is no camera, as in tests.
  bool isOnScreen(Rect worldBounds) {
    final camera = _cullingCamera ??= switch (findGame()) {
      final FlameGame game => game.camera,
      _ => null,
    };
    if (camera == null) return true;
    return camera.visibleWorldRect.inflate(0.5).overlaps(worldBounds);
  }
}
