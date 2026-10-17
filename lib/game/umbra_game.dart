import 'dart:math' as math;
import 'dart:ui';

import 'package:flame/flame.dart';
import 'package:flame/input.dart' show HasKeyboardHandlerComponents;
import 'package:flame_forge2d/flame_forge2d.dart';

import '../config/game_config.dart';
import '../config/game_settings.dart';
import '../character/character_interactions.dart';
import '../audio/ambient_audio.dart';
import '../config/palette.dart';
import '../entities/player.dart';
import '../input/keyboard_input.dart';
import '../input/player_intent.dart';
import '../input/touch_controls.dart';
import '../render/debug_hud.dart';
import '../render/fog_backdrop.dart';
import '../render/foreground_overlay.dart';
import '../story/chapter_card.dart';
import '../story/chapter_director.dart';
import '../story/progress_store.dart';
import '../world/checkpoint_service.dart';
import '../world/death_sequence.dart';
import '../world/level.dart';
import '../world/stage.dart';

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
///
/// ## Two ways to run
///
/// By default the game opens the proving ground, the 96 m test level every
/// physics and character test runs on. With [campaign] it is the real game:
/// the title over the first scene, then the chapters of the story one after
/// another, run by a [ChapterDirector].
class UmbraGame extends Forge2DGame with HasKeyboardHandlerComponents {
  /// [debugTools] adds the on-screen development buttons; it defaults to
  /// on only in `UMBRA_DEBUG` builds.
  UmbraGame({
    this.debugTools = DebugHud.enabled,
    this.campaign = false,
    ProgressStore? progress,
    GameSettings? settings,
    this.audioEnabled = false,
  }) : settings = settings ?? GameSettings(),
       progress = progress ?? ProgressStore.memory(),
       super(
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
  final GameSettings settings;

  /// Explicitly enabled by the application; headless physics tools stay silent.
  final bool audioEnabled;

  /// Whether this is the story rather than the proving ground.
  final bool campaign;

  /// The furthest chapter reached, kept between runs.
  final ProgressStore progress;

  /// Runs the story when [campaign] is set.
  ChapterDirector? director;

  /// The shared intent object that input writes to and the player reads from.
  final PlayerIntent _intent = PlayerIntent();
  PlayerIntent get intent => _intent;
  late final AmbientAudio _audio = AmbientAudio(
    settings: settings,
    outputEnabled: audioEnabled,
  );
  void unlockAudio() => _audio.unlock();
  double _controlScale = 1;
  int _heardSteps = 0, _heardLandings = 0;
  double _interactionSoundCooldown = 0;

  /// Owns the held-state of the on-screen walk buttons. Held as a field because
  /// the button callbacks close over it and it has to outlive [onLoad].
  late final TouchControls _touchControls = TouchControls(
    _intent,
    settings: settings,
    onRope: () => _player?.isOnRope ?? false,
    debugVisible: () => _debugVisible,
    hidden: () =>
        _stage == null ||
        isGameplayPaused ||
        _intent.isScripted ||
        (_stage?.controlsHidden ?? false) ||
        (director?.hidesControls ?? false),
    onPause: pauseGameplay,
    debugTools: debugTools,
  );

  static const String pauseOverlay = 'pause';
  bool get isGameplayPaused => overlays.isActive(pauseOverlay);

  void pauseGameplay() {
    if (isGameplayPaused || (director?.hidesControls ?? false)) return;
    _touchControls.clear();
    _intent.clear();
    pauseEngine();
    overlays.add(pauseOverlay);
    _audio.pause();
  }

  void resumeGameplay() {
    if (!isGameplayPaused) return;
    overlays.remove(pauseOverlay);
    _simulationAccumulator = 0;
    resumeEngine();
    _audio.resume();
  }

  void resetFromPause() {
    final player = _player;
    if (player == null) return;
    deathSequence.cancel();
    checkpoints.respawn(player);
    resumeGameplay();
  }

  Future<void> returnToTitle() async {
    if (director == null) return;
    deathSequence.cancel();
    resumeGameplay();
    await director!.start();
  }

  void _settingsChanged() {
    _audio.updateMix();
    if (_controlScale != settings.controlsScale) {
      _controlScale = settings.controlsScale;
      _touchControls.removeButtons();
      camera.viewport.addAll(_touchControls.buildButtons());
    }
  }

  bool get soundEnabled => _audio.enabled;
  void toggleSound() => _audio.toggle();

  /// Respawn state: the current stage's.
  CheckpointService checkpoints = CheckpointService(
    initialCheckpoint: GameConfig.playerSpawn,
  );

  /// Plays out a death: the limp body, the fade to black, the respawn.
  late DeathSequence deathSequence = DeathSequence(checkpoints: checkpoints);

  /// The player, once the level has built it. The camera follows this.
  Player? _player;
  Player? get player => _player;

  /// The level or chapter being played.
  Stage? _stage;
  Stage? get stage => _stage;
  FogBackdrop? _backdrop;

  /// Where the camera is heading. Kept separate from the camera's actual
  /// position so it can ease towards it.
  final Vector2 _cameraTarget = Vector2.zero();

  /// The smoothly following camera position, before any shake.
  final Vector2 _cameraBase = Vector2.zero();
  double _cameraVelocityX = 0;
  double _lookAhead = 0;

  /// Camera shake from hard landings: 0 to 1, dying away.
  double _trauma = 0;
  double _shakeClock = 0;
  int _seenLandings = 0;
  double get cameraTrauma => _trauma;

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
    _controlScale = settings.controlsScale;
    settings.addListener(_settingsChanged);

    // Frame a 16 x 9 m window on the world, in metres. Flame fits it to the
    // screen and keeps it fitted through resizes; a wider phone sees more of
    // the level to the sides rather than a stretched picture.
    camera.viewfinder.visibleGameSize = Vector2(
      GameConfig.cameraVisibleWidth,
      GameConfig.cameraVisibleHeight,
    );

    // Out-of-focus shapes and the lens in front of the world, and the
    // black the picture fades to when he dies or a scene ends.
    await camera.viewport.addAll([
      ForegroundFog(camera: camera),
      ForegroundOverlay(camera: camera, settings: settings),
      ScreenFade(camera: camera, blackness: () => blackness),
    ]);

    // The keyboard listener lives on the game, not in the world: it is not a
    // thing in the room, it is a source of events. HasKeyboardHandlerComponents
    // walks the component tree and delivers key events to any KeyboardHandler.
    //
    // Kept even though Umbra ships on Android, where there is no keyboard: it
    // costs nothing at runtime, it is what the test suite drives the player
    // with, and it means the game is still playable on a desktop while
    // developing.
    await add(
      KeyboardInput(_intent, onPause: pauseGameplay, onActivity: unlockAudio),
    );

    // Touch controls go in the camera's *viewport*, not in the world. The
    // viewport is screen space, so the buttons keep a constant thumb-sized
    // footprint in pixels and never scale or pan with the camera. They must be
    // added directly to it, because Flame positions them by a margin measured
    // against their immediate parent's size.
    await camera.viewport.addAll(_touchControls.buildButtons());

    await world.add(
      PhysicsDebugOverlay(world: world, isVisible: () => _debugVisible),
    );
    await camera.viewport.add(
      DebugHud(
        camera: camera,
        player: () => _player,
        isVisible: () => _debugVisible,
        framesPerSecond: () => _fps,
        physicsMilliseconds: () => physicsMilliseconds,
      ),
    );

    if (campaign) {
      final director = this.director = ChapterDirector(
        game: this,
        progress: progress,
      );
      await camera.viewport.add(
        ChapterCard(camera: camera, director: director),
      );
      await director.start();
    } else {
      // Everything physical goes into the physics world.
      await setStage(
        Level(
          intent: _intent,
          checkpoints: CheckpointService(
            initialCheckpoint: GameConfig.playerSpawn,
          ),
        ),
      );
    }
  }

