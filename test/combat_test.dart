import 'dart:convert';

import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'package:umbra/combat/projectile.dart';
import 'package:umbra/combat/weapons.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/story/hunters.dart';
import 'package:umbra/story/progress_store.dart';
import 'package:umbra/story/vampire.dart';
import 'support/campaign.dart';

void main() {
  /// A patrol room's hunter [gap] metres to the right of the boy, who faces
  /// him.
  Future<(UmbraGame, JourneyChapter, Stalker)> faceHunter(
    WidgetTester tester, {
    double gap = 1.0,
  }) async {
    final game = await bootCampaign(tester);
    final stage = await enterChapter<JourneyChapter>(tester, game, 3);
    final room = stage.rooms.firstWhere((r) => r.kind == PuzzleKind.patrol);
    final hunter = room.hunter!;
    final x = room.x + 8;
    stage.player.teleportTo(Vector2(x, stage.groundAt(x) - .65));
    game.intent.setKeyboardState(axis: 1);
    step(game, .2);
    game.intent.setKeyboardState(axis: 0);
    stage.player.teleportTo(Vector2(x, stage.groundAt(x) - .65));
    hunter.reset(x + gap);
    step(game, .05);
    return (game, stage, hunter);
  }

  testWidgets('later chapters start with the sword and three stars', (
    tester,
  ) async {
    final (game, _, _) = await faceHunter(tester, gap: 10);
    expect(game.kit.hasSword, isTrue);
    expect(game.kit.hasShuriken, isTrue);
    expect(game.kit.stars, CombatKit.maxStars);
    expect(game.player!.facing, 1);
  });

  testWidgets('one slash cuts a hunter down to ash', (tester) async {
    final (game, _, hunter) = await faceHunter(tester);
    expect(hunter.vampire.killable, isTrue);
    game.intent.requestAttack();
    step(game, .3);
    expect(hunter.vampire.mode, VampireMode.burn);
    step(game, 1.5);
    expect(hunter.vampire.gone, isTrue);
    expect(game.player!.isDead, isFalse);
  });

  testWidgets('a chaser only reels back from the blade', (tester) async {
    final (game, _, hunter) = await faceHunter(tester);
    hunter.vampire.killable = false;
    final x = hunter.vampire.x;
    game.intent.requestAttack();
    step(game, .3);
    expect(hunter.vampire.mode, isNot(VampireMode.burn));
    expect(hunter.vampire.isCombatStunned, isTrue);
    expect(hunter.vampire.x, greaterThan(x + .3));
  });

  testWidgets('a thrown star flies to a far hunter and spends one star', (
    tester,
  ) async {
    final (game, stage, hunter) = await faceHunter(tester, gap: 6);
    game.intent.requestThrow();
    step(game, .15);
    expect(stage.descendants().whereType<Shuriken>(), hasLength(1));
    expect(game.kit.stars, CombatKit.maxStars - 1);
    step(game, .6);
    expect(hunter.vampire.mode, VampireMode.burn);
    expect(stage.descendants().whereType<Shuriken>(), isEmpty);
  });

  testWidgets('a claw kills in one blow, except through a dash', (
    tester,
  ) async {
    final (game, _, _) = await faceHunter(tester, gap: 12);
    final boy = game.player!;
    game.intent.requestDash();
    step(game, 2 / 60);
    expect(boy.isDashing, isTrue);
    expect(boy.receiveEnemyHit(direction: -1), isFalse);
    expect(boy.isDead, isFalse);
    step(game, .5);
    expect(boy.isDashing, isFalse);
    expect(boy.receiveEnemyHit(direction: -1), isTrue);
    expect(boy.isDead, isTrue);
  });

  test('old saves with any weapon record carry the whole kit', () async {
    SharedPreferences.setMockInitialValues({
      ProgressStore.key: jsonEncode({
        'version': 3,
        'furthest': 'home',
        'chapter': 'home',
        'checkpoint': null,
        'weapons': {'katana': 2},
        'equipped': ['katana', null, null],
        'activeWeaponSlot': 0,
        'pickups': [0],
      }),
    });
    final kit = CombatKit.fromProgress(await ProgressStore.load());
    expect(kit.hasSword, isTrue);
    expect(kit.hasShuriken, isTrue);
    expect(kit.stars, CombatKit.maxStars);
  });
}

void step(UmbraGame game, double seconds) {
  for (var i = 0; i < (seconds * 60).round(); i++) {
    game.update(1 / 60);
  }
}
