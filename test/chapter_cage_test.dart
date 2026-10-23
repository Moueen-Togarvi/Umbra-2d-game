import 'support/route_pilot.dart';
import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/cage.dart';
import 'package:umbra/game/umbra_game.dart';

void main() {
  Future<UmbraGame> boot(WidgetTester tester) async {
    final game = UmbraGame(campaign: true);
    await tester.pumpWidget(GameWidget(game: game));
    for (var i = 0; i < 60 && game.stage?.isLoaded != true; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(() {
      game.pauseEngine();
      if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
    });
    return game;
  }

  Future<void> until(
    WidgetTester tester,
    UmbraGame game,
    bool Function() done, {
    int frames = 900,
  }) async {
    for (var i = 0; i < frames && !done(); i++) {
      driveExtension(game);
      game.update(1 / 60);
      if (i % 4 == 0) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 2)),
        );
        await tester.pump();
      }
    }
  }

  Future<CageChapter> enter(WidgetTester tester, UmbraGame game) async {
    for (var i = 0; i < 180; i++) {
      driveExtension(game);
      game.update(1 / 60);
    }
    game.director!.playChapter(5);
    await until(
      tester,
      game,
      () => game.director!.isPlaying && !game.director!.isBusy,
    );
    final cage = game.stage! as CageChapter;
    await until(tester, game, () => !game.intent.isScripted, frames: 900);
    return cage;
  }

  testWidgets('a slow knock leaves the door shut', (tester) async {
    final game = await boot(tester);
    final cage = await enter(tester, game);
    // Standing still, nothing swings it.
    for (var i = 0; i < 60 * 4; i++) {
      driveExtension(game);
      game.update(1 / 60);
    }
    // Getting up shifts his weight and rocks it a little; nothing like
    // a blow hard enough for the latch.
    expect(cage.cell.isOpen, isFalse);
    expect(cage.cell.hardestHit, lessThan(cage.cell.breakSpeed!));
    expect(
      (cage.cell.body.position.x - cage.cell.restCentre.x).abs(),
      lessThan(0.6),
    );
  });

  testWidgets('chapter three: swing the cage open, cross the cages, lower '
      'the bridge, hide from the guard, and out', (tester) async {
    final game = await boot(tester);
    final cage = await enter(tester, game);
    final player = cage.player;
    final intent = game.intent;
    final jumped = <String>{};
    var hid = false, rodeCages = false, crossedBridge = false;
    double reached = 0;
    double swingSeconds = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 900 && !cage.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + 0.65;
      final bool grounded = player.isOnGround;
      double axis = 1;
      if (!intent.isScripted) {
        if (!cage.cell.isOpen) {
          // Run against the swing, back and forth, to pump it higher.
          swingSeconds += 1 / 60;
          final double v = cage.cell.body.linearVelocity.x;
          final double rel = x - cage.cell.body.position.x;
          axis = v.abs() < 0.05 ? 1 : -v.sign;
          if (rel > 0.5) axis = -1;
          if (rel < -0.5) axis = 1;
        } else if (x < CageChapter.ledgeX + 0.3) {
          // Out of the open side when it swings close to the ledge.
          final double near = cage.cell.body.position.x + cage.cell.width / 2;
          axis = 1;
          if (grounded &&
              near > CageChapter.ledgeX - 0.5 &&
              !jumped.contains('out')) {
            jump('out');
          }
        }
        if (grounded && x > 17.5 && x < 18.1 && !jumped.contains('beam')) {
          jump('beam');
        }
        if (grounded && x > 35.5 && x < 36.2 && !jumped.contains('step')) {
          jump('step');
        }
        if (grounded &&
            feet < 6 &&
            x > 39.4 &&
            x < 40.0 &&
            !jumped.contains('c1')) {
          jump('c1');
        }
        if (grounded &&
            x > 42.2 &&
            x < 42.7 &&
            feet < 6.2 &&
            !jumped.contains('c2')) {
          rodeCages = true;
          jump('c2');
        }
        if (grounded &&
            x > 44.9 &&
            x < 45.4 &&
            feet < 6.2 &&
            !jumped.contains('c3')) {
          jump('c3');
        }
        // Jump onto the raised end of the lever; then wait for the bridge.
        if (grounded && x > 51.8 && x < 52.3 && !jumped.contains('lever')) {
          jump('lever');
        }
        if (x > 55.6 && x < 57 && !cage.bridge.isDown) axis = 0;
        if (x > 57 && x < 61) crossedBridge = true;
        // The guard's tunnel.
        final guard = cage.guard;
        if (x > 71 && x < 74 && !(guard.facing > 0 && guard.x > 87)) {
          axis = 0;
        }
        if (x > 85.6 && x < 86.4) {
          final bool passed = guard.facing < 0 && guard.x < 84.4;
          if (!passed) {
            axis = 0;
            hid |= cage.hidden;
          }
        }
      }
      intent.setKeyboardState(
        axis: axis,
        sit: x > 85.3 && x < 86.7 && axis == 0,
      );
      driveExtension(game);
      game.update(1 / 60);
      expect(
        player.isDead,
        isFalse,
        reason:
            'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
            'after $jumped (guard ${cage.guard.x.toStringAsFixed(1)})',
      );
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      cage.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; '
          'cage open ${cage.cell.isOpen}; lever ${cage.lever.body.angle.toStringAsFixed(2)} '
          'mode ${player.interactions.mode}',
    );
    expect(swingSeconds, greaterThan(2), reason: 'it takes some swinging');
    expect(rodeCages, isTrue);
    expect(cage.lever.pressed, isTrue);
    expect(crossedBridge, isTrue);
    expect(hid, isTrue, reason: 'he hid in the niche as it passed');
  });

  testWidgets('walking into the guard is death', (tester) async {
    final game = await boot(tester);
    final cage = await enter(tester, game);
    cage.player.teleportTo(Vector2(80, cage.groundAt(80) - 0.65));
    cage.guard
      ..x = 84
      ..patrol(77, 97);
    for (var i = 0; i < 60 * 6 && !cage.player.isDead; i++) {
      game.intent.setKeyboardState(axis: 1);
      driveExtension(game);
      game.update(1 / 60);
    }
    expect(cage.player.isDead, isTrue);
  });
}
