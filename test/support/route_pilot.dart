import 'dart:math' as math;

import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/chapters/journey_chapter.dart';
import 'package:umbra/chapters/puzzle_route.dart';
import 'package:flame_forge2d/flame_forge2d.dart' show BodyType;
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
  bool rockfallGo = false;
  bool crateFreed = false, crateBehind = false, leapt = false;
  int heavyStep = 0;
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
      rockfallGo = false;
      crateFreed = false;
      crateBehind = false;
      leapt = false;
      heavyStep = 0;
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
      rockfallGo = false;
      crateFreed = false;
      crateBehind = false;
      leapt = false;
      heavyStep = 0;
    }
    var interact = false, up = false, down = false;
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
        case PuzzleKind.burningRope:
          if (ground && local > 15.3 && local < 16) {
            jump();
          }
          if (p.isOnRope && local > 18.4 && p.velocity.x > 1.5) {
            jump();
          }
        case PuzzleKind.raft:
        case PuzzleKind.floodTrap:
        case PuzzleKind.logFloat:
        case PuzzleKind.sinkingRaft:
          // The log on the bank goes in first, pushed.
          if (room.kind == PuzzleKind.logFloat &&
              room.crates.first.body.position.x < room.x + 15 &&
              local < 13.7) {
            break;
          }
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
          // Off only once no part of it rests on the deck's edge
          // (x + 19.8): its weight there holds the lift down.
          final chestOn = room.crates.first.body.position.x < room.x + 20.35;
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
        case PuzzleKind.traps:
          // The crate goes first, springing each trap, to the wall; then
          // up it, onto the ledge.
          final crate = room.crates.first.body.position.x - room.x;
          if (crate > 19.3 && ground && local > 17.4 && local < 20.5) jump();
        case PuzzleKind.plateGate:
          final a = room.crates[0].body.position.x - room.x;
          final b = room.crates[1].body.position.x - room.x;
          if (a < 10.85) {
            // Onto the plate with the first.
            if (local > a) axis = 0;
          } else if (local < a + .6) {
            // Over it, leaving it there.
            if (ground && a - local < 1.7) jump();
          }
          if (local > a + .6 && b > 23.6 && ground && local > 21.8) jump();
        case PuzzleKind.bridge:
          // Across at a run: it gives way behind.
          axis = 1;
        case PuzzleKind.rockfall:
          final stones = room.stones!.rocks.where((r) => r.isEnabled);
          if (ground && local > 2.2 && local < 2.7) jump();
          // Over each stone as it comes.
          for (final r in stones) {
            final dx = r.position.x - x;
            if (ground &&
                dx > .5 &&
                dx < 2.2 &&
                r.linearVelocity.x < -1.5 &&
                (r.position.y - feet).abs() < 1.2) {
              jump();
            }
          }
          // Below the rise, one goes by; then up, before the next.
          if (local > 21 && local < 24 && !rockfallGo) {
            axis = 0;
            if (stones.any(
              (r) => r.position.x < x - .8 && r.linearVelocity.x < -1,
            )) {
              rockfallGo = true;
            }
          }

        case PuzzleKind.chase:
          if (ground && local > 11.5 && local < 12.3) jump();
          if (ground && local > 17.4 && local < 18.2) jump();
        case PuzzleKind.bats:
          // Short of where they sweep low, wait for them to go by; then on.
          final double since = 9 - room.batClock;
          if (local > 8.4 && local < 10 && !(since > 3.4 && since < 5.4)) {
            axis = 0;
          }
        case PuzzleKind.spikes:
          if (ground && local > 12.4 && local < 12.9) jump();
          if (ground && local > 21.4 && local < 21.62) jump();
        case PuzzleKind.barrel:
          // Pushed off the top, it rolls to the plate; then over it and
          // the sill behind it.
          if (ground && local > 21.6 && local < 22.1) jump();
        case PuzzleKind.zipline:
          if (ground && feet > room.floor - .3 && local > 7 && local < 7.6) {
            jump();
          }
          if (ground && feet < room.floor - 1 && local > 10.2 && local < 10.9) {
            jump();
          }
          if (p.isOnRope) {
            axis = 0;
            if (room.zip!.handle.arrived && p.velocity.x > -.3) jump();
          }
        case PuzzleKind.logBridge:
        case PuzzleKind.bookcase:
          // Once it is down across the gap, up onto it.
          if (room.trunk!.body.angle.abs() > 1.2 &&
              ground &&
              local > 14.6 &&
              local < 15.7) {
            jump();
          }
        case PuzzleKind.wolves:
          if (ground && local > 7 && local < 7.6) jump();
          if (ground && local > 14 && local < 14.6) jump();
          if (ground &&
              feet < room.floor - .9 &&
              local > 15.6 &&
              local < 16.6) {
            jump();
          }
        case PuzzleKind.crows:
          sit = local > 7.4 && local < 19.6;
        case PuzzleKind.pullCrate:
          final c = room.crates.first.body.position.x - room.x;
          if (ground && feet > room.floor - .3 && local > 3.4 && local < 4) {
            jump();
          }
          final pulling = p.interactions.mode.name == 'pulling';
          if (!crateFreed && c > 12.3) crateFreed = true;
          if (!crateFreed && local > 8.4 && feet > room.floor - .3) {
            // Round on its far side: hold it and walk back.
            if (local > c + 1.5) {
              axis = -1;
            } else if (local < c + .55) {
              axis = 1;
            } else {
              interact = true;
              axis = pulling ? 1 : -.3;
            }
          } else if (crateFreed && !crateBehind) {
            // Back over it, to its near side.
            axis = -1;
            if (ground && local > c && local - c < 1.7) jump();
            if (ground && local < c - .8) crateBehind = true;
          } else if (crateBehind) {
            // Hard against the wall: up onto it, then up the wall.
            if (ground && c > 20.4 && local > 18.6 && local < 20.8) jump();
          }
        case PuzzleKind.bog:
          if (ground && local > 7.4 && local < 27.2) jump();
        case PuzzleKind.ropeClimb:
          final line = room.ropes.first;
          if (ground &&
              feet > room.floor - .3 &&
              local > 15.3 &&
              local < 15.9) {
            jump();
          }
          if (p.isOnRope) {
            if (line.holdLength > 1.7) {
              up = true;
              axis = 0;
            } else if (p.velocity.x > 1 && x > line.anchor.x + .3) {
              jump();
            }
          }
        case PuzzleKind.cageLift:
          final lift = room.cage!;
          if (!lift.rising) {
            if (p.isOnRope) {
              axis = 0;
            } else if (local > 12) {
              axis = ((room.x + 15.5 - x) * 2).clamp(-1, 1);
              if (ground && (local - 15.5).abs() < .25) jump();
            }
          } else {
            // Let go of the cord: the cage takes him up.
            if (p.isOnRope) down = true;
            if (!lift.isUp) axis = 0;
          }
        case PuzzleKind.drawbridge:
          if (!room.cord!.pulled) {
            if (local > 12 && local < 14.6) {
              axis = ((room.x + 13.6 - x) * 2).clamp(-1, 1);
              if (ground && (local - 13.6).abs() < .25) jump();
            }
          } else {
            if (p.isOnRope) down = true;
            final bridge = room.drawbridge!;
            final lying = bridge.down || bridge.body.angle.abs() < .2;
            if (!lying && local > 12) axis = 0;
          }
        case PuzzleKind.levers:
          if (room.solved && p.isOnRope) jump();
          if (!room.solved) {
            final next = PuzzleRoom.leverOrder[math.min(room.pulls.length, 2)];
            final cord = room.cords[next];
            final double target = room.x + 8 + next * 2.6;
            if (p.isOnRope) {
              axis = 0;
              // Let go (a hop off it: down only slides to its end).
              if (cord.pulled || p.interactions.attachedRope != cord) {
                jump();
              }
            } else if (local > 6) {
              axis = ((target - x) * 2).clamp(-1, 1);
              if (ground && (target - x).abs() < .2 && !cord.pulled) jump();
            }
          }
        case PuzzleKind.twoRopes:
          if (ground && local > 12.45 && local < 12.95) jump();
          final held = p.interactions.attachedRope;
          final first = held == room.ropes.first;
          if (held != null &&
              p.velocity.x > (first ? 1.2 : 1.0) &&
              x > held.anchor.x + (first ? .9 : 1.15)) {
            jump();
          }
        case PuzzleKind.stalactites:
          if (ground && local > 16.5 && local < 16.95) jump();
        case PuzzleKind.sluice:
          if (!room.pedal!.pressed && local > 6.5 && local < 11) {
            axis = ((room.x + 8.1 - x) * 2).clamp(-1, 1);
            if (ground && (local - 8.1).abs() > .2) jump();
          }
          final second = room.pedal2!;
          if (!second.pressed) {
            if (local > 9.6 &&
                local < 12.6 &&
                room.water!.level < room.floor - .2) {
              axis = local > 11.6 ? -1 : 0;
            }
            if (local > 21 && local < 24.5) {
              axis = ((room.x + 22.5 - x) * 2).clamp(-1, 1);
              if (ground && (local - 22.5).abs() > .2) jump();
            }
          } else if (ground && local > 21.4 && local < 24) {
            jump();
          }
        case PuzzleKind.floatCrate:
          final c = room.crates.first.body.position;
          if (ground && feet > room.floor - .3 && local > 3.3 && local < 3.9) {
            jump();
          }
          if (ground &&
              feet < room.floor - .8 &&
              feet > room.floor - 1.3 &&
              local > 5.2 &&
              local < 5.8) {
            jump();
          }
          final onLedge = feet < room.floor - 2;
          if (!room.pedal!.pressed && onLedge && local > 6.5 && local < 10.5) {
            axis = ((room.x + 8.1 - x) * 2).clamp(-1, 1);
            if (ground && (local - 8.1).abs() > .2) jump();
          }
          if (room.pedal!.pressed && onLedge && local > 9.3 && local < 11) {
            // Back from the edge until the crate is up; then a run and onto it.
            if (c.y - .6 > room.floor - 2.7) {
              axis = ((room.x + 9.7 - x) * 2).clamp(-1, 1);
            } else if (ground && local > 10.45) {
              leapt = true;
              jump();
            }
          }
          if (leapt && !ground && local > 10.2 && local < 14.5) axis = 1;
          if (ground &&
              local > 12.3 &&
              local < 13.6 &&
              feet < room.floor - 2.8) {
            jump();
          }
        case PuzzleKind.crusher:
        case PuzzleKind.coffinHands:
        case PuzzleKind.fireJets:
          // Short of each, until it has struck and gone back.
          final row = room.timed!;
          for (var i = 0; i < row.xs.length; i++) {
            final ahead = row.xs[i] - x;
            if (ahead > .85 && ahead < 1.6 && row.clearFor(i) < 1.0) {
              axis = 0;
              break;
            }
          }
        case PuzzleKind.twoCrates:
          // The step is the crate still loose (the other lies in the pit):
          // up once it is against the wall.
          final step = room.crates
              .where((c) => c.body.type == BodyType.dynamic)
              .map((c) => c.body.position.x)
              .fold(0.0, math.max);
          if (ground && step > room.x + 22.2 && local > 20.5 && local < 22.8) {
            jump();
          }
        case PuzzleKind.sleeper:
          sit = local > 13.6 && local < 26.6;
        case PuzzleKind.heavyLight:
          final heavy = room.crates[0].body.position.x - room.x;
          final light = room.crates[1].body.position.x - room.x;
          final pulling = p.interactions.mode.name == 'pulling';
          if (heavyStep == 0 && light > 16.2) heavyStep = 1;
          if (heavyStep == 1) {
            // Back onto the plate with the heavy one.
            if (heavy < 12.95) {
              heavyStep = 2;
            } else {
              interact = true;
              axis = pulling ? -1 : .3;
            }
          }
          if (heavyStep == 2) {
            // Back a step for a run at it, then over it, leaving it there.
            axis = -1;
            if (heavy - local > 1.5) heavyStep = 3;
          }
          if (heavyStep == 3) {
            if (ground &&
                feet > room.floor - .3 &&
                heavy - local > .9 &&
                heavy - local < 1.15) {
              jump();
            }
            if (local > heavy + .8) heavyStep = 4;
          }
          if (heavyStep == 4 && ground) {
            // Up the crate's top onto the wall; or, dropped in the gap
            // between them, back up onto the crate.
            if (feet < room.floor - .9 && local > 21.2) jump();
            if (feet > room.floor - .3 && local > light + .4 && local < 23) {
              axis = -.4;
              jump();
            }
          }
          if (heavyStep == 4 &&
              ground &&
              light > 22.2 &&
              local > 20.6 &&
              local < 22.6) {
            jump();
          }
        case PuzzleKind.boulder:
          // Behind it until it has broken through and come to rest.
          if (!room.barrel!.settled && local > 21 && local < 24) axis = 0;
          // Over the hollow it lies in, rather than across its top.
          if (ground && local > 27.62 && local < 27.92) jump();
          if (ground && local > 31.6 && local < 32.2) jump();
        case PuzzleKind.barrelRun:
          for (final c in room.casks) {
            if (!c.isReady || c.body.type != BodyType.dynamic) continue;
            final dx = c.body.position.x - x;
            final closing =
                -c.body.linearVelocity.x + math.max(0, p.velocity.x);
            // Up as it is about to reach him, however fast it comes.
            if (ground &&
                dx > .4 &&
                closing > .5 &&
                dx / closing < .42 &&
                c.body.linearVelocity.x < -1 &&
                (c.body.position.y - feet).abs() < 1.2) {
              jump();
            }
          }
        case PuzzleKind.floodRise:
          if (ground &&
              ((local > 8.2 && local < 8.8) ||
                  (local > 11.2 && local < 11.8) ||
                  (local > 14.2 && local < 14.8) ||
                  (local > 17.2 && local < 17.8))) {
            jump();
          }
        case PuzzleKind.fallingStairs:
          // Up without stopping; a hop onto each step if it holds him.
          if (ground && local > 9.3 && local < 22.4) jump();
        case PuzzleKind.timedDoor:
          if (ground && local > 14.1 && local < 14.5) jump();
        case PuzzleKind.bell:
          final cord = room.cord!;
          final v = room.chaser!.vampire;
          if (!cord.pulled) {
            if (p.isOnRope) {
              axis = 0;
            } else if (local > 2) {
              axis = ((room.x + 5 - x) * 2).clamp(-1, 1);
              if (ground && (local - 5).abs() < .2) jump();
            }
          } else if (p.isOnRope) {
            jump();
          } else if (v.x > room.x + 6.5 && local < 10) {
            // In the cover, low, until he has gone by to the bell.
            axis = ((room.x + 8.3 - x) * 2).clamp(-1, 1);
            sit = (local - 8.3).abs() < .6;
          }
        case PuzzleKind.moonWindow:
        case PuzzleKind.chandelier:
          final cord = room.cord!;
          final double at = room.kind == PuzzleKind.moonWindow ? 12 : 14;
          if (!cord.pulled) {
            if (p.isOnRope) {
              axis = 0;
            } else if (local > at - 3) {
              axis = ((room.x + at - x) * 2).clamp(-1, 1);
              if (ground && (local - at).abs() < .2) jump();
            }
          } else {
            if (p.isOnRope) jump();
            if (!room.hunter!.burning && local > at - 3 && local < 19) axis = 0;
          }
        case PuzzleKind.watchEye:
          final watcher = room.eye!;
          if (local > 5.5 &&
              local < 29.5 &&
              (watcher.watching || watcher.shutFor < .45)) {
            axis = 0;
          }
        case PuzzleKind.bellGate:
          final cord = room.cord!;
          if (!cord.pulled) {
            if (p.isOnRope) {
              axis = 0;
            } else if (local > 7) {
              axis = ((room.x + 10 - x) * 2).clamp(-1, 1);
              if (ground && (local - 10).abs() < .2) jump();
            }
          } else {
            if (p.isOnRope) jump();
            if (room.door!.shut && !room.solved && local < 17) axis = 0;
          }
        case PuzzleKind.tripwire:
          if (ground && local > 9.9 && local < 10.35) jump();
          sit = local > 16 && local < 23.2;
        case PuzzleKind.twoPlates:
          final a = room.crates.first.body.position.x - room.x;
          if (a < 10.85) {
            if (local > a) axis = 0;
          } else if (local < a + .6) {
            if (ground && a - local < 1.7) jump();
          }
        case PuzzleKind.leapRope:
          if (ground && feet > room.floor - .3 && local > 5.2 && local < 5.8) {
            jump();
          }
          if (ground &&
              feet < room.floor - .8 &&
              feet > room.floor - 1.3 &&
              local > 7.2 &&
              local < 7.8) {
            jump();
          }
          if (ground &&
              feet < room.floor - 1.8 &&
              local > 12.3 &&
              local < 12.9) {
            jump();
          }
          final held = p.interactions.attachedRope;
          if (held != null && p.velocity.x > 1.0 && x > held.anchor.x + .75) {
            jump();
          }
        case PuzzleKind.fireChase:
        case PuzzleKind.collapse:
          if (ground &&
              ((local > 11.1 && local < 11.5) ||
                  (local > 19.1 && local < 19.5))) {
            jump();
          }
        case PuzzleKind.boulderChase:
          if (ground &&
              ((local > 12.1 && local < 12.5) ||
                  (local > 21.1 && local < 21.5))) {
            jump();
          }
        case PuzzleKind.movingPlatform:
          final deck = room.ferry!.body.position.x - room.x;
          final onDeck =
              ground &&
              feet < room.floor - .1 &&
              (x - room.ferry!.body.position.x).abs() < 1.2;
          if (local > 11 && local < 13 && !onDeck) {
            // At the edge until it is here.
            axis = deck < 14.6 ? 1 : ((room.x + 12.5 - x) * 2).clamp(-1, 1);
          }
          if (onDeck) {
            axis = deck > 20.5
                ? 1
                : ((room.ferry!.body.position.x - x) * 2).clamp(-1, 1);
          }
        default:
      }
      // A trap ahead, open: over it.
      for (final trap in room.traps) {
        final ahead = trap.x - x;
        if (!trap.sprung && ground && ahead > .7 && ahead < 1.25) jump();
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
    game.intent.setKeyboardState(
      axis: axis,
      sit: sit,
      interact: interact,
      up: up,
      down: down,
    );
  }
}
