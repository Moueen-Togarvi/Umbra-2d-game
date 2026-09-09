import 'package:flame/components.dart' show Component;

import '../config/game_config.dart';
import '../entities/ground.dart';
import '../entities/hazard.dart';
import '../entities/player.dart';
import '../input/player_intent.dart';
import 'checkpoint_service.dart';

/// Builds the Step 1 test room and owns nothing else.
///
/// Level layout is its own concern, kept out of both the game class and the
/// entities. When there is more than one room, this becomes one of several
/// files that look like it, and nothing else has to change.
///
/// The room, in metres, with y pointing down:
///
/// ```
///   0                5     7                    12
///   +----------------------------------------------+  0
///   |                                              |
///   |                              [ platform ]    |  4.6
///   |                                              |
///   |  P                                           |
///   |################|     |######################|  6.0  <- floor
///   |################| ### |######################|
///   +----------------------------------------------+  7.0
///                      ^ hazard in the pit
/// ```
class TestRoom extends Component {
  TestRoom({required this._intent, required this.checkpoints});

  final PlayerIntent _intent;

  /// Exposed so the game can hand it to anything else that needs to kill or
  /// save the player later.
  final CheckpointService checkpoints;

  @override
  Future<void> onLoad() async {
    await addAll([
      // --- Floor, split by a pit the player has to jump ------------------------
      Ground.slab(
        left: 0,
        right: GameConfig.gapStartX,
        top: GameConfig.floorSurfaceY,
        thickness: GameConfig.floorThickness,
      ),
      Ground.slab(
        left: GameConfig.gapEndX,
        right: GameConfig.roomWidth,
        top: GameConfig.floorSurfaceY,
        thickness: GameConfig.floorThickness,
      ),

      // --- A raised platform, so there is something to jump *onto* -------------
      Ground.slab(
        left: GameConfig.platformStartX,
        right: GameConfig.platformEndX,
        top: GameConfig.platformSurfaceY,
        thickness: GameConfig.platformThickness,
      ),

      // --- Walls, so the player cannot walk out of the room --------------------
      Ground.slab(
        left: -GameConfig.wallThickness,
        right: 0,
        top: 0,
        thickness: GameConfig.roomHeight,
      ),
      Ground.slab(
        left: GameConfig.roomWidth,
        right: GameConfig.roomWidth + GameConfig.wallThickness,
        top: 0,
        thickness: GameConfig.roomHeight,
      ),

      // --- The hazard, filling the bottom of the pit ---------------------------
      Hazard.zone(
        left: GameConfig.gapStartX,
        right: GameConfig.gapEndX,
        top: GameConfig.floorSurfaceY + GameConfig.floorThickness / 2,
        bottom: GameConfig.roomHeight,
        checkpoints: checkpoints,
      ),

      // --- The player ----------------------------------------------------------
      Player(intent: _intent, spawnPosition: checkpoints.activeCheckpoint),
    ]);
  }
}
