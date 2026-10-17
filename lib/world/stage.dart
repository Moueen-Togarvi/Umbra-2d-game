import 'package:flame/components.dart';

import '../entities/player.dart';
import '../render/fog_layer.dart';
import '../render/chapter_backgrounds.dart';
import '../render/light.dart';
import '../render/mood.dart';
import '../render/scenery.dart';
import 'checkpoint_service.dart';

/// A place the boy can be: the proving ground or a chapter of the story.
///
/// The game holds one at a time. It asks the stage how big it is (to keep
/// the camera inside it), what the air is like (for the fog behind it) and
/// where the boy is; the stage builds and owns everything in it.
abstract class Stage extends Component {
  /// Metres, from x = 0 and y = 0 at the top.
  double get width;
  double get height;

  /// The lowest the camera's centre may go: below this is only earth.
  double get cameraMaxY;

  MoodTrack get moods;

  /// Where the far ground lies for a camera at x, or null for the
  /// backdrop's fixed horizon.
  double Function(double cameraX)? get backdropGround => null;

  /// The depth layers to stand in the fog, or null for the usual forest.
  List<FogLayerSpec>? get backdropSpecs => null;

  ChapterBackground? get backgroundPlan => null;

  /// Scenery far enough off to stand among the fog layers rather than in
  /// front of them; the backdrop draws these, each between the layers
  /// nearer and further than it.
  final List<BackdropDrawable> backdropProps = [];

  /// Sounds asked for this frame, as (name, loudness 0–1), and how hard
  /// the picture should shake; the game plays and empties them.
  final List<(String, double)> cues = [];
  double shake = 0;

  /// The loop that sets this place's sound, under the wind (rain, the
  /// works of a clock, running water, birds at dawn), or null.
  String? get ambience => null;

  /// Asks for the sound [name], as loud as [weight] and quieter the
  /// further [at] is from the camera; and a shake of [shake] (0–1).
  void cue(String name, {double weight = 1, Vector2? at, double shake = 0}) {
    double w = weight;
    final Vector2? camera =
        cameraFocus ?? (isMounted ? player.body.position : null);
    if (at != null && camera != null) {
      final double d = (at - camera).length;
      w *= (1 - (d - 6) / 18).clamp(0.0, 1.0);
    }
    if (w > 0.02) cues.add((name, w));
    if (shake > 0 && w > 0.02) {
      this.shake = (this.shake + shake * w).clamp(0, 1);
    }
  }

  /// Everything that lights the world here (see [LightSource]).
  final List<LightSource> lights = [];

  /// Whether [point] is in any light.
  bool isLit(Vector2 point) {
    for (final light in lights) {
      if (light.lights(point)) return true;
    }
    return false;
  }

  /// Available as soon as the stage has loaded.
  Player get player;

  CheckpointService get checkpoints;

  /// Where a cutscene wants the camera, or null to follow the boy.
  Vector2? cameraFocus;

  /// How close the camera comes in, 1 as usual (a scene's close-up).
  double cameraZoom = 1;

  /// Black over the whole picture, 0 to 1, for a stage's own fades
  /// (cutscenes, its last moment).
  double blackness = 0;

  /// Whether the play buttons should be hidden (a cutscene is running).
  bool get controlsHidden => false;

  /// Set once the boy has reached the stage's end.
  bool get isComplete => false;
}

/// A light that joins its stage's [Stage.lights] while it is mounted.
mixin StageLight on Component implements LightSource {
  Stage? stage;

  @override
  void onMount() {
    super.onMount();
    stage = ancestors().whereType<Stage>().firstOrNull;
    stage?.lights.add(this);
  }

  @override
  void onRemove() {
    stage?.lights.remove(this);
    super.onRemove();
  }
}

/// A sound (and a shake) from anything on a stage.
extension StageCues on Component {
  void cue(String name, {double weight = 1, Vector2? at, double shake = 0}) {
    final Stage? stage = this is Stage
        ? this as Stage
        : ancestors().whereType<Stage>().firstOrNull;
    stage?.cue(name, weight: weight, at: at, shake: shake);
  }
}
