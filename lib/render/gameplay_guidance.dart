import 'dart:math' as math;
import 'package:flame/components.dart';
import 'package:flutter/painting.dart';

import '../character/character_interactions.dart';
import '../combat/combat_target.dart';
import '../combat/weapons.dart';
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
    required this.kit,
  }) : super(priority: 8000);

  final CombatKit Function() kit;

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
    _clock += dt;
    final boy = player();
    final place = stage();
    prompt = null;
    promptTarget = null;
    if (place != null) place.timeScale = 1;
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

    _combatLesson(place, boy);

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

  /// The button a fight lesson points at (a layout id), or null. Combat
  /// is taught without words: the button pulses, and a ring marks what it
  /// is for.
  String? prompt;
  Vector2? promptTarget;
  bool _slowShown = false, _dashShown = false;

  /// Chapter 1 points at Slash by the dummy and at the first vampire's
  /// wind-up (time slows for it, once), and at Throw for a vampire out of
  /// reach. Chapter 2 points at Dash the first time a claw winds up.
  void _combatLesson(Stage place, Player boy) {
    prompt = null;
    promptTarget = null;
    final chapter = chapterIndex();
    final kit = this.kit();
    if (!tutorialEnabled() && chapter != 1) return;
    if (chapter > 1 || !kit.hasSword) {
      place.timeScale = 1;
      return;
    }
    final at = boy.body.position;
    final facing = boy.facing;
    CombatTarget? close, far;
    bool telegraph = false;
    for (final target in place.descendants().whereType<CombatTarget>()) {
      if (!target.canReceiveCombatHit) continue;
      final delta = target.combatPosition - at;
      if (delta.y.abs() > 1.6 || delta.x * facing < -.3) continue;
      final d = delta.x.abs();
      if (d <= AttackTiming.slashReach - .05) {
        close ??= target;
        telegraph |= target is CombatTelegraph &&
            (target as CombatTelegraph).isTelegraphing;
      } else if (d <= 12 && target is! TrainingEffigy) {
        far ??= target;
      }
    }
    if (chapter == 1) {
      if (!_dashShown && telegraph) {
        prompt = 'dash';
        promptTarget = close!.combatPosition;
        _dashShown = true;
      }
      return;
    }
    final slow = telegraph && !_slowShown;
    place.timeScale = slow ? .3 : 1;
    if (!slow && telegraph) _slowShown = true;
    if (close != null && (close is TrainingEffigy || telegraph || slow)) {
      prompt = 'attack';
      promptTarget = close.combatPosition;
    } else if (close == null && far != null && kit.hasShuriken) {
      prompt = 'throw';
      promptTarget = far.combatPosition;
    }
  }

  void _advanceTutorial(Player boy, Stage place) {
    final complete = switch (_tutorial) {
      0 => intent.horizontalAxis.abs() > .2 || boy.velocity.x.abs() > .8,
      1 => !boy.isOnGround && boy.velocity.y.abs() > .4,
      2 => boy.isLow,
      3 =>
        boy.interactions.mode == InteractionMode.pushing ||
            boy.interactions.mode == InteractionMode.pulling,
      4 => boy.isOnRope,
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

  double _clock = 0;

  @override
  void render(Canvas canvas) {
    final view = camera.viewport.size;
    if (view.x <= 0) return;
    final lesson = promptTarget;
    if (lesson != null) {
      // What the pulsing button is for: a ring closing in on it.
      final point = camera.localToGlobal(lesson).toOffset();
      final t = (_clock * 1.4) % 1;
      canvas.drawCircle(
        point,
        34 - 16 * t,
        Paint()
          ..color = Color.fromRGBO(255, 255, 255, .25 + .6 * t)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 + t,
      );
    }
    if (_message.isEmpty || _visible <= 0) return;
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
