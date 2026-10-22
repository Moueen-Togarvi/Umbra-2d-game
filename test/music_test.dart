import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/audio/sound_bank.dart';
import 'package:umbra/chapters/chase.dart';
import 'package:umbra/config/game_settings.dart';
import 'package:umbra/game/umbra_game.dart';
import 'package:umbra/ui/audio_settings.dart';
import 'package:umbra/world/stage.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('the music panel: music and sound switches, three sliders, '
      'and every piece to play under the game', (tester) async {
    final settings = GameSettings();
    final tried = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: AudioSettings(settings: settings, onTry: tried.add),
          ),
        ),
      ),
    );
    expect(find.byType(Switch), findsNWidgets(2));
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.byKey(const ValueKey('music-${SoundBank.menu}')), findsNothing);
    for (final (id, title, _) in SoundBank.backgrounds) {
      expect(find.byKey(ValueKey('music-$id')), findsOneWidget);
      expect(find.textContaining(title), findsOneWidget);
    }

    await tester.tap(find.byKey(const ValueKey('music-bg_overshadow')));
    await tester.pump();
    expect(settings.background, 'bg_overshadow');
    expect(tried, ['bg_overshadow'], reason: 'tried out at once');

    await tester.tap(find.byType(Switch).first);
    await tester.pump();
    expect(settings.musicOn, isFalse);
    await tester.tap(find.byType(Switch).last);
    await tester.pump();
    expect(settings.soundOn, isFalse);
  });

  testWidgets('the menu has its own music, play another, '
      'and a chase its own', (tester) async {
    final game = await bootCampaign(tester);
    expect(game.director!.showingTitle, isTrue);
    expect(game.musicNow, SoundBank.menu);
    // Trying one out on the menu plays it there.
    game.previewBackground = 'bg_descent';
    expect(game.musicNow, 'bg_descent');
    game.previewBackground = null;

    game.settings.setBackground('bg_solitude');
    expect(game.musicNow, SoundBank.menu, reason: 'the menu keeps its own');
    final chase = await enterChapter<ChaseChapter>(tester, game, 15);
    expect(game.musicNow, 'bg_solitude');
    // A vampire near: dread, until it passes.
    chase.reportThreat(ThreatLevel.tension);
    expect(game.musicNow, UmbraGame.dreadMusic);
    for (var i = 0; i < 240; i++) {
      game.update(1 / 60);
    }
    expect(game.musicNow, 'bg_solitude');
    chase.startChase();
    expect(game.musicNow, SoundBank.chase);
    chase.stopChase();
    for (var i = 0; i < 120; i++) { game.update(1 / 60); }
    expect(game.musicNow, 'bg_solitude');
    // A piece that is not in the game falls back to the first.
    game.settings.setBackground('nothing');
    expect(game.musicNow, GameSettings.defaultBackground);
    // Nor does the menu's own play under the game.
    game.settings.setBackground(SoundBank.menu);
    expect(game.musicNow, GameSettings.defaultBackground);
  });
}
