import 'package:flame/components.dart';

import '../entities/player.dart';
import '../render/fog_layer.dart';
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

  /// Scenery far enough off to stand among the fog layers rather than in
  /// front of them; the backdrop draws these, each between the layers
  /// nearer and further than it.
  final List<BackdropDrawable> backdropProps = [];

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

  /// Black over the whole picture, 0 to 1, for a stage's own fades
  /// (cutscenes, its last moment).
  double blackness = 0;

  /// Whether the play buttons should be hidden (a cutscene is running).
  bool get controlsHidden => false;

  /// Set once the boy has reached the stage's end.
  bool get isComplete => false;
}
