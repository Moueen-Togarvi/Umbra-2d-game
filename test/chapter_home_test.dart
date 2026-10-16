import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/home.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';
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

  void step(UmbraGame game, double seconds) {
    for (var i = 0; i < (seconds * 60).round(); i++) {
      game.update(1 / 60);
    }
  }

  testWidgets('the title waits on the first scene with the boy indoors', (
    tester,
  ) async {
    final game = await boot(tester);
    step(game, 3);
    final home = game.stage! as HomeChapter;
    expect(game.director!.showingTitle, isTrue);
    expect(home.player.hidden, isTrue);
    expect(game.intent.isScripted, isTrue);
    expect(game.blackness, lessThan(0.01));
    // Keys do nothing behind the title.
    final double x = home.player.body.position.x;
    game.intent.setKeyboardState(axis: 1);
    step(game, 1);
    expect(home.player.body.position.x, closeTo(x, 0.05));
    game.intent.setKeyboardState(axis: 0);
  });

  testWidgets('the opening: the door bursts open, he runs out, she reaches '
      'after him, and he is given the controls', (tester) async {
    final game = await boot(tester);
    step(game, 3);
    final home = game.stage! as HomeChapter;
    game.director!.begin();
    double widest = 0, reach = 0;
    var seenOut = false;
    for (var i = 0; i < 60 * 20 && game.intent.isScripted; i++) {
      game.update(1 / 60);
      widest = widest < home.cottage.doorAngle
          ? home.cottage.doorAngle
          : widest;
      reach = reach < home.cottage.mother.reach
          ? home.cottage.mother.reach
          : reach;
      seenOut |= !home.player.hidden;
    }
    expect(game.intent.isScripted, isFalse, reason: 'controls handed back');
    expect(seenOut, isTrue);
    expect(widest, greaterThan(1.4), reason: 'the door was thrown open');
    // It stays open: the hinges are stiff and it only bounces a little.
    expect(home.cottage.doorAngle, greaterThan(1.3));
    expect(reach, 1);
    expect(home.player.body.position.x, greaterThan(14));
    expect(home.cameraFocus, isNull, reason: 'the camera follows him again');
  });

  testWidgets('chapter one can be played from the door to the forest', (
    tester,
  ) async {
    final game = await boot(tester);
    step(game, 3);
    final home = game.stage! as HomeChapter;
    game.director!.begin();
    for (var i = 0; i < 60 * 20 && game.intent.isScripted; i++) {
      game.update(1 / 60);
    }
    final player = home.player;
    final intent = game.intent;
    final jumped = <String>{};
    var climbedWall = false, swung = false, rodePlank = false;
    double reached = 0;

    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 150 && !home.isComplete; i++) {
      intent.setKeyboardState(axis: 1);
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      if (!intent.isScripted) {
        if (grounded && x > 27.5 && x < 28.4 && !jumped.contains('fence')) {
          jump('fence');
        }
        // Push the cart to the wall, get up on it, then up the wall.
        final double cartRight =
            home.cart.body.position.x + home.cart.size.x / 2;
        if (grounded &&
            cartRight > 34.1 &&
            x < 33.7 &&
            feet > 6.9 &&
            !jumped.contains('cart')) {
          jump('cart');
        }
        if (grounded &&
            jumped.contains('cart') &&
            feet < 6.6 &&
            x > 33.3 &&
            !jumped.contains('wall')) {
          jump('wall');
        }
        if (mode == InteractionMode.hanging ||
            mode == InteractionMode.climbing) {
          climbedWall |= x > 33 && x < 37;
        }
        if (grounded && x > 46.1 && x < 46.6 && !jumped.contains('plank')) {
          jump('plank');
        }
        if (grounded && x > 47 && x < 51.2) rodePlank = true;
        if (grounded &&
            x > 50.4 &&
            x < 51.2 &&
            feet > 7.0 &&
            !jumped.contains('lip')) {
          jump('lip');
        }
        if (grounded && x > 57.2 && x < 58 && !jumped.contains('log')) {
          jump('log');
        }
        if (grounded && x > 65.3 && x < 66 && !jumped.contains('gully')) {
          jump('gully');
        }
        if (mode == InteractionMode.swinging) {
          swung = true;
          final double vx = player.velocity.x;
          if (x > 68.4 && vx > 1.5 && !jumped.contains('release')) {
            jump('release');
          }
        }
        if (grounded && x > 82.3 && x < 83 && !jumped.contains('rock')) {
          jump('rock');
        }
        if (grounded && x > 92.1 && x < 92.8 && !jumped.contains('log2')) {
          jump('log2');
        }
      }
      game.update(1 / 60);
      expect(
        player.isDead,
        isFalse,
        reason:
            'died at x=${x.toStringAsFixed(2)} after $jumped '
            '(mode $mode, plank ${home.plank.body.angle.toStringAsFixed(2)})',
      );
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0);
    expect(
      home.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped',
    );
    expect(climbedWall, isTrue, reason: 'the wall is climbed from the cart');
    expect(rodePlank, isTrue, reason: 'the ditch is crossed on the plank');
    expect(swung, isTrue, reason: 'the gully is crossed on the tyre swing');
    expect(game.checkpoints.activeCheckpoint.x, greaterThan(99));
  });

  testWidgets('without the cart the wall cannot be climbed', (tester) async {
    final game = await boot(tester);
    step(game, 3);
    final home = game.stage! as HomeChapter;
    game.director!.begin();
    for (var i = 0; i < 60 * 20 && game.intent.isScripted; i++) {
      game.update(1 / 60);
    }
    // Put him on the far side of the cart, at the foot of the wall.
    home.player.teleportTo(Vector2(33.6, home.groundAt(33.6) - 0.65));
    step(game, 0.5);
    for (var k = 0; k < 4; k++) {
      game.intent.setKeyboardState(axis: 1);
      game.intent.requestJump();
      step(game, 1.4);
    }
    game.intent.setKeyboardState(axis: 0);
    expect(home.player.body.position.x, lessThan(34.3));
  });
}
