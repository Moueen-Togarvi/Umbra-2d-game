import 'package:flame/flame.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:umbra/chapters/chapter.dart';
import 'package:umbra/story/cottage.dart';
import 'support/campaign.dart';

void main() {
  testWidgets(
    'painted scenery stays undecoded while live props load their art',
    (tester) async {
      final game = await bootCampaign(tester);
      await enterChapter<Chapter>(tester, game, 0);
      expect(Flame.images.containsKey(Cottage.art), isTrue);
      expect(
        Flame.images.containsKey('part1/ch1_orchard_tree_a_far.png'),
        isFalse,
      );
      await enterChapter<Chapter>(tester, game, 19);
      expect(Flame.images.containsKey('part3/ch9_far_chandelier.png'), isTrue);
      expect(
        Flame.images.containsKey('part1/ch1_orchard_tree_a_far.png'),
        isFalse,
      );
    },
  );
}
