import '../input/player_intent.dart';
import 'bone_pit.dart';
import 'cage.dart';
import 'caves.dart';
import 'chandeliers.dart';
import 'chapter.dart';
import 'children.dart';
import 'chase.dart';
import 'clock_tower.dart';
import 'crypt.dart';
import 'dawn.dart';
import 'forest.dart';
import 'great_gate.dart';
import 'halls.dart';
import 'home.dart';
import 'mill.dart';
import 'storm.dart';

import 'campaign_catalog.dart';
import 'journey_chapter.dart';

class ChapterEntry {
  const ChapterEntry(this.id, this.title, this._build);
  final String id, title;
  final Chapter Function(PlayerIntent, bool) _build;
  Chapter build(PlayerIntent intent, {bool atTitle = false}) =>
      _build(intent, atTitle);
}

abstract final class Chapters {
  static final List<ChapterEntry> all = [
    ChapterEntry(
      CampaignCatalog.ids[0],
      CampaignCatalog.titles[0],
      (intent, atTitle) => HomeChapter(intent: intent, atTitle: atTitle),
    ),
    ChapterEntry(
      CampaignCatalog.ids[1],
      CampaignCatalog.titles[1],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 2),
    ),
    ChapterEntry(
      CampaignCatalog.ids[2],
      CampaignCatalog.titles[2],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 3),
    ),
    ChapterEntry(
      CampaignCatalog.ids[3],
      CampaignCatalog.titles[3],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 4),
    ),
    ChapterEntry(
      CampaignCatalog.ids[4],
      CampaignCatalog.titles[4],
      (intent, atTitle) => ForestChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[5],
      CampaignCatalog.titles[5],
      (intent, atTitle) => CageChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[6],
      CampaignCatalog.titles[6],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 7),
    ),
    ChapterEntry(
      CampaignCatalog.ids[7],
      CampaignCatalog.titles[7],
      (intent, atTitle) => CavesChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[8],
      CampaignCatalog.titles[8],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 9),
    ),
    ChapterEntry(
      CampaignCatalog.ids[9],
      CampaignCatalog.titles[9],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 10),
    ),
    ChapterEntry(
      CampaignCatalog.ids[10],
      CampaignCatalog.titles[10],
      (intent, atTitle) => CryptChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[11],
      CampaignCatalog.titles[11],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 12),
    ),
    ChapterEntry(
      CampaignCatalog.ids[12],
      CampaignCatalog.titles[12],
      (intent, atTitle) => BonePitChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[13],
      CampaignCatalog.titles[13],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 14),
    ),
    ChapterEntry(
      CampaignCatalog.ids[14],
      CampaignCatalog.titles[14],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 15),
    ),
    ChapterEntry(
      CampaignCatalog.ids[15],
      CampaignCatalog.titles[15],
      (intent, atTitle) => ChaseChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[16],
      CampaignCatalog.titles[16],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 17),
    ),
    ChapterEntry(
      CampaignCatalog.ids[17],
      CampaignCatalog.titles[17],
      (intent, atTitle) => HallsChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[18],
      CampaignCatalog.titles[18],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 19),
    ),
    ChapterEntry(
      CampaignCatalog.ids[19],
      CampaignCatalog.titles[19],
      (intent, atTitle) => ChandeliersChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[20],
      CampaignCatalog.titles[20],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 21),
    ),
    ChapterEntry(
      CampaignCatalog.ids[21],
      CampaignCatalog.titles[21],
      (intent, atTitle) => ClockTowerChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[22],
      CampaignCatalog.titles[22],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 23),
    ),
    ChapterEntry(
      CampaignCatalog.ids[23],
      CampaignCatalog.titles[23],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 24),
    ),
    ChapterEntry(
      CampaignCatalog.ids[24],
      CampaignCatalog.titles[24],
      (intent, atTitle) => ChildrenChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[25],
      CampaignCatalog.titles[25],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 26),
    ),
    ChapterEntry(
      CampaignCatalog.ids[26],
      CampaignCatalog.titles[26],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 27),
    ),
    ChapterEntry(
      CampaignCatalog.ids[27],
      CampaignCatalog.titles[27],
      (intent, atTitle) => MillChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[28],
      CampaignCatalog.titles[28],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 29),
    ),
    ChapterEntry(
      CampaignCatalog.ids[29],
      CampaignCatalog.titles[29],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 30),
    ),
    ChapterEntry(
      CampaignCatalog.ids[30],
      CampaignCatalog.titles[30],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 31),
    ),
    ChapterEntry(
      CampaignCatalog.ids[31],
      CampaignCatalog.titles[31],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 32),
    ),
    ChapterEntry(
      CampaignCatalog.ids[32],
      CampaignCatalog.titles[32],
      (intent, atTitle) => GreatGateChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[33],
      CampaignCatalog.titles[33],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 34),
    ),
    ChapterEntry(
      CampaignCatalog.ids[34],
      CampaignCatalog.titles[34],
      (intent, atTitle) => StormChapter(intent: intent),
    ),
    ChapterEntry(
      CampaignCatalog.ids[35],
      CampaignCatalog.titles[35],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 36),
    ),
    ChapterEntry(
      CampaignCatalog.ids[36],
      CampaignCatalog.titles[36],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 37),
    ),
    ChapterEntry(
      CampaignCatalog.ids[37],
      CampaignCatalog.titles[37],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 38),
    ),
    ChapterEntry(
      CampaignCatalog.ids[38],
      CampaignCatalog.titles[38],
      (intent, atTitle) => JourneyChapter(intent: intent, number: 39),
    ),
    ChapterEntry(
      CampaignCatalog.ids[39],
      CampaignCatalog.titles[39],
      (intent, atTitle) => DawnChapter(intent: intent),
    ),
  ];
  static const int story = 40;
  static const _ones = [
    'ZERO',
    'ONE',
    'TWO',
    'THREE',
    'FOUR',
    'FIVE',
    'SIX',
    'SEVEN',
    'EIGHT',
    'NINE',
    'TEN',
    'ELEVEN',
    'TWELVE',
    'THIRTEEN',
    'FOURTEEN',
    'FIFTEEN',
    'SIXTEEN',
    'SEVENTEEN',
    'EIGHTEEN',
    'NINETEEN',
  ];
  static String numberWord(int n) {
    if (n < 0 || n > 40) return '$n';
    if (n < 20) return _ones[n];
    final tens = const {2: 'TWENTY', 3: 'THIRTY', 4: 'FORTY'}[n ~/ 10]!;
    return n % 10 == 0 ? tens : '$tens-${_ones[n % 10]}';
  }
}
