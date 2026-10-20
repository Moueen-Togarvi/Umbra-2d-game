import 'support/route_pilot.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/mill.dart';
import 'package:umbra/character/character_interactions.dart';
import 'package:umbra/config/game_config.dart';

import 'support/campaign.dart';

void main() {
  testWidgets('chapter twelve: the race turns the wheel that winds the gate, '
      'and the flood drowns them and lifts him to the ledge', (tester) async {
    final game = await bootCampaign(tester);
    final mill = await enterChapter<MillChapter>(tester, game, 27);
    final player = mill.player;
    final intent = game.intent;
    final jumped = <String>{};
    var rode = false;
    double reached = 0;
    double cooldown = 0;
    double spun = 0;
    void jump(String what) {
      jumped.add(what);
      intent.requestJump();
    }

    for (var i = 0; i < 60 * 900 && !mill.isComplete; i++) {
      final double x = player.body.position.x;
      final double feet = player.body.position.y + GameConfig.playerHeight / 2;
      final bool grounded = player.isOnGround;
      final mode = player.interactions.mode;
      double axis = 1;
      bool down = false;
      cooldown -= 1 / 60;
      if (mill.wheel.turning.abs() > spun) spun = mill.wheel.turning.abs();
      if (!intent.isScripted) {
        // Each cord: under it, up, hang until it gives, down.
        for (final c in [mill.sluiceCord, mill.damCord]) {
          final double cx = c.anchor.x;
          if ((x - cx).abs() > 6 || feet < 6.5) continue;
          if (c == mill.damCord && !mill.gate.open) continue;
          if (mode == InteractionMode.swinging ||
              mode == InteractionMode.climbing) {
            axis = 0;
            down = c.pulled;
          } else if (!c.pulled) {
            final double off = cx - x;
            axis = off.abs() > 0.12
                ? off.sign * (off.abs() > 0.6 ? 1 : 0.35)
                : 0;
            if (axis == 0 && grounded && cooldown <= 0) {
              cooldown = 1.2;
              jump('cord$cx');
            }
          }
        }
        // The gate: wait for the wheel to wind it up.
        if (mill.sluiceCord.pulled && !mill.gate.open && x > 31 && x < 34.3) {
          axis = 0;
        }
        // At the cistern: wait for the raft to come up, then onto it.
        final raft = mill.raft.body.position;
        final double raftTop = raft.y - 0.45;
        if (mill.damCord.pulled && x > 44.7 && x < MillChapter.basinLeft) {
          axis = 0;
          if (grounded &&
              (raftTop - MillChapter.floor).abs() < 0.35 &&
              raft.x < MillChapter.basinLeft + 3.5 &&
              cooldown <= 0) {
            cooldown = 1;
            axis = 0.8;
            jump('raft');
          }
        }
        if (!grounded &&
            jumped.contains('raft') &&
            x < MillChapter.basinLeft + 3) {
          axis = 0.8;
        }
        final bool onRaft =
            grounded &&
            (feet - raftTop).abs() < 0.2 &&
            (x - raft.x).abs() < 1.6;
        if (onRaft) {
          rode = true;
          final double off = raft.x - x;
          axis = off.abs() > 0.2 ? off.sign * 0.4 : 0;
          if (raftTop < MillChapter.ledge + 0.1 &&
              raft.x > MillChapter.basinRight - 2.9 &&
              cooldown <= 0) {
            cooldown = 1;
            axis = 1;
            jump('ledge');
          }
        }
        if (mode == InteractionMode.hanging) axis = 1;
      }
      intent.setKeyboardState(axis: axis, down: down);
      driveExtension(game);
      game.update(1 / 60);
      if (player.isDead) {
        fail(
          'died at x=${x.toStringAsFixed(2)} feet=${feet.toStringAsFixed(2)} '
          'after $jumped; basin ${mill.basin.level.toStringAsFixed(2)}; raft '
          '${mill.raft.body.position}; gate ${mill.gate.lift.toStringAsFixed(2)}',
        );
      }
      if (x > reached) reached = x;
    }
    intent.setKeyboardState(axis: 0, down: false);
    expect(
      mill.isComplete,
      isTrue,
      reason:
          'stopped at x=${player.body.position.x.toStringAsFixed(2)} '
          'y=${player.body.position.y.toStringAsFixed(2)} '
          '(furthest ${reached.toStringAsFixed(1)}) after $jumped; mode '
          '${player.interactions.mode.name}; wheel spun $spun; gate '
          '${mill.gate.lift}; basin ${mill.basin.level}; raft '
          '${mill.raft.body.position}',
    );
    expect(spun, greaterThan(0.6), reason: 'the race turned the wheel');
    expect(rode, isTrue);
    expect(mill.drowned.every((v) => v.gone), isTrue);
  });
}
