import 'dart:ui';

/// The entire colour vocabulary of the game.
///
/// Umbra is a silhouette game: there are two colours, and adding a third should
/// be a deliberate decision made here rather than an accident made inside a
/// component's render method.
abstract final class Palette {
  /// The flat, slightly warm light grey everything is drawn against.
  static const Color background = Color(0xFFE6E5E1);

  /// The solid black used for every physical object in the world.
  static const Color silhouette = Color(0xFF000000);

  // ---------------------------------------------------------------------------
  // On-screen controls
  // ---------------------------------------------------------------------------
  // Translucent black, so the buttons read as part of the same monochrome world
  // rather than as a UI kit bolted on top. They sit over the play area, so they
  // must be legible without ever competing with the player silhouette.

  /// Resting fill of a control button.
  static const Color control = Color(0x30000000);

  /// Fill of a control button while it is held down.
  static const Color controlPressed = Color(0x5C000000);

  /// The arrow glyph drawn inside a control button.
  static const Color controlGlyph = Color(0x8A000000);
}
