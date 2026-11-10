import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/combat/weapons.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/story/progress_store.dart';
import 'package:umbra/ui/pause_screen.dart';
import 'package:umbra/ui/weapon_overlays.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('weapon radial switches slots and armory opens from pause', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final game = UmbraGame(progress: ProgressStore.memory());
    for (var chapter = 0; chapter < 3; chapter++) {
      game.weapons.unlock(WeaponCatalog.forChapter(chapter));
    }
    await tester.pumpWidget(
      MaterialApp(
        home: GameWidget<UmbraGame>(
          game: game,
          overlayBuilderMap: {
            UmbraGame.pauseOverlay: (_, game) => PauseScreen(game: game),
            UmbraGame.weaponRadialOverlay: (_, game) =>
                WeaponRadialOverlay(game: game),
            UmbraGame.weaponPickupOverlay: (_, game) =>
                WeaponPickupOverlay(game: game),
          },
        ),
      ),
    );
    for (var i = 0; i < 30 && game.player == null; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(game.player, isNotNull);

    game.openWeaponRadial();
    await tester.pump();
    expect(find.text('CHOOSE\nWEAPON'), findsOneWidget);
    await tester.tap(find.byType(WeaponIcon).at(1));
    await tester.pump();
    expect(game.weapons.activeSlot, 1);
    expect(game.isWeaponRadialOpen, isFalse);

    game.pauseGameplay();
    await tester.pump();
    await tester.tap(find.text('ARMORY'));
    await tester.pump();
    expect(
      find.text('Tap an unlocked weapon, then choose one of three slots.'),
      findsOneWidget,
    );

    game.pauseEngine();
    if (game.world.physicsWorld.isValid) game.world.physicsWorld.destroy();
  });
}
