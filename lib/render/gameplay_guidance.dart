import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../character/character_interactions.dart';
import '../config/game_config.dart';
import '../config/game_settings.dart';
import '../entities/hazard.dart';
import '../entities/castle_traps.dart';
import '../entities/physics_props.dart';
import '../entities/player.dart';
import '../entities/trap_props.dart';
import '../entities/weapon_pickup.dart';
import '../input/player_intent.dart';
import '../world/stage.dart';

/// Quiet, contextual guidance shared by every chapter.
///
/// It teaches actions by observing successful play, then retires permanently.
/// After that it only appears for nearby danger, usable objects, checkpoints,
/// or when the player has made no progress for a while.
class GameplayGuidance extends Component {
  GameplayGuidance({
    required this.camera,
    required this.player,
    required this.stage,
    required this.intent,
    required this.settings,
    required this.chapterIndex,
    required this.tutorialEnabled,
  }) : super(priority: 8000);

  final CameraComponent camera;
  final Player? Function() player;
  final Stage? Function() stage;
  final PlayerIntent intent;
  final GameSettings settings;
  final int Function() chapterIndex;
  final bool Function() tutorialEnabled;

  final TextPainter _text = TextPainter(
    textDirection: TextDirection.ltr,
    textAlign: TextAlign.center,
  );
  String _message = '';
  Vector2? _target;
  double _visible = 0;
  double _idle = 0;
  double _warningRest = 0;
  double _checkpoint = 0;
  double _scanRest = 0;
  int _tutorial = 0;
  double? _furthestX;
  (Vector2, double)? _danger;
  (String, Vector2)? _usable;

  static const tutorialMessages = [
    'HOLD LEFT OR RIGHT TO MOVE',
    'WALK INTO THE GLOWING KATANA',
    'TAP ATTACK TO STUN THE TARGET',
    'TAP JUMP TO CLEAR THE LOG',
    'HOLD SIT TO CROUCH LOW',
    'PUSH AGAINST THE CART',
    'JUMP INTO THE ROPE TO CATCH IT',
  ];

  void checkpointReached() {
    _checkpoint = 2.2;
  }

  @override
  void update(double dt) {
    final boy = player();
    final place = stage();
    if (boy == null || place == null || !boy.isMounted || boy.isDead) {
      _message = '';
      _target = null;
      return;
    }
    if (place.controlsHidden || intent.isScripted) {
      _message = '';
      _target = null;
      return;
    }
    _visible = math.max(0, _visible - dt);
    _warningRest = math.max(0, _warningRest - dt);
    _checkpoint = math.max(0, _checkpoint - dt);
    _scanRest -= dt;

    final x = boy.body.position.x;
    final previous = _furthestX;
    if (previous == null || x > previous + .45 || boy.velocity.length > .55) {
      _furthestX = previous == null ? x : math.max(previous, x);
      _idle = 0;
    } else {
      _idle += dt;
    }

    if (!settings.tutorialComplete &&
        tutorialEnabled() &&
        chapterIndex() == 0) {
      _advanceTutorial(boy, place);
      if (_tutorial < tutorialMessages.length) {
        _show(tutorialMessages[_tutorial]);
        return;
      }
    }

    if (_checkpoint > 0) {
      _show('CHECKPOINT SAVED');
      return;
    }

    if (_scanRest <= 0) {
      _danger = _nearestDanger(place, boy.body.position);
      _usable = _nearestUsable(place, boy.body.position);
      _scanRest = .18;
    }
    final danger = _danger;
    if (danger != null && danger.$2 <= GameConfig.dangerWarningMeters) {
      _target = danger.$1;
      _show(
        place.threat == ThreatLevel.chase
            ? 'RUN — IT IS CLOSE'
            : 'DANGER AHEAD',
      );
      if (_warningRest <= 0) {
        place.cue('tick', weight: .34, at: danger.$1);
        _warningRest = 2.5;
      }
      return;
    }

    final usable = _usable;
    if (usable != null) {
      _target = usable.$2;
      _show(usable.$1);
      return;
    }

    if (place.threat == ThreatLevel.chase) {
      _show('KEEP MOVING — BREAK ITS SIGHT');
    } else if (_idle > 18) {
      _show('LOOK FOR MOVEMENT OR A PATH THROUGH THE FOG');
    } else if (_visible <= 0) {
      _message = '';
      _target = null;
    }
  }

