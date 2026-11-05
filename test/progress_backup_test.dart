import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/story/progress_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'corrupt primary progress recovers the saved checkpoint from backup',
    () async {
      SharedPreferences.setMockInitialValues({});
      final progress = await ProgressStore.load();
      await progress.enter(4);
      await progress.saveCheckpoint('forest', 'checkpoint-2');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(ProgressStore.key, 'broken');
      final recovered = await ProgressStore.load();
      expect(recovered.current, 4);
      expect(recovered.checkpoint, 'checkpoint-2');
      expect(recovered.canContinue, isTrue);
    },
  );
}
