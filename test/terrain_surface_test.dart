import 'dart:math' as math;

import 'package:flame/game.dart' show Vector2;
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/config/game_config.dart';
import 'package:umbra/world/terrain.dart';

void main() {
  test('all six banks share collision heights and leave spawn level', () {
    final terrain = Terrain([
      for (final flat in GameConfig.terrainProfile)
        [
          for (var i = 0; i < flat.length; i += 2)
            Vector2(flat[i], flat[i + 1]),
        ],
    ]);

    for (final segment in terrain.segments) {
      for (final control in segment.controls) {
        expect(segment.heightAt(control.x), closeTo(control.y, 1e-10));
      }
      for (var i = 0; i < segment.surface.length - 1; i++) {
        final a = segment.surface[i];
        final b = segment.surface[i + 1];
        final x = (a.x + b.x) / 2;
        // Forge2D's Vector2 stores single-precision coordinates.
        expect(b.x - a.x, lessThanOrEqualTo(TerrainSegment.sampleStep + 1e-5));
        expect(segment.heightAt(x), closeTo((a.y + b.y) / 2, 1e-10));
        expect(segment.slopeAt(x), closeTo((b.y - a.y) / (b.x - a.x), 1e-10));
      }
    }
    for (double x = 0; x <= 4; x += 0.1) {
      expect(terrain.heightAt(x), closeTo(GameConfig.floorSurfaceY, 1e-10));
      expect(terrain.slopeAt(x), closeTo(0, 1e-10));
    }
    expect(
      terrain.heightAt((GameConfig.gapStartX + GameConfig.gapEndX) / 2),
      isNull,
    );
  });

  test('level shelves stay level beside steep banks without spline humps', () {
    final segment = TerrainSegment([
      Vector2(0, 7),
      Vector2(3, 7),
      Vector2(4, 5),
      Vector2(8, 5),
      Vector2(9, 8),
    ]);
    for (final point in segment.surface) {
      for (var i = 0; i < segment.controls.length - 1; i++) {
        final a = segment.controls[i];
        final b = segment.controls[i + 1];
        if (point.x < a.x || point.x > b.x) continue;
        if (a.y == b.y) {
          expect(point.y, closeTo(a.y, 1e-10));
        } else {
          expect(
            point.y,
            inInclusiveRange(
              math.min(a.y, b.y) - 0.027,
              math.max(a.y, b.y) + 0.027,
            ),
          );
        }
      }
    }
  });
}
