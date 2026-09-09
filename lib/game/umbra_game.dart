import 'dart:ui';

import 'package:flame/input.dart' show HasKeyboardHandlerComponents;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/palette.dart';
import '../input/keyboard_input.dart';
import '../input/player_intent.dart';
import '../world/checkpoint_service.dart';
import '../world/test_room.dart';

/// The root of the game.
///
/// Its only jobs are to configure the physics world, set up the camera, and
/// wire the input layer to the level. It deliberately contains no gameplay
/// logic: the moment a game class starts knowing how jumping works, it is on
/// its way to becoming the God class that every other file has to import.
///
/// ## Why [Forge2DGame] rather than a plain FlameGame
///
/// [Forge2DGame] owns a [Forge2DWorld], which wraps a Box2D world and steps it
/// once per frame before dispatching the contact events that step produced. It
/// also swaps in a viewfinder that understands the metres-to-pixels conversion,
/// so the rest of the code can think purely in metres.
class UmbraGame extends Forge2DGame with HasKeyboardHandlerComponents {
  UmbraGame()
    : super(
        // Gravity is handed to the physics world at construction. Positive y is
        // downwards in Flame's coordinate system.
        gravity: GameConfig.gravity,

        // How large a metre is on screen. This is a *rendering* setting: change
        // it and the game looks bigger, but the simulation is bit-for-bit
        // identical. Older versions of flame_forge2d abused the camera's `zoom`
        // for this, which conflated "how big is the world" with "how far is the
        // camera zoomed in". They are separate here.
        metersToPixels: GameConfig.metersToPixels,
      );

  /// The shared intent object that input writes to and the player reads from.
  final PlayerIntent _intent = PlayerIntent();

  /// Respawn state. Created in [onLoad] so it can be replaced per level later.
  ///
  /// Deliberately `late` rather than `late final`: a hot restart re-runs
  /// [onLoad], and reassigning a `late final` throws.
  late CheckpointService checkpoints;

  @override
  Color backgroundColor() => Palette.background;

  @override
  Future<void> onLoad() async {
    // This await is mandatory and must come first.
    //
    // Forge2DGame.onLoad initialises the physics backend, and on the web that
    // means fetching and instantiating the Box2D WebAssembly module. Creating
    // any body before it finishes throws. Native builds happen to be
    // synchronous, so forgetting this line produces code that works perfectly
    // on desktop and dies on the web.
    await super.onLoad();

    // Fit the whole room on screen, expressed in metres. This is persistent:
    // resize the window and Flame recomputes the zoom to keep the room framed,
    // without touching the simulation.
    camera.viewfinder
      ..visibleGameSize = Vector2(GameConfig.roomWidth, GameConfig.roomHeight)
      ..position = Vector2(GameConfig.roomWidth / 2, GameConfig.roomHeight / 2);

    checkpoints = CheckpointService(initialCheckpoint: GameConfig.playerSpawn);

    // The keyboard listener lives on the game, not in the world: it is not a
    // thing in the room, it is a source of events. HasKeyboardHandlerComponents
    // walks the component tree and delivers key events to any KeyboardHandler.
    await add(KeyboardInput(_intent));

    // Everything physical goes into the physics world.
    await world.add(TestRoom(intent: _intent, checkpoints: checkpoints));
  }
}
