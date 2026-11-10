import 'package:flutter_test/flutter_test.dart';
import 'package:surya/models/inventory_item.dart';
import 'package:surya/services/inventory_repository.dart';

/// Phase 7b (CLAUDE.md §10): unit-tests the pure inventory logic — item state
/// wire-format, create payload, copyWith, duplicate key, and the scope value
/// object. The Firestore-backed repository (like the other repos) is exercised
/// on-device, not here.
void main() {
  group('ItemState wire format', () {
    test('round-trips present/needed', () {
      expect(ItemState.present.wire, 'present');
      expect(ItemState.needed.wire, 'needed');
      expect(ItemStateWire.fromWire('present'), ItemState.present);
      expect(ItemStateWire.fromWire('needed'), ItemState.needed);
    });

    test('unknown/null falls back to needed (item stays actionable)', () {
      expect(ItemStateWire.fromWire(null), ItemState.needed);
      expect(ItemStateWire.fromWire('garbage'), ItemState.needed);
    });
  });

  group('InventoryItem', () {
    const item = InventoryItem(
      id: 'i1',
      name: 'rice',
      state: ItemState.needed,
      quantity: '2 bags',
      locationQuery: 'grocery store',
      updatedBy: 'u1',
      updatedByName: 'Asha',
    );

    test('isNeeded/isPresent reflect state', () {
      expect(item.isNeeded, isTrue);
      expect(item.isPresent, isFalse);
      expect(item.copyWith(state: ItemState.present).isPresent, isTrue);
    });

    test('dedupeKey is trimmed + lowercased', () {
      expect(const InventoryItem(id: 'x', name: '  Rice  ', state: ItemState.needed)
          .dedupeKey, 'rice');
    });

    test('toCreateMap carries fields and defaults createdBy to the actor', () {
      final map = item.toCreateMap();
      expect(map['name'], 'rice');
      expect(map['state'], 'needed');
      expect(map['quantity'], '2 bags');
      expect(map['locationQuery'], 'grocery store');
      expect(map['updatedBy'], 'u1');
      expect(map['updatedByName'], 'Asha');
      expect(map['createdBy'], 'u1'); // falls back to updatedBy
      // The repository injects server timestamps — not in the model payload.
      expect(map.containsKey('lastUpdatedAt'), isFalse);
    });

    test('toCreateMap omits empty optional fields', () {
      const bare = InventoryItem(
        id: 'i2',
        name: 'milk',
        state: ItemState.present,
        updatedBy: 'u1',
      );
      final map = bare.toCreateMap();
      expect(map.containsKey('quantity'), isFalse);
      expect(map.containsKey('locationQuery'), isFalse);
    });

    test('copyWith preserves identity fields', () {
      final moved = item.copyWith(state: ItemState.present, updatedByName: 'Ravi');
      expect(moved.id, 'i1');
      expect(moved.createdBy, item.createdBy);
      expect(moved.updatedByName, 'Ravi');
      expect(moved.name, 'rice');
    });
  });

  group('InventoryScope', () {
    test('personal vs family carry the right flags and id', () {
      const personal = InventoryScope.personal('u1');
      const family = InventoryScope.family('f1');
      expect(personal.isPersonal, isTrue);
      expect(personal.isFamily, isFalse);
      expect(personal.id, 'u1');
      expect(family.isFamily, isTrue);
      expect(family.id, 'f1');
    });

    test('equality distinguishes personal and family with the same id', () {
      expect(const InventoryScope.personal('x'),
          equals(const InventoryScope.personal('x')));
      expect(const InventoryScope.personal('x'),
          isNot(equals(const InventoryScope.family('x'))));
    });
  });
}
