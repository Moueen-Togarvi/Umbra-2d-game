// The main menu's picture alone, with no words over it, for laying out
// menu designs on:
//   flutter test tool/capture/capture_menu_scene_test.dart
// Writes build/chapters-preview/menu/scene.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/ui/menu_scene.dart';

void main() {
  testWidgets('menu scene', (tester) async {
    const size = Size(1600, 720);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: const ColoredBox(color: Colors.black, child: MenuScene()),
        ),
      ),
    );
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final bytes = await tester.runAsync(() async {
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    });
    final dir = Directory('build/chapters-preview/menu')
      ..createSync(recursive: true);
    File('${dir.path}/scene.png').writeAsBytesSync(bytes!);
  });
}
