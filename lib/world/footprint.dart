import 'dart:ui';

/// Something drawn in the world without a body (a window's shutters, a
/// cell front, a drain in a wall) that takes up room on or just above the
/// ground: the trees and other standing decoration keep clear of it.
abstract interface class HasFootprint {
  /// Where it is drawn, world metres.
  Rect get footprint;
}
