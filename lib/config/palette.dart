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

  /// The fog at mid distance from the light.
  static const Color fogMid = Color(0xFFC6C6C6);

  /// The colour the world sinks into at the bottom of the screen and in the
  /// corners.
  static const Color dark = Color(0xFF000000);

  /// The colour behind everything, only ever visible for a frame before the
  /// backdrop paints.
  static const Color background = fogMid;

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

  /// The low sun behind the dusk fog: barely warm.
  static const Color duskLight = Color(0xFFF2E6D2);

  /// The moon behind the night fog: barely cold.
  static const Color moonLight = Color(0xFFDDE3EA);

  // ---------------------------------------------------------------------------
  // Brand
  // ---------------------------------------------------------------------------
  // The only two colours in the game. Amber is home: the lamp in the
  // cottage window, the title, the warm end. Red is the vampires' eyes and
  // nothing else. Both are rare on screen, which is what makes them work.

  /// The lamp in the cottage window, and the brand's warm accent.
  static const Color lampAmber = Color(0xFFE8A84A);

  /// The vampires' eyes. Used for nothing else.
  static const Color vampireRed = Color(0xFFC21E1E);

  /// Near-black for the brand's screens (title, cards, splash): a hair
  /// lighter than the silhouettes so they never vanish into it.
  static const Color brandBlack = Color(0xFF0B0B0B);

  /// The fog-pale ink of text on the brand's screens.
  static const Color brandInk = Color(0xFFD8D4CC);

  // ---------------------------------------------------------------------------
  // On-screen controls
  // ---------------------------------------------------------------------------
  // Translucent white, so the buttons read as a faint ring of light rather
  // than as a UI kit bolted on top of a dark scene. They sit over the play
  // area and must never compete with the player silhouette.

  /// Resting fill of a control button.
  static const Color control = Color(0x0AFFFFFF);

  /// Fill of a control button while it is held down.
  static const Color controlPressed = Color(0x26FFFFFF);

  /// The ring around a control button.
  static const Color controlRing = Color(0x24FFFFFF);

  /// The arrow glyph drawn inside a control button.
  static const Color controlGlyph = Color(0x73FFFFFF);
}
