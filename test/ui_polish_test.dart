import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/config/game_settings.dart';
import 'package:umbra/ui/settings_panel.dart';
import 'package:umbra/ui/chapter_carousel.dart';
import 'package:umbra/ui/startup_intro.dart';

void main() {
  testWidgets('settings stay stable across tabs and reset needs confirmation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 360);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final settings = GameSettings()..set('music', .2);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SettingsPanel(settings: settings, unit: 3.6, onBack: () {}),
          ),
        ),
      ),
    );
    final before = tester.getRect(find.byType(SettingsPanel));
    for (final tab in ['Controls', 'Sound', 'Display']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
      expect(tester.getRect(find.byType(SettingsPanel)), before);
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(settings.music, .2);
    await tester.tap(find.text('Reset'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Reset').last);
    await tester.pumpAndSettle();
    expect(settings.music, .6);
    expect(find.text('Settings restored'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets(
    'chapters support slow swipes, groups and locked launch protection',
    (tester) async {
      int? played;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChapterCarousel(
              reached: 2,
              initialIndex: 2,
              currentIndex: 2,
              onBack: () {},
              onPlay: (i) => played = i,
            ),
          ),
        ),
      );
      expect(find.text('CONTINUE'), findsOneWidget);
      await tester.timedDrag(
        find.byType(ChapterCarousel),
        const Offset(-100, 0),
        const Duration(seconds: 2),
      );
      await tester.pumpAndSettle();
      expect(find.text('4 / 40'), findsOneWidget);
      expect(find.text('Complete chapter 3 to unlock'), findsOneWidget);
      await tester.tap(find.text('LOCKED'));
      expect(played, isNull);
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('36–40').last);
      await tester.pumpAndSettle();
      expect(find.text('36 / 40'), findsOneWidget);
    },
  );

  testWidgets('reduced motion is persistent and skips animated intro', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final settings = await GameSettings.load();
    settings.setFlag('reducedMotion', true);
    await tester.pump();
    expect((await GameSettings.load()).reducedMotion, isTrue);
    await tester.pumpWidget(
      MaterialApp(home: StartupIntro(settings: settings)),
    );
    expect(find.text('Tap to skip'), findsNothing);
    await settings.reset();
    expect(settings.reducedMotion, isFalse);
  });

  testWidgets(
    'phone layouts render at large text size and capture desktop previews',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [
        const Size(375, 812),
        const Size(800, 360),
        const Size(1280, 720),
      ]) {
        tester.view.physicalSize = size;
        for (final chapter in [false, true]) {
          await tester.pumpWidget(
            MaterialApp(
              home: MediaQuery(
                data: MediaQueryData(
                  size: size,
                  textScaler: TextScaler.linear(size.width == 375 ? 1.5 : 1),
                ),
                child: Scaffold(
                  body: RepaintBoundary(
                    key: const ValueKey('capture'),
                    child: chapter
                        ? ChapterCarousel(
                            reached: 2,
                            initialIndex: 2,
                            onBack: () {},
                            onPlay: (_) {},
                          )
                        : Center(
                            child: SingleChildScrollView(
                              child: SettingsPanel(
                                settings: GameSettings(),
                                unit: size.shortestSide / 100,
                                width: size.width * .86,
                                onBack: () {},
                              ),
                            ),
                          ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (size.width == 1280) {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(const ValueKey('capture')),
            );
            await tester.runAsync(() async {
              final image = await boundary.toImage();
              final bytes = await image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              await File(
                'screenshots/polished-${chapter ? "chapters" : "settings"}.png',
              ).writeAsBytes(bytes!.buffer.asUint8List());
              image.dispose();
            });
          }
        }
      }
    },
  );
}
