import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/story/progress_store.dart';
import 'package:umbra/ui/title_screen.dart';

void main() {
  testWidgets('chapter carousel matches Umbra artwork and lock treatment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await (FontLoader(
      'Cinzel',
    )..addFont(rootBundle.load('assets/fonts/Cinzel-Variable.ttf'))).load();
    final game = UmbraGame(campaign: true, progress: ProgressStore.memory(1));
    await tester.pumpWidget(MaterialApp(home: TitleScreen(game: game)));
    await tester.pump(const Duration(seconds: 4));
    await tester.tap(find.text('CHAPTERS'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(() async {
      final context = tester.element(find.byType(TitleScreen));
      await Future.wait([
        precacheImage(
          const AssetImage('assets/images/ui/menu_background_v2.png'),
          context,
        ),
        for (final id in ['home', 'old_orchard', 'hunters_road', 'graveyard'])
          precacheImage(
            AssetImage('assets/images/chapter_cards/$id.webp'),
            context,
          ),
      ]);
    });
    await tester.pump();
    await expectLater(
      find.byType(TitleScreen),
      matchesGoldenFile('goldens/chapter-carousel.png'),
    );
  });
}
