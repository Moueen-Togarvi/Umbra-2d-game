import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_settings.dart';
import 'package:umbra/ui/settings_panel.dart';

void main() {
  Future<GameSettings> show(WidgetTester tester, [SettingsTab? tab]) async {
    final settings = GameSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsPanel(
              settings: settings,
              unit: 7.2,
              initialTab: tab ?? SettingsTab.display,
            ),
          ),
        ),
      ),
    );
    return settings;
  }

  testWidgets('three tabs, each with only its own settings', (tester) async {
    await show(tester);
    for (final key in ['brightness', 'atmosphere']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('controlsScale')), findsNothing);
    expect(find.byType(Switch), findsNothing, reason: 'no Material switches');
    expect(find.byType(Slider), findsNothing, reason: 'no Material sliders');

    await tester.tap(find.text('Controls'));
    await tester.pump();
    for (final key in [
      'controlsScale',
      'controlsOpacity',
      'toggle-vibration',
    ]) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
    expect(find.byKey(const ValueKey('brightness')), findsNothing);

    await tester.tap(find.text('Sound').first);
    await tester.pump();
    for (final key in ['music', 'ambience', 'effects', 'toggle-musicOn']) {
      expect(find.byKey(ValueKey(key)), findsOneWidget);
    }
  });

  testWidgets('a thin slider follows a tap and a drag, within its range', (
    tester,
  ) async {
    final settings = await show(tester);
    final slider = find.byKey(const ValueKey('brightness'));
    final box = tester.getRect(slider);
    await tester.tapAt(box.centerLeft + const Offset(1, 0));
    await tester.pump();
    expect(settings.brightness, closeTo(.8, .01));
    await tester.dragFrom(
      box.centerLeft + const Offset(4, 0),
      Offset(box.width * 2, 0),
    );
    await tester.pump();
    expect(settings.brightness, closeTo(1.3, .001), reason: 'held at its top');
    await tester.tapAt(box.center);
    await tester.pump();
    expect(settings.brightness, closeTo(1.05, .02));
  });

  testWidgets('a pill toggle turns its setting on and off', (tester) async {
    final settings = await show(tester, SettingsTab.controls);
    final bool was = settings.vibration;
    await tester.tap(find.byKey(const ValueKey('toggle-vibration')));
    await tester.pump();
    expect(settings.vibration, !was);
    await tester.tap(find.byKey(const ValueKey('toggle-vibration')));
    await tester.pump();
    expect(settings.vibration, was);
  });
}
