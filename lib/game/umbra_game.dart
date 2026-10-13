import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/flame.dart';
import 'package:flame/input.dart' show HasKeyboardHandlerComponents;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../audio/ambient_audio.dart';
import '../config/palette.dart';
import '../entities/player.dart';
import '../input/keyboard_input.dart';
import '../input/player_intent.dart';
import '../input/touch_controls.dart';
import '../render/debug_hud.dart';
import '../render/fog_backdrop.dart';
import '../render/foreground_overlay.dart';
import '../world/checkpoint_service.dart';
import '../world/death_sequence.dart';
import '../world/level.dart';

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
  /// [debugTools] adds the on-screen development buttons; it defaults to
  /// on only in `UMBRA_DEBUG` builds.
  UmbraGame({this.debugTools = DebugHud.enabled})
    : super(
        // Gravity is handed to the physics world at construction. Positive y is
        // downwards in Flame's coordinate system.
        gravity: GameConfig.gravity,
        world: _ProfiledWorld(),

        // How large a metre is on screen. This is a *rendering* setting: change
        // it and the game looks bigger, but the simulation is bit-for-bit
        // identical. Older versions of flame_forge2d abused the camera's `zoom`
        // for this, which conflated "how big is the world" with "how far is the
        // camera zoomed in". They are separate here.
        metersToPixels: GameConfig.metersToPixels,
      );

  final bool debugTools;

  /// The shared intent object that input writes to and the player reads from.
  final PlayerIntent _intent = PlayerIntent();
  final AmbientAudio _audio = AmbientAudio();

  /// Owns the held-state of the on-screen walk buttons. Held as a field because
  /// the button callbacks close over it and it has to outlive [onLoad].
  late final TouchControls _touchControls = TouchControls(
    _intent,
    debugVisible: () => _debugVisible,
    debugTools: debugTools,
  );

  /// Plays out a death: the limp body, the fade to black, the respawn.
  late DeathSequence deathSequence;

  /// Respawn state. Created in [onLoad] so it can be replaced per level later.
  ///
  /// Deliberately `late` rather than `late final`: a hot restart re-runs
  /// [onLoad], and reassigning a `late final` throws.
  late CheckpointService checkpoints;

  /// The player, once the level has built it. The camera follows this.
  Player? _player;

  /// Where the camera is heading. Kept separate from the camera's actual
  /// position so it can ease towards it.
  final Vector2 _cameraTarget = Vector2.zero();
  double _cameraVelocityX = 0;
  double _lookAhead = 0;

  static const double _simulationStep = 1 / 120;
  double _simulationAccumulator = 0;
  bool _debugVisible = DebugHud.enabled;
  double _fps = 0, _frameElapsed = 0;
  int _displayFrames = 0;
  double get framesPerSecond => _fps;
  double get physicsMilliseconds => (world as _ProfiledWorld).stepMilliseconds;
  bool get debugVisible => _debugVisible;

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

    // Every piece of baked art, up front. The backdrop and the ground pull
    // them from the cache by name; loading here means no component has to
    // wait on the network mid-frame.
    //
    // If the assets are missing — which is the case in a bare test binding —
    // the scenery simply does not draw. The physics does not depend on it.
    await _loadArt();
    await _audio.start();

    // Frame a 16 x 9 m window on the world, in metres. Flame fits it to the
    // screen and keeps it fitted through resizes; a wider phone sees more of
    // the level to the sides rather than a stretched picture.
    camera.viewfinder.visibleGameSize = Vector2(
      GameConfig.cameraVisibleWidth,
      GameConfig.cameraVisibleHeight,
    );

    checkpoints = CheckpointService(initialCheckpoint: GameConfig.playerSpawn);
    deathSequence = DeathSequence(checkpoints: checkpoints);

    // Start the camera on the spawn point so the first frame is not a pan.
    _cameraTarget.setFrom(
      _clampCamera(_idealCameraFor(GameConfig.playerSpawn, 0)),
    );
    camera.viewfinder.position = _cameraTarget.clone();

    // The fog and forest behind the world; out-of-focus shapes and the lens
    // in front of it; and the black the picture fades to when he dies.
    await camera.backdrop.add(FogBackdrop(camera: camera));
    await camera.viewport.addAll([
      ForegroundFog(camera: camera),
      ForegroundOverlay(camera: camera),
      ScreenFade(camera: camera, blackness: () => deathSequence.blackness),
    ]);

    // The keyboard listener lives on the game, not in the world: it is not a
    // thing in the room, it is a source of events. HasKeyboardHandlerComponents
    // walks the component tree and delivers key events to any KeyboardHandler.
    //
    // Kept even though Umbra ships on Android, where there is no keyboard: it
    // costs nothing at runtime, it is what the test suite drives the player
    // with, and it means the game is still playable on a desktop while
    // developing.
    await add(KeyboardInput(_intent));

    // Touch controls go in the camera's *viewport*, not in the world. The
    // viewport is screen space, so the buttons keep a constant thumb-sized
    // footprint in pixels and never scale or pan with the camera. They must be
    // added directly to it, because Flame positions them by a margin measured
    // against their immediate parent's size.
    await camera.viewport.addAll(_touchControls.buildButtons());

    // Everything physical goes into the physics world.
    final level = Level(intent: _intent, checkpoints: checkpoints);
    await world.add(level);
    _player = level.player;

    _player!.debugEnabled = _debugVisible;
    await world.add(
      PhysicsDebugOverlay(world: world, isVisible: () => _debugVisible),
    );
    await camera.viewport.add(
      DebugHud(
        camera: camera,
        player: _player!,
        isVisible: () => _debugVisible,
        framesPerSecond: () => _fps,
        physicsMilliseconds: () => physicsMilliseconds,
      ),
    );
  }

  /// The only bitmap the game draws: film grain. Everything else is
  /// procedural. If it is missing the grain is simply left out.
  Future<void> _loadArt() async {
    try {
      await Flame.images.load('grain.png');
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // Camera
  // ---------------------------------------------------------------------------
  //
  // A slow, weighted follow: the camera aims a little above the player and a
  // little ahead of where they are walking, and eases towards that point
  // rather than locking onto it. Clamped to the level so the edges never show.

  @override
  void update(double dt) {
    // Keep contacts, acceleration and jump timing consistent on different
    // displays. Discard long stalls instead of simulating a resume in one step.
    final double frameDt = dt.clamp(0.0, 0.10);
    if (dt > 0) {
      _frameElapsed += dt;
      _displayFrames++;
      if (_frameElapsed >= 0.5) {
        _fps = _displayFrames / _frameElapsed;
        _frameElapsed = 0;
        _displayFrames = 0;
      }
    }
    final Player? currentPlayer = _player;
    if (currentPlayer != null && currentPlayer.isMounted) {
      if (_intent.consumeAudioToggleRequest()) _audio.toggle();
      if (_intent.consumeDebugToggleRequest()) {
        _debugVisible = !_debugVisible;
        currentPlayer.debugEnabled = _debugVisible;
      }
      if (_intent.consumeResetRequest()) {
        _touchControls.clear();
        _intent.clear();
        deathSequence.cancel();
        checkpoints.respawn(currentPlayer);
        _simulationAccumulator = 0;
      }
    }
    _simulationAccumulator += frameDt;
    while (_simulationAccumulator + 1e-10 >= _simulationStep) {
      super.update(_simulationStep);
      _simulationAccumulator = math.max(
        0,
        _simulationAccumulator - _simulationStep,
      );
    }
    final Player? player = _player;
    if (player == null || !player.isMounted) {
      return;
    }
    deathSequence.update(frameDt, player);

    // Lead the way he is running, easing the lead itself so a turn swings
    // the view round instead of jerking it.
    final double running =
        (player.velocity.x.abs() / GameConfig.moveSpeedMetersPerSecond).clamp(
          0.0,
          1.0,
        );
    final double lead = player.isDead
        ? 0
        : player.facing * running * GameConfig.cameraLookAhead;
    final double maxLeadChange = 3.0 * frameDt;
    _lookAhead += (lead - _lookAhead).clamp(-maxLeadChange, maxLeadChange);

    final Vector2 ideal = _idealCameraFor(player.cameraPosition, _lookAhead);
    final current = camera.viewfinder.position;
    // Ignore small vertical landing corrections and idle motion.
    if ((ideal.y - current.y).abs() < 0.35) ideal.y = current.y;
    _cameraTarget.setFrom(_clampCamera(ideal));

    // Horizontal: a critically damped spring, which starts and stops
    // smoothly. Vertical: an exponential ease, a fixed fraction of the
    // remaining distance per second.
    final double nextX = _smoothDamp(
      current.x,
      _cameraTarget.x,
      GameConfig.cameraHorizontalSmoothSeconds,
      frameDt,
    );
    final double t = 1 - math.exp(-GameConfig.cameraFollowSpeed * frameDt);
    camera.viewfinder.position = Vector2(
      nextX,
      current.y + (_cameraTarget.y - current.y) * t,
    );
  }

  /// Unity-style SmoothDamp: moves [current] towards [target] like a
  /// critically damped spring that settles in about [smoothTime] seconds.
  double _smoothDamp(
    double current,
    double target,
    double smoothTime,
    double dt,
  ) {
    if (dt <= 0) return current;
    final double omega = 2 / smoothTime;
    final double x = omega * dt;
    final double decay = 1 / (1 + x + 0.48 * x * x + 0.235 * x * x * x);
    final double change = current - target;
    final double temp = (_cameraVelocityX + omega * change) * dt;
    _cameraVelocityX = (_cameraVelocityX - omega * temp) * decay;
    return target + (change + temp) * decay;
  }

  @override
  void lifecycleStateChange(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _touchControls.clear();
      _intent.clear();
      _simulationAccumulator = 0;
      _audio.pause();
    } else {
      _audio.resume();
    }
    super.lifecycleStateChange(state);
  }

  @override
  void onRemove() {
    _audio.dispose();
    _intent.clear();
    super.onRemove();
  }

  Vector2 _idealCameraFor(Vector2 playerPosition, double lead) {
    return Vector2(
      playerPosition.x + lead,
      playerPosition.y - GameConfig.cameraLookUp,
    );
  }

  /// Keeps the camera's window inside the level.
  Vector2 _clampCamera(Vector2 target) {
    final Rect visible = camera.visibleWorldRect;
    final double halfW = visible.width / 2;
    final double halfH = visible.height / 2;
    final double minX = halfW;
    final double maxX = GameConfig.levelWidth - halfW;
    final double minY = halfH - 1.0; // a little sky above the level's top
    final double maxY = math.min(
      GameConfig.cameraMaxY,
      GameConfig.levelHeight - halfH,
    );
    return Vector2(
      maxX < minX ? GameConfig.levelWidth / 2 : target.x.clamp(minX, maxX),
      maxY < minY ? GameConfig.levelHeight / 2 : target.y.clamp(minY, maxY),
    );
  }
}

/// Times the native physics step and contact dispatch, excluding rendering.
class _ProfiledWorld extends Forge2DWorld {
  final Stopwatch _watch = Stopwatch();
  double stepMilliseconds = 0;
  @override
  void update(double dt) {
    _watch.reset();
    _watch.start();
    super.update(dt);
    _watch.stop();
    final sample = _watch.elapsedMicroseconds / 1000;
    stepMilliseconds += (sample - stepMilliseconds) * 0.10;
  }
}
