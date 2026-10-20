// Browser-only verification harness: flutter build web --target tool/audio/web_audio_probe.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:umbra/audio/ambient_audio_web.dart';
import 'package:umbra/config/game_settings.dart';

void main() => runApp(const MaterialApp(home: AudioProbe()));

class AudioProbe extends StatefulWidget {
  const AudioProbe({super.key});
  @override
  State<AudioProbe> createState() => _AudioProbeState();
}

class _AudioProbeState extends State<AudioProbe> {
  final settings = GameSettings();
  late final audio = AmbientAudio(settings: settings, outputEnabled: true);
  String result = 'Run audio checks';
  bool running = false;
  Future<void> run() async {
    if (running) return;
    setState(() {
      running = true;
      result = 'Running';
    });
    await audio.unlock();
    audio.effect('heartbeat', 1);
    await Future<void>.delayed(const Duration(seconds: 3));
    audio.cancelEffects();
    for (var i = 0; i < 100; i++) {
      audio.effect('heartbeat', 1, i.isEven ? -.8 : .8);
    }
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final saturated = audio.activeVoices;
    await audio.pause();
    final paused = audio.activeVoices;
    await audio.resume();
    audio.effect('heartbeat', 1);
    audio.cancelEffects();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final transition = audio.activeVoices;
    audio.effect('heartbeat', 1);
    settings.setFlag('soundOn', false);
    await audio.updateMix();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    final muted = audio.activeVoices;
    await audio.dispose();
    setState(
      () => result = jsonEncode({
        'saturated': saturated,
        'limit': AmbientAudio.maxVoices,
        'paused': paused,
        'transitionCancelled': transition,
        'muted': muted,
        'passed':
            saturated == 12 && paused == 0 && transition == 0 && muted == 0,
      }),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ElevatedButton(
            onPressed: running ? null : run,
            child: const Text('Run audio checks'),
          ),
          Text(result),
        ],
      ),
    ),
  );
}
