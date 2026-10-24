import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('a slam, a death and a checkpoint are felt, and nothing is '
      'with vibration off', (tester) async {
    final felt = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          felt.add('${call.arguments}'.split('.').last);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final game = await bootCampaign(tester);
    final chapter = await enterChapter<Chapter>(tester, game, 1);
    void frames(int n) {
      for (var i = 0; i < n; i++) {
        game.update(1 / 60);
      }
    }

    frames(30);
    felt.clear();
    chapter.cue('gate', shake: 0.8);
    frames(1);
    expect(felt, ['heavyImpact'], reason: 'a gate slamming close by');
    frames(20);
    chapter.cue('wood', shake: 0.2);
    frames(1);
    expect(felt.last, 'lightImpact', reason: 'a small knock, lightly');
    frames(20);
    chapter.cue('checkpoint');
    frames(1);
    expect(felt.last, 'selectionClick');

    game.settings.setFlag('vibration', false);
    felt.clear();
    chapter.cue('gate', shake: 0.8);
    chapter.player.die();
    frames(30);
    expect(felt, isEmpty, reason: 'vibration is off');

    game.settings.setFlag('vibration', true);
    game.resumeGameplay();
    chapter.checkpoints.respawn(chapter.player);
    frames(400);
    expect(chapter.player.isDead, isFalse);
    felt.clear();
    chapter.player.die();
    frames(2);
    expect(felt, ['heavyImpact'], reason: 'dying');
  });
}