  void _advanceTutorial(Player boy, Stage place) {
    final complete = switch (_tutorial) {
      0 => intent.horizontalAxis.abs() > .2 || boy.velocity.x.abs() > .8,
      1 =>
        place.descendants().whereType<WeaponPickup>().isEmpty ||
            boy.body.position.x > 21.4,
      2 =>
        place.descendants().whereType<TrainingEffigy>().any(
              (target) => target.isCombatStunned,
            ) ||
            boy.body.position.x > 26.8,
      3 => !boy.isOnGround && boy.velocity.y.abs() > .4,
      4 => boy.isLow,
      5 =>
        boy.interactions.mode == InteractionMode.pushing ||
            boy.interactions.mode == InteractionMode.pulling,
      6 => boy.isOnRope,
      _ => false,
    };
    if (!complete) return;
    _tutorial++;
    if (_tutorial >= tutorialMessages.length) {
      settings.completeTutorial();
      _show('YOU ARE READY');
    }
  }

  void _show(String value) {
    _message = value;
    _visible = .25;
  }

  (Vector2, double)? _nearestDanger(Stage place, Vector2 from) {
    Vector2? nearest;
    var distance = double.infinity;
    for (final item in place.descendants()) {
      final Vector2? at = switch (item) {
        Hazard() when item.isMounted && item.body.isValid => item.body.position,
        BearTrap() when !item.sprung => Vector2(item.x, item.groundY),
        ArrowTrap() => Vector2(item.wires.first, item.floor),
        _ => null,
      };
      if (at == null || at.x < from.x - .5) continue;
      final d = (at - from).length;
      if (d < distance) {
        nearest = at;
        distance = d;
      }
    }
    return nearest == null ? null : (nearest, distance);
  }

  (String, Vector2)? _nearestUsable(Stage place, Vector2 from) {
    for (final item in place.descendants()) {
      if (item is PhysicsCrate && item.isReady) {
        final d = (item.body.position - from).length;
        if (d < 1.55) return ('PUSH AGAINST IT TO MOVE IT', item.body.position);
      }
      if (item is SwingRope && item.isReady) {
        final d = (item.grip - from).length;
        if (d < 2.1) return ('JUMP TO CATCH THE ROPE', item.grip);
      }
    }
    return null;
  }

  @override
  void render(Canvas canvas) {
    if (_message.isEmpty || _visible <= 0) return;
    final view = camera.viewport.size;
    if (view.x <= 0) return;
    _text.text = TextSpan(
      text: _message,
      style: TextStyle(
        fontFamily: 'Roboto',
        fontSize: (view.y * .035).clamp(13, 18),
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: const Color(0xEEFFFFFF),
        shadows: const [Shadow(color: Color(0xFF000000), blurRadius: 8)],
      ),
    );
    _text.layout(maxWidth: view.x * .72);
    final box = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(view.x / 2, view.y * .18),
        width: _text.width + 30,
        height: _text.height + 18,
      ),
      const Radius.circular(7),
    );
    canvas.drawRRect(box, Paint()..color = const Color(0x85000000));
    _text.paint(canvas, Offset((view.x - _text.width) / 2, box.top + 9));

    final target = _target;
    if (target == null) return;
    final point = camera.localToGlobal(target);
    final pulse = 7 + 2 * math.sin(_visible * 8).abs();
    canvas.drawCircle(
      point.toOffset(),
      pulse,
      Paint()
        ..color = const Color(0xAAFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }
}
