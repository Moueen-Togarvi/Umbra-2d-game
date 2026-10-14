import 'dart:math' as math;

/// Hand over hand: where along a rope each hand holds, in metres from the
/// anchor, front hand first.
///
/// A gripping hand stays where it is on the rope while the body climbs past
/// it. When it is left too far below (climbing up) or above (climbing down)
/// the hold, it lets go and takes a new grip on the far side of the other
/// hand, one hand at a time, the way LIMBO's boy climbs.
class RopeGrips {
  /// Arc lengths along the rope of the front and back hands.
  final List<double> arcs = [0, 0];
  int _moving = -1;
  double _from = 0, _to = 0, _t = 0;

  /// How far above and below the hold a hand can stay before it moves.
  static const double reachAbove = 0.30, reachBelow = 0.30;

  /// Where a moving hand takes its new grip, above or below the hold.
  static const double regripAbove = 0.22, regripBelow = 0.24;

  /// How long one hand takes to move to its new grip.
  static const double moveSeconds = 0.16;

  /// One hand above the hold, at the head, and one below it, at the chest.
  void reset(double hold) {
    arcs[0] = hold - 0.10;
    arcs[1] = hold + 0.16;
    _moving = -1;
    _t = 0;
  }

  /// Which hand is moving to a new grip, or -1.
  int get moving => _moving;

  /// How far off the rope a hand is, 0 holding to 1 mid-move.
  double lift(int hand) => hand == _moving ? math.sin(math.pi * _t) : 0;

  void update(double hold, double dt, {double top = 0.2, double end = 1e9}) {
    if (_moving >= 0) {
      _t = math.min(1, _t + dt / moveSeconds);
      final double s = _t * _t * (3 - 2 * _t);
      arcs[_moving] = _from + (_to - _from) * s;
      if (_t >= 1) _moving = -1;
      return;
    }
    for (var i = 0; i < 2; i++) {
      final double offset = arcs[i] - hold;
      double? target;
      if (offset > reachBelow) {
        target = hold - regripAbove;
      } else if (offset < -reachAbove) {
        target = hold + regripBelow;
      }
      if (target == null) continue;
      _moving = i;
      _from = arcs[i];
      _to = target.clamp(top, end);
      _t = 0;
      return;
    }
  }
}
