import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/audio/ambient_audio.dart';
import 'package:umbra/config/game_settings.dart';

// Exercise the real audioplayers command path. Deliberately never send a
// seek-complete event: restarting a stopped web voice must not depend on one.
class _AssetCache extends AudioCache {
  @override
  Future<Uri> load(String fileName) async => Uri.file('/test/$fileName');
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  test('footstrikes survive busy voices; the music follows the settings; '
      'pause cancels queued steps', () async {
    final messenger = binding.defaultBinaryMessenger;
    const codec = StandardMethodCodec();
    final sources = <String, String>{};
    final calls = <MethodCall>[];
    final channels = <String>{};
    Completer<void>? holdSteps;
    void channel(String name) {
      channels.add(name);
      messenger.setMockMethodCallHandler(
        MethodChannel(name),
        (_) async => null,
      );
    }

    channel('xyz.luan/audioplayers.global/events');
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers.global'),
      (_) async => null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('xyz.luan/audioplayers'),
      (call) async {
        calls.add(call);
        final args = Map<String, dynamic>.from(call.arguments as Map);
        final id = args['playerId'] as String;
        if (call.method == 'create') {
          channel('xyz.luan/audioplayers/events/$id');
        }
        if (call.method == 'setSourceUrl') {
          sources[id] = args['url'] as String;
          await messenger.handlePlatformMessage(
            'xyz.luan/audioplayers/events/$id',
            codec.encodeSuccessEnvelope({
              'event': 'audio.onPrepared',
              'value': true,
            }),
            (_) {},
          );
        }
        if (call.method == 'stop' &&
            (sources[id]?.contains('step_run') ?? false)) {
          await holdSteps?.future;
        }
        if (call.method == 'getCurrentPosition' ||
            call.method == 'getDuration') {
          return 0;
        }
        return null;
      },
    );
    final oldCache = AudioCache.instance;
    AudioCache.instance = _AssetCache();
    final settings = GameSettings();
    final audio = AmbientAudio(settings: settings, outputEnabled: true);
    addTearDown(() async {
      holdSteps?.complete();
      holdSteps = null;
      await audio.dispose();
      AudioCache.instance = oldCache;
      for (final name in [
        ...channels,
        'xyz.luan/audioplayers',
        'xyz.luan/audioplayers.global',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(name), null);
      }
    });
    await audio.unlock();
    bool isStep(MethodCall c) =>
        c.method == 'resume' &&
        (sources[(c.arguments as Map)['playerId']]?.contains('step_run') ??
            false);
    Future<void> drain() async {
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    holdSteps = Completer<void>();
    for (var i = 0; i < 18; i++) {
      audio.effect('step_run', 0.65);
    }
    await drain();
    expect(calls.where(isStep), isEmpty);
    holdSteps!.complete();
    holdSteps = null;
    await drain();
    expect(calls.where(isStep), hasLength(18), reason: 'no busy-voice drops');
    expect(calls.where((c) => c.method == 'seek'), isEmpty);
    // A low-latency voice never reports finishing. Nothing may ask the
    // platform where it is every frame from then on: that flood is what
    // left the later footsteps waiting until they were never heard.
    for (var frame = 1; frame <= 30; frame++) {
      binding.handleBeginFrame(Duration(milliseconds: frame * 16));
      binding.handleDrawFrame();
      await drain();
    }
    expect(calls.where((c) => c.method == 'getCurrentPosition'), isEmpty);

    // The music the game asks for comes in.
    audio.score('bg_descent');
    audio.update(1 / 60);
    await drain();
    audio.update(1.0);
    await drain();
    final score = sources.entries.singleWhere(
      (s) => s.value.contains('bg_descent'),
    );
    double lastVolume() =>
        (calls
                    .where(
                      (c) =>
                          c.method == 'setVolume' &&
                          (c.arguments as Map)['playerId'] == score.key,
                    )
                    .last
                    .arguments
                as Map)['volume']
            as double;
    expect(
      calls.where(
        (c) =>
            c.method == 'resume' &&
            (c.arguments as Map)['playerId'] == score.key,
      ),
      isNotEmpty,
    );
    expect(lastVolume(), greaterThan(0));
    // Music off: silent; on again: heard.
    settings.setFlag('musicOn', false);
    await audio.updateMix();
    await drain();
    expect(lastVolume(), 0);
    settings.setFlag('musicOn', true);
    await audio.updateMix();
    audio.update(0.1);
    await drain();
    expect(lastVolume(), greaterThan(0));
    // The speaker off: the music stops and no step sounds.
    calls.clear();
    settings.setFlag('soundOn', false);
    await audio.updateMix();
    audio.effect('step_run', 0.65);
    await drain();
    expect(
      calls.where(
        (c) =>
            c.method == 'pause' &&
            (c.arguments as Map)['playerId'] == score.key,
      ),
      isNotEmpty,
    );
    expect(calls.where(isStep), isEmpty);
    settings.setFlag('soundOn', true);
    await audio.updateMix();
    await drain();

    calls.clear();
    holdSteps = Completer<void>();
    for (var i = 0; i < 10; i++) {
      audio.effect('step_run', 0.65);
    }
    await drain();
    final paused = audio.pause();
    holdSteps!.complete();
    holdSteps = null;
    await paused;
    await drain();
    expect(
      calls.where(isStep),
      isEmpty,
      reason: 'queued steps never sound after pause',
    );
    audio.effect('step_run', 0.65);
    await drain();
    expect(calls.where(isStep), isEmpty);
    await audio.resume();
    audio.effect('step_run', 0.65);
    await drain();
    expect(calls.where(isStep), hasLength(1));
  });
}
