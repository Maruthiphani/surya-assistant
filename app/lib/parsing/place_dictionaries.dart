import '../models/reminder.dart';

/// Small, data-driven dictionaries for classifying a location phrase
/// (CLAUDE.md §9). Kept intentionally short — the LLM fallback covers anything
/// not listed, so we never chase an exhaustive list.
class PlaceDictionaries {
  PlaceDictionaries._();

  /// Known retail chains → dynamic ("query": match any nearby branch).
  static const Set<String> chains = {
    'costco', 'walmart', 'target', 'kroger', 'publix', 'safeway', 'aldi',
    'trader joe\'s', 'trader joes', 'whole foods', 'cvs', 'walgreens',
    'home depot', 'lowe\'s', 'lowes', 'best buy', 'ikea', 'starbucks',
    'mcdonald\'s', 'mcdonalds', 'costco wholesale',
  };

  /// Category keywords → dynamic ("query").
  static const Set<String> categories = {
    'pharmacy', 'grocery', 'grocery store', 'supermarket', 'gas station',
    'atm', 'bank', 'coffee shop', 'restaurant', 'hospital', 'gym',
    'post office', 'hardware store',
  };

  /// Saved-place keywords → specific (coordinates from the user's saved places,
  /// wired in a later phase).
  static const Set<String> savedPlaces = {'home', 'work', 'office', 'school'};

  /// Result of typing a location phrase. `unknown` means the local parser is
  /// not confident → the composer falls back to the LLM.
  static LocationTyping typeLocation(String rawPhrase) {
    var p = rawPhrase.trim().toLowerCase();
    // Strip leading articles/possessives: "a pharmacy", "the costco", "my gym".
    p = p.replaceFirst(RegExp(r'^(a|an|the|my)\s+'), '').trim();
    if (p.isEmpty) return const LocationTyping.unknown();

    if (savedPlaces.contains(p)) {
      return LocationTyping(LocationType.specific, p, isSavedPlace: true);
    }

    // A disambiguator (city/street/comma/landmark) → one specific place.
    if (RegExp(r'\s+(in|on|near|at)\s+').hasMatch(p) || p.contains(',')) {
      return LocationTyping(LocationType.specific, p);
    }

    if (chains.contains(p) || categories.contains(p)) {
      return LocationTyping(LocationType.query, p);
    }

    // Unknown single place name — let the LLM decide specific vs query.
    return const LocationTyping.unknown();
  }
}

class LocationTyping {
  const LocationTyping(this.type, this.normalized, {this.isSavedPlace = false})
      : isUnknown = false;
  const LocationTyping.unknown()
      : type = null,
        normalized = '',
        isSavedPlace = false,
        isUnknown = true;

  final LocationType? type;
  final String normalized;
  final bool isSavedPlace;
  final bool isUnknown;
}
