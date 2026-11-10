import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:umbra/combat/weapons.dart';
import 'package:umbra/story/progress_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forty chapters map to ten families and four ordered tiers', () {
    final definitions = [
      for (var chapter = 0; chapter < 40; chapter++)
        WeaponCatalog.forChapter(chapter),
    ];
    expect(definitions, hasLength(40));
    for (var chapter = 0; chapter < definitions.length; chapter++) {
      expect(definitions[chapter].family, WeaponFamily.values[chapter % 10]);
      expect(definitions[chapter].tier, chapter ~/ 10 + 1);
      expect(definitions[chapter].name, isNotEmpty);
      expect(definitions[chapter].recovery, greaterThan(0));
    }
  });

  test('inventory upgrades equipped family in place and refills ammo', () {
    final inventory = WeaponInventory();
    final first = WeaponCatalog.forChapter(1);
    inventory.unlock(first);
    expect(inventory.activeFamily, WeaponFamily.shuriken);
    expect(inventory.ammoFor(WeaponFamily.shuriken), first.maxAmmo);
    expect(inventory.spend(), isTrue);
    expect(inventory.ammoFor(WeaponFamily.shuriken), first.maxAmmo - 1);

    final upgrade = WeaponCatalog.forChapter(11);
    inventory.unlock(upgrade);
    expect(inventory.equipped.singleWhere((f) => f != null), upgrade.family);
    expect(inventory.active!.tier, 2);
    inventory.refill();
    expect(inventory.ammoFor(upgrade.family), upgrade.maxAmmo);
  });

  test('version three persists loadout and collected chapter', () async {
    SharedPreferences.setMockInitialValues({});
    final progress = await ProgressStore.load();
    final inventory = WeaponInventory()
      ..unlock(WeaponCatalog.forChapter(0))
      ..unlock(WeaponCatalog.forChapter(1));
    inventory.select(1);
    await inventory.save(progress, collectedChapter: 1);

    final loaded = await ProgressStore.load();
    final restored = WeaponInventory.fromProgress(loaded);
    expect(restored.tiers[WeaponFamily.katana], 1);
    expect(restored.tiers[WeaponFamily.shuriken], 1);
    expect(restored.activeSlot, 1);
    expect(loaded.weaponPickups, contains(1));
  });

  test(
    'version two save grants missed pickups through furthest chapter',
    () async {
      SharedPreferences.setMockInitialValues({
        'umbra.campaign.v2': jsonEncode({
          'version': 2,
          'furthest': 'bone_pit',
          'chapter': 'bone_pit',
          'checkpoint': null,
        }),
      });
      final progress = await ProgressStore.load();
      final inventory = WeaponInventory.fromProgress(progress);
      expect(progress.weaponPickups, containsAll(List.generate(13, (i) => i)));
      expect(inventory.tiers[WeaponFamily.katana], 2);
      expect(inventory.tiers[WeaponFamily.kunai], 2);
      expect(inventory.equipped.whereType<WeaponFamily>(), hasLength(3));
    },
  );
}
