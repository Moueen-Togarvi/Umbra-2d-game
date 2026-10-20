import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/config/game_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('settings survive reload without changing chapter progress', () async {
    SharedPreferences.setMockInitialValues({'umbra.reachedChapter': 4});
    final settings = await GameSettings.load();
    settings.set('brightness', 1.15);
    settings.set('controlsScale', 1.2);
    settings.set('effects', .3);
    await Future<void>.delayed(Duration.zero);
    final reloaded = await GameSettings.load();
    expect(reloaded.brightness, 1.15);
    expect(reloaded.controlsScale, 1.2);
    expect(reloaded.effects, .3);
    expect(
      (await SharedPreferences.getInstance()).getInt('umbra.reachedChapter'),
      4,
    );
  });
  test(
    'damaged storage and extreme input cannot create invalid slider values',
    () async {
      SharedPreferences.setMockInitialValues({
        'umbra.settings.brightness': 'invalid',
        'umbra.settings.controlsScale': 40.0,
        'umbra.settings.effects': double.nan,
      });
      final settings = await GameSettings.load();
      expect(settings.brightness, 1);
      expect(settings.controlsScale, 1.3);
      expect(settings.effects, .8);
      settings.set('brightness', double.nan);
      settings.set('controlsOpacity', -50);
      expect(settings.brightness, 1);
      expect(settings.controlsOpacity, .3);
    },
  );
  test('music and sound choices survive reload', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = await GameSettings.load();
    expect(settings.musicOn, isTrue);
    expect(settings.soundOn, isTrue);
    expect(settings.background, GameSettings.defaultBackground);
    expect(settings.music, .6);
    var heard = 0;
    settings.addListener(() => heard++);
    settings
      ..set('music', .25)
      ..setFlag('musicOn', false)
      ..setFlag('soundOn', false)
      ..setBackground('bg_descent');
    expect(heard, 4);
    await Future<void>.delayed(Duration.zero);
    final reloaded = await GameSettings.load();
    expect(reloaded.music, .25);
    expect(reloaded.musicOn, isFalse);
    expect(reloaded.soundOn, isFalse);
    expect(reloaded.background, 'bg_descent');
    expect(() => settings.setFlag('nonsense', true), throwsArgumentError);
  });
}
