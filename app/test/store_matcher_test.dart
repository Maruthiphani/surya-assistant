import 'package:flutter_test/flutter_test.dart';
import 'package:surya/models/inventory_item.dart';
import 'package:surya/services/store_matcher.dart';

InventoryItem _item(String name, {String? hint}) => InventoryItem(
      id: name,
      name: name,
      state: ItemState.needed,
      locationQuery: hint,
    );

/// Phase 7c/7d (CLAUDE.md §10): the store-likelihood heuristics are pure, so
/// they unit-test directly. These assert *category matching*, never real stock.
void main() {
  const m = StoreMatcher();

  group('categorize', () {
    test('maps keywords to the right category', () {
      expect(m.categorize('Basmati rice'), StoreCategory.grocery);
      expect(m.categorize('aspirin'), StoreCategory.pharmacy);
      expect(m.categorize('claw hammer'), StoreCategory.hardware);
      expect(m.categorize('USB charger'), StoreCategory.electronics);
      expect(m.categorize('spiral notebook'), StoreCategory.stationery);
    });

    test('unknown items default to grocery (the common list case)', () {
      expect(m.categorize('wotsit'), StoreCategory.grocery);
    });
  });

  group('resolveTarget', () {
    test('uses the explicit where-to-buy hint when present (local stores)', () {
      expect(m.resolveTarget(_item('rice', hint: 'Sai Market')), 'sai market');
      expect(m.resolveTarget(_item('rice', hint: '  Pharmacy  ')), 'pharmacy');
    });

    test('falls back to the category query from the name', () {
      expect(m.resolveTarget(_item('rice')), 'grocery store');
      expect(m.resolveTarget(_item('aspirin')), 'pharmacy');
    });

    test('strips the :: id separator from a hint', () {
      expect(m.resolveTarget(_item('x', hint: 'a::b')), 'a b');
    });
  });

  group('targetsFor / needsForTarget', () {
    final needs = [
      _item('rice'),
      _item('milk'),
      _item('aspirin'),
      _item('dosa batter', hint: 'Sai Market'),
    ];

    test('distinct targets, one per store kind', () {
      final targets = m.targetsFor(needs);
      expect(targets, containsAll(['grocery store', 'pharmacy', 'sai market']));
      expect(targets.length, 3); // rice + milk collapse to one grocery target
    });

    test('needsForTarget selects only items for that store', () {
      final grocery = m.needsForTarget(needs, 'grocery store').map((i) => i.name);
      expect(grocery, containsAll(['rice', 'milk']));
      expect(grocery, isNot(contains('aspirin')));

      final sai = m.needsForTarget(needs, 'sai market').map((i) => i.name);
      expect(sai, ['dosa batter']);
    });

    test('empty needs → no targets (so no store geofences / alerts)', () {
      expect(m.targetsFor(const []), isEmpty);
    });
  });

  group('labelFor', () {
    test('category targets read naturally', () {
      expect(m.labelFor('grocery store'), 'a grocery store');
    });

    test('named local stores are title-cased', () {
      expect(m.labelFor('sai market'), 'Sai Market');
    });
  });
}
