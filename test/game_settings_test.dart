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
}
