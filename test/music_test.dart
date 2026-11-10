import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/audio/sound_bank.dart';
import 'package:umbra/chapters/chase.dart';
import 'package:umbra/config/game_settings.dart';
import 'package:umbra/ui/settings_panel.dart';
import 'package:umbra/world/stage.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('the sound page controls volume without exposing tracks', (
    tester,
  ) async {
    final settings = GameSettings();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SettingsPanel(
              settings: settings,
              unit: 7.2,
              initialTab: SettingsTab.sound,
            ),
          ),
        ),
      ),
    );
    expect(find.byType(PillToggle), findsNWidgets(2));
    expect(find.byType(ThinSlider), findsNWidgets(3));
    expect(find.byKey(const ValueKey('music')), findsOneWidget);
    expect(find.text('While playing'), findsNothing);
    expect(find.textContaining('Wastelands'), findsNothing);
    expect(find.textContaining('Tomb'), findsNothing);

    await tester.ensureVisible(find.byKey(const ValueKey('toggle-musicOn')));
    await tester.tap(find.byKey(const ValueKey('toggle-musicOn')));
    await tester.pump();
    expect(settings.musicOn, isFalse);
    await tester.tap(find.byKey(const ValueKey('toggle-soundOn')));
    await tester.pump();
    expect(settings.soundOn, isFalse);
  });

  testWidgets('menu music stays fixed and gameplay alternates each chapter', (
    tester,
  ) async {
    final game = await bootCampaign(tester);
    expect(game.director!.showingTitle, isTrue);
    expect(game.musicNow, SoundBank.menu);
    await enterChapter<Stage>(tester, game, 0);
    expect(game.musicNow, SoundBank.gameplayTomb);
    await enterChapter<Stage>(tester, game, 1);
    expect(game.musicNow, SoundBank.gameplayWastelands);
    await enterChapter<Stage>(tester, game, 2);
    expect(game.musicNow, SoundBank.gameplayTomb);
    final chase = await enterChapter<ChaseChapter>(tester, game, 15);
    expect(game.musicNow, SoundBank.gameplayWastelands);
    chase.reportThreat(ThreatLevel.tension);
    expect(game.musicNow, SoundBank.gameplayWastelands);
    chase.startChase();
    expect(game.musicNow, SoundBank.gameplayWastelands);
  });
}
