import 'package:flame/game.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/character/character_rig.dart' show Gait;
import 'package:umbra/config/game_config.dart';
import 'package:umbra/entities/physics_props.dart';
import 'package:umbra/entities/player.dart';
import 'package:umbra/game/umbra_game.dart';

/// Every foot that comes down is heard: each stride at a run or a creep,
/// each little step in place; and never in the air.
void main() {
  Future<(UmbraGame, Player)> boot(WidgetTester tester) async {
    final game = UmbraGame();
    await tester.pumpWidget(GameWidget(game: game));
    for (
      var i = 0;
      i < 30 && game.world.descendants().whereType<Player>().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    game.pauseEngine();
    addTearDown(game.pauseEngine);
    // A clear run along the first stretch: no crates in the way.
    for (final crate in game.world.descendants().whereType<PhysicsCrate>()) {
      crate.removeFromParent();
    }
    for (var i = 0; i < 60; i++) {
      game.update(1 / 120);
    }
    return (game, game.world.descendants().whereType<Player>().single);
  }

  /// Runs the game for [seconds], keeping every foot contact.
  List<FootContact> run(UmbraGame game, Player player, double seconds) {
    final contacts = <FootContact>[];
    for (var i = 0; i < (seconds * 120).round(); i++) {
      final int before = player.footContacts;
      game.update(1 / 120);
      if (player.footContacts > before) contacts.add(player.lastFootContact!);
    }
    return contacts;
  }

  testWidgets('a run is heard foot by foot, both feet in turn', (tester) async {
    final (game, player) = await boot(tester);
    game.intent.setKeyboardState(axis: 1);
    run(game, player, 0.5);
    final double from = player.body.position.x;
    final contacts = run(game, player, 2.0);
    final double distance = player.body.position.x - from;
    game.intent.setKeyboardState(axis: 0);

    // Two steps to a stride.
    final double expected =
        2 * distance / Gait.strideMeters(GameConfig.moveSpeedMetersPerSecond);
    expect(contacts.length, closeTo(expected, expected * 0.25));
    expect(contacts.every((c) => c.stride && !c.onProp), isTrue);
    var alternate = 0;
    for (var i = 1; i < contacts.length; i++) {
      if (contacts[i].foot != contacts[i - 1].foot) alternate++;
    }
    expect(alternate, greaterThanOrEqualTo(contacts.length - 2));
    expect(
      contacts.map((c) => c.strength).reduce((a, b) => a < b ? a : b),
      greaterThan(0.55),
      reason: 'a run is the firmest step',
    );
  });

  testWidgets('a long walk never falls silent', (tester) async {
    final (game, player) = await boot(tester);
    for (final speed in [1.0, 0.5]) {
      game.intent.setKeyboardState(axis: speed);
      run(game, player, 0.6);
      var quiet = 0.0, longest = 0.0;
      for (var i = 0; i < 6 * 120; i++) {
        final int before = player.footContacts;
        game.update(1 / 120);
        final bool walking =
            player.isOnGround && player.velocity.x.abs() > 0.5;
        quiet = player.footContacts > before || !walking ? 0 : quiet + 1 / 120;
        if (quiet > longest) longest = quiet;
      }
      expect(longest, lessThan(0.6), reason: 'at $speed: no step goes unheard');
      game.intent.setKeyboardState(axis: -speed);
      run(game, player, 6.6);
    }
    game.intent.setKeyboardState(axis: 0);
  });

  testWidgets('nothing in the air', (tester) async {
    final (game, player) = await boot(tester);
    game.intent.setKeyboardState(axis: 1);
    run(game, player, 0.5);
    game.intent.requestJump();
    run(game, player, 0.1);
    expect(player.isOnGround, isFalse);
    final int before = player.footContacts;
    while (!player.isOnGround) {
      game.update(1 / 120);
      if (!player.isOnGround) expect(player.footContacts, before);
    }
    game.intent.setKeyboardState(axis: 0);
  });

  testWidgets('creeping is heard, softer than running', (tester) async {
    final (game, player) = await boot(tester);
    game.intent.setKeyboardState(sit: true, axis: 1);
    run(game, player, 0.6);
    final contacts = run(game, player, 2.0);
    game.intent.setKeyboardState(sit: false, axis: 0);
    expect(contacts, isNotEmpty);
    for (final contact in contacts) {
      expect(contact.stride, isTrue);
      expect(contact.strength, lessThan(0.5));
    }
  });

  testWidgets('stopping, the feet settle with soft little steps', (
    tester,
  ) async {
    final (game, player) = await boot(tester);
    game.intent.setKeyboardState(axis: 1);
    run(game, player, 0.8);
    game.intent.setKeyboardState(axis: 0);
    final settling = run(game, player, 1.5).where((c) => !c.stride);
    expect(settling, isNotEmpty, reason: 'a foot steps into place');
    for (final contact in settling) {
      expect(contact.strength, lessThan(0.3));
    }
    // Then still: nothing more.
    final int footfalls = player.footfalls;
    run(game, player, 1.0);
    expect(player.footfalls, footfalls);
  });

  testWidgets('on a plank the step is wood', (tester) async {
    final (game, player) = await boot(tester);
    // A heavy board lying on the ground, and him standing on it.
    await game.world.add(
      PhysicsCrate(
        position: Vector2(3.0, GameConfig.floorSurfaceY - 0.06),
        size: Vector2(3.0, 0.12),
        massKg: 300,
        friction: 0.9,
      ),
    );
    run(game, player, 0.1);
    player.teleportTo(
      Vector2(
        2.0,
        GameConfig.floorSurfaceY - 0.12 - GameConfig.playerHeight / 2,
      ),
    );
    run(game, player, 0.5);
    expect(player.onProp, isTrue);
    game.intent.setKeyboardState(axis: 1);
    final contacts = run(game, player, 0.6);
    game.intent.setKeyboardState(axis: 0);
    expect(contacts, isNotEmpty);
    expect(contacts.every((c) => c.onProp), isTrue);
  });
}
