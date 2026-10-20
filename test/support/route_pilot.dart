import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'package:umbra/entities/clock_props.dart';
import 'package:umbra/game/umbra_game.dart';

final _pilots = Expando<RoutePilot>();
void driveExtension(UmbraGame game) {
  final stage = game.stage;
  if (stage is! Chapter ||
      !stage.isLoaded ||
      !stage.isMounted ||
      stage.intent.isScripted) {
    return;
  }
  if (stage is! JourneyChapter &&
      stage.player.body.position.x < stage.coreWidth) {
    return;
  }
  game.intent.clear();
  (_pilots[game] ??= RoutePilot(game)).tick();
}

/// Uses only ordinary movement, sit and jump input, never moves bodies.
class RoutePilot {
  RoutePilot(this.game);
  final UmbraGame game;
  double cooldown = 0;
  PuzzleRoom? previous;
  bool firstCoverPassed = false, secondCoverPassed = false;
  bool wasDead = false;
  bool raftDeparting = false, raftBoarded = false;
  bool loopReturned = false;
  void tick() {
    final stage = game.stage! as Chapter;
    final p = stage.player;
    final rooms = stage is JourneyChapter ? stage.rooms : stage.extensionRooms;
    if (p.isDead && !wasDead) {
      firstCoverPassed = false;
      secondCoverPassed = false;
      raftDeparting = false;
      raftBoarded = false;
      loopReturned = false;
      cooldown = 0;
    }
    wasDead = p.isDead;
    final x = p.body.position.x;
    final room = rooms.where((r) => x < r.end).firstOrNull;
    var axis = 1.0;
    var sit = false;
    cooldown -= 1 / 60;
    void jump() {
      if (cooldown <= 0) {
        game.intent.requestJump();
        cooldown = .65;
      }
    }

    if (room != previous) {
      previous = room;
      firstCoverPassed = false;
      secondCoverPassed = false;
      raftDeparting = false;
      raftBoarded = false;
      loopReturned = false;
    }
    if (room != null) {
      final local = x - room.x;
      final feet = p.body.position.y + .65;
      final ground = p.isOnGround;
      switch (room.kind) {
        case PuzzleKind.crawl:
          sit = local > 10 && local < 23;
          if (ground && local > 26.8 && local < 30) jump();
        case PuzzleKind.coffin:
          if (local > 7 && local < 28) {
            sit = true;
            axis = .5;
          }
          if (ground && local > 28 && local < 33) jump();
        case PuzzleKind.crate:
          if (ground && local > 14 && local < 19.5) jump();
        case PuzzleKind.drain:
          if (!room.pedal!.pressed && local > 6.5 && local < 11) {
            axis = ((room.x + 8.1 - x) * 2).clamp(-1, 1);
            if (ground && (local - 8.1).abs() > .2) jump();
          }
          if (local > 10 && room.water!.level < room.floor - .2) axis = 0;
          sit = local > 11.3 && local < 25;
        case PuzzleKind.rope:
          if (ground && local > 15.3 && local < 16) {
            jump();
          }
          if (p.isOnRope && local > 18.4 && p.velocity.x > 1.5) {
            jump();
          }
        case PuzzleKind.raft:
        case PuzzleKind.floodTrap:
          if (room.kind == PuzzleKind.floodTrap) {
            if (!room.pedal!.pressed && local > 6.5 && local < 11) {
              axis = ((room.x + 8.1 - x) * 2).clamp(-1, 1);
              if (ground && (local - 8.1).abs() > .2) jump();
            }
            if (local > 11 && room.water!.level > room.floor + .3) {
              axis = 0;
              break;
            }
          }
          final raft = room.crates.first;
          final rx = raft.body.position.x;
          if (ground && local > 12.8 && local < 14) jump();
          if (local > 14 && local < 21.5) {
            final balance = rx + .4 - x;
            if (ground && feet < room.floor + .4) raftBoarded = true;
            sit = raftBoarded;
            axis = raftBoarded ? 0 : (balance * 2).clamp(-1, 1);
            if (raftDeparting || rx > room.x + 20.5 || local > 21) {
              sit = false;
              raftDeparting = true;
              axis = 1;
              if (ground) jump();
            }
          }
        case PuzzleKind.lift:
        case PuzzleKind.returnLoop:
          final returning = room.kind == PuzzleKind.returnLoop;
          final deck = room.floor - .24 + room.lift!.travel;
          final chestOn =
              room.crates.first.body.position.x <
              room.x + (returning ? 20.3 : 20);
          if (local > 13 && local < 20 && !(returning && room.pedal!.pressed)) {
            if (ground &&
                feet > room.floor - .1 &&
                local > 15.6 &&
                local < 16.3) {
              axis = .55;
              jump();
            } else if (ground && (feet - deck).abs() < .15) {
              if (chestOn) {
                axis = .6;
              } else if (room.lift!.travel > -3) {
                axis = ((room.x + 18.4 - x) * 2).clamp(-.5, .5);
              }
            } else if (ground && feet < deck - .5 && chestOn) {
              axis = -.6;
            }
          }
          if (returning) {
            if (room.pedal!.pressed) {
              if (local < 17 && feet > room.floor - .3) loopReturned = true;
              if (!loopReturned) {
                axis = -1;
                if (ground &&
                    ((local > 17 && local < 18.1) ||
                        (local > 26.5 && local < 29.5))) {
                  jump();
                }
              } else {
                sit = local > 19 && local < 36.4;
                if (ground && local > 36.5 && local < 40) jump();
              }
            } else if (local > 26.4 && feet < room.floor - 2) {
              axis = ((room.x + 27.8 - x) * 2).clamp(-1, 1);
              if (ground) jump();
            }
          }
        case PuzzleKind.seesaw:
          if (ground && local > 12.8 && local < 14.3) jump();
          if (ground && local > 17.8 && local < 19) jump();
        case PuzzleKind.weight:
          sit = local > 29 && local < 37;
          if (ground &&
              local > 13.5 &&
              local < 17 &&
              room.crates.first.body.position.x > room.x + 14.8) {
            jump();
          }
        case PuzzleKind.patrol:
          final v = room.hunter!.vampire;
          if (!firstCoverPassed && local >= 10) sit = true;
          if (!firstCoverPassed && local >= 11.3 && local < 15) {
            axis = 0;
            sit = true;
            if (v.facing > 0 && v.x > x + 8) firstCoverPassed = true;
          }
          if (firstCoverPassed &&
              !secondCoverPassed &&
              local >= 18.5 &&
              local < 21) {
            axis = 0;
            sit = true;
            if (v.facing < 0 && v.x < x - 2.5) secondCoverPassed = true;
          }
        case PuzzleKind.lantern:
          if (ground && local > 35.2 && local < 39.5) jump();
        case PuzzleKind.pendulum:
          sit = local > 26 && local < 34;
          final pendulum = stage.children.whereType<Pendulum>().firstWhere(
            (q) => (q.pivot.x - room.x - 17.5).abs() < .1,
          );
          final plate = pendulum.plateTop;
          final pv = pendulum.body.linearVelocity.x;
          final on =
              ground &&
              (feet - plate.y).abs() < .18 &&
              (x - plate.x).abs() < 1.1;
          if (local > 11 && local < 13.5 && ground) {
            final off = room.x + 13.38 - x;
            axis = (off * 2).clamp(-1, 1);
            if (off.abs() < .15 && plate.x < room.x + 15.2 && pv < -1) {
              axis = .7;
              jump();
            }
          }
          if (!ground && local < 15.2) axis = .7;
          if (on) {
            axis = 0;
            if (plate.x > room.x + 20.3 && pv.abs() < 1.2) {
              axis = 1;
              jump();
            }
          }
        case PuzzleKind.cages:
          if (ground && local > 13.1 && local < 14) jump();
          if (ground && local >= 14 && local < 20) {
            final under = room.cages
                .where((c) => (c.body.position.x - x).abs() < 1.15)
                .firstOrNull;
            if (under != null && x > under.body.position.x + .45) jump();
          }
        case PuzzleKind.oil:
          if (!room.pedal!.pressed && local > 6.5 && local < 11) {
            axis = ((room.x + 8.1 - x) * 2).clamp(-1, 1);
            if (ground && (local - 8.1).abs() > .2) jump();
          }
          if (local > 11 &&
              (!room.solved ||
                  room.lamp!.fire == null ||
                  room.lamp!.fire!.burning)) {
            axis = 0;
          }
        case PuzzleKind.hammer:
          if (ground && local > 15 && local < 24) jump();
      }
      if (room.pedal?.pressed == true && ground && local > 6.8 && local < 9.5) {
        jump();
      }
      if (p.interactions.mode.name == 'hanging') {
        axis =
            room.kind == PuzzleKind.returnLoop &&
                room.pedal!.pressed &&
                !loopReturned
            ? -1
            : 1;
        sit = false;
      }
    }
    game.intent.setKeyboardState(axis: axis, sit: sit);
  }
}
