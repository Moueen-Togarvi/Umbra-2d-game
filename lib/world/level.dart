import 'package:flame/components.dart' show Component;

import '../config/game_config.dart';
import '../entities/ground.dart';
import '../entities/hazard.dart';
import '../entities/player.dart';
import '../input/player_intent.dart';
import 'checkpoint_service.dart';

/// Builds the level from the slabs described in [GameConfig] and owns nothing
/// else.
///
/// Level layout is its own concern, kept out of both the game class and the
/// entities. The layout itself is data — a list of slabs — so a second level
/// is a second list, not a second copy of this file.
///
/// The level, in metres, with y pointing down and the camera showing 9 m:
///
/// ```
///   0        14 16      24  27  30 32      42       50 52         64
///   |  shore  |  |  mist |   |   |  | forest |  high  |  |  descent  |
///   ####### ### ###### ### ### #### ####### ########## ###############
///          ^pit            ^pit               ^pit
/// ```
///
/// Every stretch of x between 0 and [GameConfig.levelWidth] that no slab
/// covers is a pit, and gets a spiked hazard at the bottom.
class Level extends Component {
  Level({required this._intent, required this.checkpoints});

  final PlayerIntent _intent;

  /// Exposed so the game can hand it to anything else that needs to kill or
  /// save the player later.
  final CheckpointService checkpoints;

  @override
  Future<void> onLoad() async {
    final List<Component> pieces = [];

    // --- The ground ----------------------------------------------------------
    // Every slab runs from its surface all the way to the bottom of the level,
    // so nothing bright ever shows beneath a floor.
    for (final slab in GameConfig.terrain) {
      pieces.add(
        Ground.slab(
          left: slab.left,
          right: slab.right,
          top: slab.top,
          thickness: GameConfig.levelHeight - slab.top,
        ),
      );
    }

    // --- Pits: the gaps between slabs, spiked ---------------------------------
    final sorted = [...GameConfig.terrain]
      ..sort((a, b) => a.left.compareTo(b.left));
    for (var i = 0; i + 1 < sorted.length; i++) {
      final Slab a = sorted[i];
      final Slab b = sorted[i + 1];
      if (b.left <= a.right) {
        continue; // touching or overlapping: no pit
      }
      // The pit floor sits a fixed depth below the *lower* of the two lips.
      final double lip = a.top > b.top ? a.top : b.top;
      final double floor = lip + GameConfig.pitDepth;
      pieces.add(
        Hazard.zone(
          left: a.right,
          right: b.left,
          top: floor,
          bottom: GameConfig.levelHeight,
          checkpoints: checkpoints,
        ),
      );
    }

    // --- Ledges: logs and branches to jump onto -------------------------------
    for (final ledge in GameConfig.ledges) {
      // The slab under the log's centre, for the mound it rests on.
      final double centreX = (ledge.left + ledge.right) / 2;
      final Slab? under = GameConfig.terrain
          .where((s) => s.left <= centreX && centreX <= s.right)
          .firstOrNull;
      pieces.add(
        Ground.slab(
          left: ledge.left,
          right: ledge.right,
          top: ledge.top,
          thickness: GameConfig.ledgeThickness,
          style: GroundStyle.log,
          groundBelow: under?.top,
        ),
      );
    }

    // --- Walls, so the player cannot walk out of the level --------------------
    pieces.add(
      Ground.slab(
        left: -GameConfig.wallThickness,
        right: 0,
        top: -GameConfig.levelHeight,
        thickness: GameConfig.levelHeight * 2,
        style: GroundStyle.wall,
      ),
    );
    pieces.add(
      Ground.slab(
        left: GameConfig.levelWidth,
        right: GameConfig.levelWidth + GameConfig.wallThickness,
        top: -GameConfig.levelHeight,
        thickness: GameConfig.levelHeight * 2,
        style: GroundStyle.wall,
      ),
    );

    // --- The player, last so it draws on top of the ground --------------------
    pieces.add(
      Player(intent: _intent, spawnPosition: checkpoints.activeCheckpoint),
    );

    await addAll(pieces);
  }
}
