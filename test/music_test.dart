import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/audio/sound_bank.dart';
import 'package:umbra/chapters/chase.dart';
import 'package:umbra/config/game_settings.dart';
import 'package:umbra/ui/audio_settings.dart';

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

  testWidgets('the menu and play have the one picked, carrying on '
      'unbroken, and a chase its own', (tester) async {
    final game = await bootCampaign(tester);
    expect(game.director!.showingTitle, isTrue);
    expect(game.musicNow, game.settings.background);
    // Trying one out on the menu plays it there.
    game.previewBackground = 'bg_descent';
    expect(game.musicNow, 'bg_descent');
    game.previewBackground = null;

    game.settings.setBackground('bg_tomb');
    expect(game.musicNow, 'bg_tomb', reason: 'the menu plays it too');
    final chase = await enterChapter<ChaseChapter>(tester, game, 15);
    expect(game.musicNow, 'bg_tomb');
    chase.startChase();
    expect(game.musicNow, SoundBank.chase);
    chase.stopChase();
    for (var i = 0; i < 120; i++) { game.update(1 / 60); }
    expect(game.musicNow, 'bg_tomb');
    // A piece that is not in the game falls back to the first.
    game.settings.setBackground('nothing');
    expect(game.musicNow, GameSettings.defaultBackground);
  });
}
