import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'package:umbra/world/stage.dart';
import 'support/campaign.dart';

void main() {
  testWidgets(
    'lost player is investigated at last sighting before patrol resumes',
    (tester) async {
      final game = await bootCampaign(tester);
      final stage = await enterChapter<JourneyChapter>(tester, game, 3);
      final room = stage.rooms.firstWhere((r) => r.kind == PuzzleKind.patrol);
      final hunter = room.hunter!;
      hunter.reset(room.x + 8);
      hunter.vampire.facing = 1;
      stage.player.teleportTo(Vector2(room.x + 14, 6.35));
      hunter.update(1 / 60);
      expect(hunter.awake, isTrue);
      // Move out of sight without advancing the world. Search must remember the
      // old position instead of tracking the unseen player's new coordinates.
      stage.player.teleportTo(Vector2(room.x + 32, 6.35));
      for (var i = 0; i < 29; i++) {
        hunter.update(.1);
        expect(hunter.vampire.x, lessThanOrEqualTo(room.x + 14.01));
      }
      expect(hunter.awake, isTrue);
      expect(hunter.caught, isFalse);
      for (var i = 0; i < 5; i++) {
        hunter.update(.1);
      }
      expect(hunter.awake, isTrue);
      expect(hunter.vampire.x, closeTo(room.x + 14, .01));
      for (var i = 0; i < 31; i++) {
        hunter.update(.1);
      }
      expect(hunter.awake, isFalse);
      expect(hunter.vampire.x, greaterThan(room.x + 14));
      expect(hunter.vampire.facing, 1);
    },
  );

  testWidgets(
    'cover needs crouch, open crouching stays exposed, floors block sight',
    (tester) async {
      final game = await bootCampaign(tester);
      final stage = await enterChapter<JourneyChapter>(tester, game, 3);
      final room = stage.rooms.firstWhere((r) => r.kind == PuzzleKind.patrol);
      final cover = room.x + 12;
      stage.player.teleportTo(Vector2(cover, 6.35));
      game.intent.setKeyboardState(sit: true);
      for (var i = 0; i < 40; i++) {
        game.update(1 / 60);
      }
      expect(stage.playerHidden, isTrue);
      expect(stage.seesPlayer(Vector2(cover + 4, 6.35), facing: -1), isFalse);
      game.intent.setKeyboardState(sit: false);
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
      }
      expect(stage.playerHidden, isFalse);
      expect(stage.seesPlayer(Vector2(cover + 4, 6.35), facing: -1), isTrue);
      stage.player.teleportTo(Vector2(room.x + 8, 6.35));
      game.intent.setKeyboardState(sit: true);
      for (var i = 0; i < 20; i++) {
        game.update(1 / 60);
      }
      expect(stage.playerHidden, isFalse);
      expect(stage.seesPlayer(Vector2(room.x + 8, 2), facing: 1), isFalse);
      stage.reportThreat(ThreatLevel.chase);
      expect(stage.threat, ThreatLevel.chase);
      stage.reportThreat(ThreatLevel.tension);
      expect(stage.threat, ThreatLevel.chase);
      stage.update(1.6);
      expect(stage.threat, ThreatLevel.calm);
      stage.reportThreat(ThreatLevel.tension);
      expect(stage.threat, ThreatLevel.tension);
      stage.update(3.1);
      expect(stage.threat, ThreatLevel.calm);
    },
  );
}
