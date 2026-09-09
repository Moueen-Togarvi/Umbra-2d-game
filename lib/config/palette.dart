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
}
