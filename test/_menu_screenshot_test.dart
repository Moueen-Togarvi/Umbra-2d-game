import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/ui/pause_screen.dart';
import 'package:umbra/ui/title_screen.dart';
import 'package:umbra/story/progress_store.dart';

void main() {
  testWidgets('capture pause settings actions', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    final cinzel = FontLoader('Cinzel')
      ..addFont(rootBundle.load('assets/fonts/Cinzel-Variable.ttf'));
    final cormorant = FontLoader('Cormorant')
      ..addFont(rootBundle.load('assets/fonts/CormorantGaramond-Italic.ttf'));
    await cinzel.load();
    await cormorant.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              'assets/images/ui/menu_background_v2.png',
              fit: BoxFit.cover,
            ),
            PauseScreen(game: UmbraGame(campaign: true)),
          ],
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/ui/menu_background_v2.png'),
        tester.element(find.byType(PauseScreen)),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PauseScreen),
      matchesGoldenFile('goldens/pause-menu-first.png'),
    );
    await tester.tap(find.text('SETTINGS'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PauseScreen),
      matchesGoldenFile('goldens/after-display.png'),
    );
    await tester.tap(find.text('Controls'));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(PauseScreen),
      matchesGoldenFile('goldens/after-controls.png'),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(fontFamily: 'Cinzel'),
        home: TitleScreen(
          game: UmbraGame(campaign: true, progress: ProgressStore.memory(4)),
        ),
      ),
    );
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/ui/menu_background_chase.png'),
        tester.element(find.byType(TitleScreen)),
      ),
    );
    await tester.pump(const Duration(seconds: 4));
    await expectLater(
      find.byType(TitleScreen),
      matchesGoldenFile('goldens/after-main-menu.png'),
    );
    await tester.pumpWidget(const SizedBox());
  });
}