  /// How black the picture is: a death, a stage's own fade or the story's
  /// fades between chapters, whichever is darkest.
  double get blackness => math.max(
    deathSequence.blackness,
    math.max(_stage?.blackness ?? 0, director?.blackness ?? 0),
  );

  /// Swaps in [stage]: the old one and every body in it are removed, the
  /// fog behind is rebuilt for the new mood, and the camera starts on the
  /// boy.
  Future<void> setStage(Stage stage) async {
    final Stage? old = _stage;
    if (old != null) {
      world.remove(old);
      // Removal happens at the end of the tick; wait for it, so the old
      // bodies are gone before the new ones are made.
      await old.removed;
    }
    _touchControls.clear();
    // Out of any close-up the old stage ended on.
    _zoom = 1;
    camera.viewfinder.visibleGameSize = Vector2(
      GameConfig.cameraVisibleWidth,
      GameConfig.cameraVisibleHeight,
    );
    // A scene in the old stage may have held the controls.
    _intent.endScript();
    _intent.clear();
    _simulationAccumulator = 0;
    _stage = stage;
    checkpoints = stage.checkpoints;
    deathSequence = DeathSequence(checkpoints: checkpoints);
    await world.add(stage);
    final Player player = _player = stage.player;
    player.debugEnabled = _debugVisible;

    // Start the camera on the boy so the first frame is not a pan.
    _lookAhead = 0;
    _cameraVelocityX = 0;
    _trauma = 0;
    _seenLandings = 0;
    _cameraTarget.setFrom(
      _clampCamera(stage.cameraFocus ?? _idealCameraFor(player.position, 0)),
    );
    camera.viewfinder.position = _cameraTarget.clone();
    _cameraBase.setFrom(_cameraTarget);

    // The fog and forest (or rock) behind the world, for this stage's air.
    final FogBackdrop? oldBackdrop = _backdrop;
    if (oldBackdrop != null) camera.backdrop.remove(oldBackdrop);
    await camera.backdrop.add(
      _backdrop = FogBackdrop(
        camera: camera,
        moods: stage.moods,
        layerSpecs: stage.backdropSpecs,
        groundFor: stage.backdropGround,
        props: () => stage.backdropProps,
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
    director?.update(frameDt);
    final Player? player = _player;
    if (player == null || !player.isMounted) {
      return;
    }
    deathSequence.update(frameDt, player);
    if (player.footfalls != _heardSteps) {
      _heardSteps = player.footfalls;
      _audio.effect(player.waterDepth > 0.05 ? 'water' : 'step', 0.5);
    }
    if (player.landings != _heardLandings) {
      _heardLandings = player.landings;
      _audio.effect('land', (player.lastLandingImpact / 7).clamp(0.15, 1));
    }
    _interactionSoundCooldown -= frameDt;
    if (_interactionSoundCooldown <= 0 && player.velocity.length > 0.2) {
      final mode = player.interactions.mode;
      if (mode == InteractionMode.swinging) {
        _audio.effect('rope', 0.35);
        _interactionSoundCooldown = 1.2;
      } else if (mode == InteractionMode.pushing ||
          mode == InteractionMode.pulling) {
        _audio.effect('drag', 0.45);
        _interactionSoundCooldown = 0.45;
      }
    }

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

    final Vector2? focus = _stage?.cameraFocus;
    final Vector2 ideal =
        focus?.clone() ?? _idealCameraFor(player.cameraPosition, _lookAhead);
    final current = _cameraBase;
    // Ignore small vertical landing corrections and idle motion.
    if (focus == null && (ideal.y - current.y).abs() < 0.35) {
      ideal.y = current.y;
    }
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
    _cameraBase.setValues(nextX, current.y + (_cameraTarget.y - current.y) * t);
    camera.viewfinder.position = _cameraBase + _shake(player, frameDt);
    // Coming in close (or back out) slowly, for a scene's close-up.
    final double want = _stage?.cameraZoom ?? 1;
    if ((want - _zoom).abs() > 1e-4) {
      _zoom += (want - _zoom) * (1 - math.exp(-1.6 * frameDt));
      if ((want - _zoom).abs() < 1e-3) _zoom = want;
      camera.viewfinder.visibleGameSize = Vector2(
        GameConfig.cameraVisibleWidth / _zoom,
        GameConfig.cameraVisibleHeight / _zoom,
      );
    }
  }

  double _zoom = 1;

  /// A hard landing jolts the view: mostly up and down, a little sideways,
  /// fading out fast.
  Vector2 _shake(Player player, double dt) {
    if (player.landings != _seenLandings) {
      _seenLandings = player.landings;
      final double impact = player.lastLandingImpact;
      if (impact > GameConfig.cameraShakeImpact) {
        _trauma = math.min(
          1,
          _trauma + (impact - GameConfig.cameraShakeImpact + 1) / 7,
        );
      }
    }
    _trauma = math.max(0, _trauma - dt / GameConfig.cameraShakeSeconds);
    if (_trauma <= 0) return Vector2.zero();
    _shakeClock += dt;
    final double amount = GameConfig.cameraShakeMeters * _trauma * _trauma;
    return Vector2(
      amount * 0.4 * math.sin(_shakeClock * 41 + 0.7),
      amount * math.sin(_shakeClock * 53),
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
    settings.removeListener(_settingsChanged);
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
    final double width = _stage?.width ?? GameConfig.levelWidth;
    final double height = _stage?.height ?? GameConfig.levelHeight;
    final double minX = halfW;
    final double maxX = width - halfW;
    final double minY = halfH - 1.0; // a little sky above the level's top
    final double maxY = math.min(
      _stage?.cameraMaxY ?? GameConfig.cameraMaxY,
      height - halfH,
    );
    return Vector2(
      maxX < minX ? width / 2 : target.x.clamp(minX, maxX),
      maxY < minY ? height / 2 : target.y.clamp(minY, maxY),
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
