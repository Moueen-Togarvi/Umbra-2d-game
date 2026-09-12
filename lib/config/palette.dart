import 'dart:ui';

/// The entire colour vocabulary of the game.
///
/// Umbra is a silhouette game: everything physical is black, and everything
/// else is a shade of fog. Adding a colour should be a deliberate decision made
/// here rather than an accident made inside a component's render method.
///
/// Depth is expressed with *lightness*, the way it is in the reference art:
/// the further away a thing is, the more fog sits between it and the camera,
/// and the closer to the fog colour it becomes. The parallax layers are all
/// black images whose alpha carries the silhouette, so a layer's distance is
/// just how much of it is allowed through — see [depthOpacity].
abstract final class Palette {
  /// The solid black used for every physical object in the world.
  static const Color silhouette = Color(0xFF000000);

  // ---------------------------------------------------------------------------
  // Fog
  // ---------------------------------------------------------------------------

  /// The brightest point of the fog: the pale light behind the mist that
  /// everything is silhouetted against.
  static const Color fogGlow = Color(0xFFEFEFEE);

  /// The fog at mid distance from the light.
  static const Color fogMid = Color(0xFFB0B0AE);

  /// The fog at the edges of the light, before the vignette takes over.
  static const Color fogEdge = Color(0xFF7A7A78);

  /// The colour the world sinks into at the bottom of the screen and in the
  /// corners.
  static const Color dark = Color(0xFF000000);

  /// The colour behind everything, only ever visible for a frame before the
  /// backdrop paints.
  static const Color background = fogMid;

  /// Opacity of a black silhouette layer at a given depth, 0 (touching the
  /// camera) to 1 (the horizon). Rather than a formula this is a hand-tuned
  /// curve, because the eye reads fog non-linearly.
  static double depthOpacity(double depth) {
    if (depth <= 0.0) return 1.0;
    if (depth >= 1.0) return 0.18;
    // Ease-out: things stay dark for a while, then fade quickly into the mist.
    final t = depth * depth;
    return 1.0 - 0.82 * t;
  }

  // ---------------------------------------------------------------------------
  // Light
  // ---------------------------------------------------------------------------

  /// The player's eyes: the only pure-white, fully opaque thing in the world,
  /// and the way you find them in a dark scene.
  static const Color eyes = Color(0xFFFFFFFF);

  /// The soft halo around the eyes.
  static const Color eyeGlow = Color(0x55FFFFFF);

  /// Dust motes drifting through the light.
  static const Color dust = Color(0xFFFFFFFF);

  /// Shafts of light through the canopy.
  static const Color lightShaft = Color(0xFFFFFFFF);

  // ---------------------------------------------------------------------------
  // On-screen controls
  // ---------------------------------------------------------------------------
  // Translucent white, so the buttons read as a faint ring of light rather
  // than as a UI kit bolted on top of a dark scene. They sit over the play
  // area and must never compete with the player silhouette.

  /// Resting fill of a control button.
  static const Color control = Color(0x14FFFFFF);

  /// Fill of a control button while it is held down.
  static const Color controlPressed = Color(0x33FFFFFF);

  /// The ring around a control button.
  static const Color controlRing = Color(0x40FFFFFF);

  /// The arrow glyph drawn inside a control button.
  static const Color controlGlyph = Color(0xB3FFFFFF);
}
