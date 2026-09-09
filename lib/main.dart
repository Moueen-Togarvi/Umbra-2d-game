import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'game/umbra_game.dart';

Future<void> main() async {
  // Required before touching SystemChrome: those calls go over a platform
  // channel, and the channel does not exist until the binding is initialised.
  WidgetsFlutterBinding.ensureInitialized();

  // Umbra is a landscape game. Locking the orientation here covers the Flutter
  // side; AndroidManifest.xml also declares `screenOrientation`, which is what
  // stops the app flashing up in portrait for a frame during a cold start
  // before Dart has had a chance to run. Both are needed.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Hide the status and navigation bars. On a phone they would eat the play
  // area and, worse, sit exactly where the thumbs rest. `immersiveSticky`
  // brings them back temporarily on a swipe from the edge and then hides them
  // again, rather than permanently giving up the space.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  runApp(GameWidget(game: UmbraGame()));
}
