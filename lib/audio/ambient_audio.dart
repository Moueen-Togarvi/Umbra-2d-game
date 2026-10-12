import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A quiet native wind loop on Android; other targets remain silent.
/// No decoder, network stream or per-frame platform call is involved.
class AmbientAudio {
  static const _channel = MethodChannel('umbra/ambience');
  bool enabled = true;
  bool _paused = false;

  Future<void> start() => _send('start');
  Future<void> pause() async {
    _paused = true;
    await _send('pause');
  }

  Future<void> resume() async {
    _paused = false;
    await _send('start');
  }

  Future<void> dispose() => _send('dispose');
  Future<void> toggle() async {
    enabled = !enabled;
    await _send(enabled && !_paused ? 'start' : 'pause');
  }

  Future<void> _send(String action) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    if (action == 'start' && (!enabled || _paused)) return;
    try {
      await _channel.invokeMethod<void>(action);
    } on MissingPluginException {
      // Widget tests and non-Android embedders do not install this channel.
    } on PlatformException catch (error) {
      if (kDebugMode) debugPrint('Umbra ambience: ${error.code}');
    }
  }
}
