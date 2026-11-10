import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/inventory_item.dart';

/// Where an inventory lives. The same screens/repository serve two inventories
/// (CLAUDE.md §10 + the Personal/Family requirement): a private per-user one at
/// `users/{uid}/items`, and the shared family one at `families/{familyId}/items`.
///
/// Keeping both behind one scope means the one-tap "bought it" loop, add/edit/
/// move/delete, and the live listener are written once.
class InventoryScope {
  const InventoryScope.personal(this.id) : isFamily = false;
  const InventoryScope.family(this.id) : isFamily = true;

  /// uid for a personal inventory, familyId for a shared one.
  final String id;
  final bool isFamily;

  bool get isPersonal => !isFamily;

  @override
  bool operator ==(Object other) =>
      other is InventoryScope && other.id == id && other.isFamily == isFamily;

  @override
  int get hashCode => Object.hash(id, isFamily);
}

/// The person performing a write, captured so items carry "updated by" without
/// the UI having to read other users' profiles (forbidden by the rules).
class InventoryActor {
  const InventoryActor({required this.uid, required this.name});
  final String uid;
  final String name;
}

/// Reads/writes a shared or personal inventory (CLAUDE.md §10, Phase 7b).
///
/// Never touches reminders or any existing single-user data — purely additive.
abstract class InventoryRepository {
  /// Live item list for [scope], newest-updated first.
  Stream<List<InventoryItem>> watchItems(InventoryScope scope);

  /// Add a brand-new product to [scope] in the given [state].
  Future<void> addItem(
    InventoryScope scope, {
    required String name,
    required ItemState state,
    String? quantity,
    String? locationQuery,
    required InventoryActor actor,
  });

  /// Edit an existing product's editable fields.
  Future<void> updateItem(
    InventoryScope scope,
    String itemId, {
    String? name,
    String? quantity,
    String? locationQuery,
    required InventoryActor actor,
  });

  /// Move an item to [state]. The one-tap "bought it" action is just
  /// `moveTo(..., ItemState.present)` — because the list is shared and live,
  /// everyone sees it immediately (the anti-duplicate loop, CLAUDE.md §10).
  Future<void> moveTo(
    InventoryScope scope,
    String itemId,
    ItemState state, {
    required InventoryActor actor,
  });

  /// Permanently remove a product (an explicit action, distinct from a personal
  /// notification dismissal in Phase 7e).
  Future<void> deleteItem(InventoryScope scope, String itemId);
}

class FirestoreInventoryRepository implements InventoryRepository {
  FirestoreInventoryRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _items(InventoryScope scope) {
    final root = scope.isFamily ? 'families' : 'users';
    return _db.collection(root).doc(scope.id).collection('items');
  }

  @override
  Stream<List<InventoryItem>> watchItems(InventoryScope scope) {
    return _items(scope)
        .orderBy('lastUpdatedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map(InventoryItem.fromFirestore).toList(growable: false));
  }

  @override
  Future<void> addItem(
    InventoryScope scope, {
    required String name,
    required ItemState state,
    String? quantity,
    String? locationQuery,
    required InventoryActor actor,
  }) {
    final item = InventoryItem(
      id: '',
      name: name,
      state: state,
      quantity: quantity,
      locationQuery: locationQuery,
      updatedBy: actor.uid,
      updatedByName: actor.name,
      createdBy: actor.uid,
    );
    return _items(scope).add({
      ...item.toCreateMap(),
      'lastUpdatedAt': FieldValue.serverTimestamp(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> updateItem(
    InventoryScope scope,
    String itemId, {
    String? name,
    String? quantity,
    String? locationQuery,
    required InventoryActor actor,
  }) {
    return _items(scope).doc(itemId).set(
      {
        if (name != null) 'name': name.trim(),
        // Empty string clears the optional field.
        if (quantity != null)
          'quantity': quantity.trim().isEmpty ? FieldValue.delete() : quantity.trim(),
        if (locationQuery != null)
          'locationQuery': locationQuery.trim().isEmpty
              ? FieldValue.delete()
              : locationQuery.trim(),
        'updatedBy': actor.uid,
        'updatedByName': actor.name,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> moveTo(
    InventoryScope scope,
    String itemId,
    ItemState state, {
    required InventoryActor actor,
  }) {
    return _items(scope).doc(itemId).set(
      {
        'state': state.wire,
        'updatedBy': actor.uid,
        'updatedByName': actor.name,
        'lastUpdatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> deleteItem(InventoryScope scope, String itemId) {
    return _items(scope).doc(itemId).delete();
  }
}
