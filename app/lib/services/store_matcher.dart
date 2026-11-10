import '../models/inventory_item.dart';

/// Rough store category for an item. This is **store-likelihood, not real
/// stock** (CLAUDE.md §10, #6): a grocery store *likely* has rice; it is never a
/// claim about actual inventory. Deliberately tiny and data-driven (the §9
/// philosophy) — the goal is to geofence the right *kind* of store, not to be
/// exhaustive.
enum StoreCategory { grocery, pharmacy, hardware, electronics, stationery }

/// Decides which kind of store a needed item points at, and whether a store of a
/// given category is likely to carry it. Pure/stateless so it unit-tests cleanly
/// and runs on-device with no network (the Places call to find branches is the
/// coordinator's job).
class StoreMatcher {
  const StoreMatcher();

  /// Keyword → category. First match wins; unknown words fall back to grocery
  /// (the common case for a household shopping list).
  static const Map<StoreCategory, List<String>> _keywords = {
    StoreCategory.grocery: [
      'rice', 'milk', 'egg', 'bread', 'vegetable', 'veg', 'fruit', 'sugar',
      'salt', 'flour', 'atta', 'oil', 'butter', 'cheese', 'yogurt', 'curd',
      'paneer', 'chicken', 'meat', 'fish', 'onion', 'tomato', 'potato',
      'cereal', 'coffee', 'tea', 'water', 'snack', 'dal', 'lentil', 'spice',
      'masala', 'biscuit', 'juice',
    ],
    StoreCategory.pharmacy: [
      'medicine', 'medication', 'aspirin', 'paracetamol', 'tablet', 'pill',
      'bandage', 'vitamin', 'prescription', 'syrup', 'toothpaste', 'shampoo',
      'soap', 'sanitizer', 'ointment',
    ],
    StoreCategory.hardware: [
      'nail', 'screw', 'hammer', 'paint', 'tool', 'bulb', 'wire', 'tape',
      'drill', 'plywood', 'cement', 'pipe',
    ],
    StoreCategory.electronics: [
      'charger', 'cable', 'headphone', 'earphone', 'mouse', 'keyboard', 'hdmi',
      'laptop', 'phone', 'adapter', 'battery',
    ],
    StoreCategory.stationery: [
      'pen', 'pencil', 'notebook', 'paper', 'stapler', 'marker', 'eraser',
      'envelope', 'glue',
    ],
  };

  /// A Places text-search query for each category (used by /v1/nearby to find
  /// nearby branches to geofence).
  static const Map<StoreCategory, String> _categoryQuery = {
    StoreCategory.grocery: 'grocery store',
    StoreCategory.pharmacy: 'pharmacy',
    StoreCategory.hardware: 'hardware store',
    StoreCategory.electronics: 'electronics store',
    StoreCategory.stationery: 'stationery store',
  };

  /// Classify an item name into a store category. Defaults to grocery.
  StoreCategory categorize(String itemName) {
    final n = itemName.toLowerCase();
    for (final entry in _keywords.entries) {
      for (final kw in entry.value) {
        if (n.contains(kw)) return entry.key;
      }
    }
    return StoreCategory.grocery;
  }

  /// The store "target" a needed item should geofence: the item's explicit
  /// where-to-buy hint if given (e.g. "Sai Market", "pharmacy" — this is how
  /// local/regional stores are supported, §10 #4), otherwise the category query
  /// derived from the name. Normalised so it can key a geofence id and be
  /// compared on ENTER.
  String resolveTarget(InventoryItem item) {
    final hint = item.locationQuery?.trim();
    if (hint != null && hint.isNotEmpty) return _normalize(hint);
    return _normalize(_categoryQuery[categorize(item.name)]!);
  }

  /// All distinct store targets for a set of needed items — one /v1/nearby query
  /// each. Empty in → empty out (so no store geofences when nothing is needed).
  Set<String> targetsFor(Iterable<InventoryItem> needed) {
    return needed.map(resolveTarget).toSet();
  }

  /// The needed items relevant to a store with the given [targetKey] — i.e. the
  /// items that resolve to this store. Recomputed from the live list on ENTER so
  /// it's never stale.
  List<InventoryItem> needsForTarget(
    Iterable<InventoryItem> needed,
    String targetKey,
  ) {
    return needed.where((i) => resolveTarget(i) == targetKey).toList();
  }

  /// Human label for a target key in a notification ("a grocery store", or a
  /// named local store as typed).
  String labelFor(String targetKey) {
    final isCategory = _categoryQuery.values.any((q) => _normalize(q) == targetKey);
    if (isCategory) return 'a $targetKey';
    // A specific/local store name — title-case the words for display.
    return targetKey
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  /// Lowercase, collapse whitespace, and drop the `::` used as a geofence-id
  /// separator so a target can be embedded in an id safely.
  static String _normalize(String s) {
    return s
        .toLowerCase()
        .replaceAll('::', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
