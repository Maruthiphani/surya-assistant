import 'package:cloud_firestore/cloud_firestore.dart';

/// Which of the two shared lists an item sits in (CLAUDE.md §10). The two lists
/// are two *states* of one product, so moving an item between lists is just a
/// state change (this is what makes the one-tap "bought it" loop cheap).
enum ItemState {
  /// Already at home (Present Items).
  present,

  /// Still to be bought (Need to Buy).
  needed,
}

extension ItemStateWire on ItemState {
  /// The value stored in Firestore.
  String get wire => name; // "present" | "needed"

  static ItemState fromWire(String? value) {
    switch (value) {
      case 'present':
        return ItemState.present;
      case 'needed':
        return ItemState.needed;
      default:
        // Backward/forward compatible default: unknown → needed (so a mis-written
        // item still surfaces on the actionable list rather than disappearing).
        return ItemState.needed;
    }
  }
}

/// One product in a shared inventory, living at either
/// `families/{familyId}/items/{itemId}` (shared) or `users/{uid}/items/{itemId}`
/// (personal). Pure data class, mirroring the Reminder/Family convention.
///
/// `updatedBy` is the uid of the last editor; `updatedByName` is a denormalised
/// display name so the UI can show "Updated … by Asha" without reading other
/// users' profiles (which the security rules forbid). CLAUDE.md §10.
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.state,
    this.quantity,
    this.locationQuery,
    this.updatedBy,
    this.updatedByName,
    this.createdBy,
    this.lastUpdatedAt,
    this.createdAt,
  });

  final String id;

  /// Product name, e.g. "rice". Display + the key used for duplicate detection.
  final String name;

  final ItemState state;

  /// Free-text quantity, optional, e.g. "2 bags".
  final String? quantity;

  /// Optional category/chain hint for store matching, e.g. "grocery store"
  /// (reused by the Phase 7c/7d location path). Null = no hint.
  final String? locationQuery;

  /// uid of the member who last changed this item.
  final String? updatedBy;

  /// Denormalised display name of [updatedBy] for the "Updated by" label.
  final String? updatedByName;

  /// uid of the member who first added the item.
  final String? createdBy;

  final DateTime? lastUpdatedAt;
  final DateTime? createdAt;

  bool get isNeeded => state == ItemState.needed;
  bool get isPresent => state == ItemState.present;

  /// Normalised key for duplicate detection (case/space-insensitive).
  String get dedupeKey => name.trim().toLowerCase();

  InventoryItem copyWith({
    String? name,
    ItemState? state,
    String? quantity,
    String? locationQuery,
    String? updatedBy,
    String? updatedByName,
  }) {
    return InventoryItem(
      id: id,
      name: name ?? this.name,
      state: state ?? this.state,
      quantity: quantity ?? this.quantity,
      locationQuery: locationQuery ?? this.locationQuery,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
      createdBy: createdBy,
      lastUpdatedAt: lastUpdatedAt,
      createdAt: createdAt,
    );
  }

  factory InventoryItem.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    return InventoryItem(
      id: doc.id,
      name: ((data['name'] as String?) ?? '').trim(),
      state: ItemStateWire.fromWire(data['state'] as String?),
      quantity: (data['quantity'] as String?)?.trim().isNotEmpty == true
          ? (data['quantity'] as String).trim()
          : null,
      locationQuery:
          (data['locationQuery'] as String?)?.trim().isNotEmpty == true
              ? (data['locationQuery'] as String).trim()
              : null,
      updatedBy: data['updatedBy'] as String?,
      updatedByName: (data['updatedByName'] as String?)?.trim().isNotEmpty == true
          ? (data['updatedByName'] as String).trim()
          : null,
      createdBy: data['createdBy'] as String?,
      lastUpdatedAt: (data['lastUpdatedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Payload for a fresh item (create). `lastUpdatedAt`/`createdAt` use server
  /// timestamps, injected by the repository.
  Map<String, dynamic> toCreateMap() => {
        'name': name.trim(),
        'state': state.wire,
        if (quantity != null && quantity!.trim().isNotEmpty)
          'quantity': quantity!.trim(),
        if (locationQuery != null && locationQuery!.trim().isNotEmpty)
          'locationQuery': locationQuery!.trim(),
        'updatedBy': updatedBy,
        'updatedByName': updatedByName,
        'createdBy': createdBy ?? updatedBy,
      };
}
