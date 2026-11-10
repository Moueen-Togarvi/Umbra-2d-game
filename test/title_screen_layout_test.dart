import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/story/chapter_director.dart';
import 'package:umbra/story/progress_store.dart';
import 'package:umbra/ui/title_screen.dart';

void main() {
  Future<UmbraGame> openTitle(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final game = UmbraGame(campaign: true, progress: ProgressStore.memory(2));
    await tester.pumpWidget(MaterialApp(home: TitleScreen(game: game)));
    await tester.pump(const Duration(seconds: 4));
    return game;
  }

  testWidgets('main-menu settings content is centered on phone and desktop', (
    tester,
  ) async {
    for (final size in [const Size(800, 360), const Size(1280, 720)]) {
      await openTitle(tester, size);
      await tester.tap(find.text('SETTINGS'));
      await tester.pump();
      final rect = tester.getRect(
        find.byKey(const ValueKey('title-settings-content')),
      );
      expect(rect.center.dx, closeTo(size.width / 2, 1));
      expect(rect.center.dy, closeTo(size.height / 2, 1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });

  testWidgets(
    'chapter picker browses cards and keeps locked chapters disabled',
    (tester) async {
      final game = await openTitle(tester, const Size(800, 360));
      game.director = ChapterDirector(game: game, progress: game.progress);
      await tester.tap(find.text('CHAPTERS'));
      await tester.pump();
      expect(find.byKey(const ValueKey('chapter-card-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('chapter-card-4')), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key! as ValueKey<String>).value.startsWith(
                'chapter-card-',
              ),
        ),
        findsNWidgets(5),
      );
      expect(find.byKey(const ValueKey('chapter-lock-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('chapter-lock-4')), findsOneWidget);
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('chapter-card-2')))
            .onTap,
        isNotNull,
      );
      expect(
        tester
            .widget<InkWell>(find.byKey(const ValueKey('chapter-card-3')))
            .onTap,
        isNotNull,
      );
      await tester.tap(find.byKey(const ValueKey('chapter-card-3')));
      await tester.pump();
      expect(find.text('LOCKED'), findsOneWidget);
      expect(
        tester
            .widget<TextButton>(
              find.ancestor(
                of: find.text('LOCKED'),
                matching: find.byType(TextButton),
              ),
            )
            .onPressed,
        isNull,
      );
    },
  );
}
