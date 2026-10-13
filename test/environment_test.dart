import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/render/fog_backdrop.dart';
import 'package:umbra/render/fog_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('fog layers bake into small images that tile seamlessly', (
    tester,
  ) async {
    final specs = [...FogBackdrop.specs, ForegroundFog.spec];
    var bytes = 0;
    for (final spec in specs) {
      final layer = FogLayer.bake(
        spec,
        visibleHeight: GameConfig.cameraVisibleHeight,
        maxCameraRise: 3.5,
      );
      final image = layer.image;
      bytes += image.width * image.height * 4;
      expect(image.width, lessThanOrEqualTo(4096), reason: 'mobile textures');
      expect(image.height, lessThanOrEqualTo(4096));

      // The first and last columns are neighbours once the tile repeats:
      // across that seam the picture should change no more than it does
      // between the columns either side of it.
      final data = await tester.runAsync(
        () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
      );
      final pixels = data!.buffer.asUint8List();
      final w = image.width;
      double columnDifference(int a, int b) {
        var total = 0.0;
        for (var y = 0; y < image.height; y++) {
          for (var c = 0; c < 4; c++) {
            total += (pixels[(y * w + a) * 4 + c] - pixels[(y * w + b) * 4 + c])
                .abs();
          }
        }
        return total / (image.height * 4);
      }

      final seam = columnDifference(w - 1, 0);
      final neighbours = [
        columnDifference(w - 2, w - 1),
        columnDifference(0, 1),
      ].reduce((a, b) => a > b ? a : b);
      expect(
        seam,
        lessThan(neighbours * 2 + 1.5),
        reason: 'seam in layer at depth ${spec.depth}',
      );
      var coverage = 0;
      for (var i = 3; i < pixels.length; i += 4 * 97) {
        coverage += pixels[i];
      }
      if (!spec.foreground) {
        expect(coverage, greaterThan(0), reason: 'layer drew nothing');
      }
      layer.dispose();
    }
    expect(bytes, lessThan(16 * 1024 * 1024), reason: '$bytes bytes');
  });
}
