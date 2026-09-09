import 'package:flame/game.dart';
import 'package:flutter/widgets.dart';

import 'game/umbra_game.dart';

void main() {
  // GameWidget takes focus automatically, which is what lets the keyboard
  // handler receive key events without any extra focus plumbing.
  runApp(GameWidget(game: UmbraGame()));
}
