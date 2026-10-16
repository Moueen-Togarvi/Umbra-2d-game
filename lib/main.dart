import 'package:flame/game.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'chapters/chapters.dart';
import 'config/palette.dart';
import 'game/umbra_game.dart';
import 'story/chapter_director.dart';
import 'story/progress_store.dart';
import 'ui/title_screen.dart';

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

  final progress = await ProgressStore.load();
  // `--dart-define=UMBRA_UNLOCK_ALL=true` opens every chapter in the list,
  // for checking a later chapter on a device.
  if (const bool.fromEnvironment('UMBRA_UNLOCK_ALL')) {
    await progress.reach(Chapters.all.length - 1);
  }

  // `--dart-define=UMBRA_PROVING_GROUND=true` opens the test level instead
  // of the story.
  const bool provingGround = bool.fromEnvironment('UMBRA_PROVING_GROUND');
  final game = UmbraGame(campaign: !provingGround, progress: progress);

  runApp(
    GameWidget<UmbraGame>(
      game: game,
      loadingBuilder: (_) => const ColoredBox(color: Palette.brandBlack),
      overlayBuilderMap: {
        ChapterDirector.titleOverlay: (context, game) =>
            TitleScreen(game: game),
      },
    ),
  );
}
