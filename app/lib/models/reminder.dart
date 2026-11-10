import 'package:cloud_firestore/cloud_firestore.dart';

import 'recurrence.dart';

/// Lifecycle of a location reminder.
///
/// Stored in Firestore as the lowercase enum name (e.g. "active"). Only
/// [active] reminders have live geofences; once a reminder leaves [active] it
/// must never fire again (CLAUDE.md §5 — idempotent triggers).
enum ReminderStatus {
  active,
  triggered,
  completed,
  cancelled;

  static ReminderStatus fromName(String? value) {
    return ReminderStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ReminderStatus.active,
    );
  }
}

/// Whether a reminder targets one fixed place or any branch of a chain/category
/// (CLAUDE.md §1, §4).
///
/// - [specific]: a named place ("Costco in Cumming") → one fixed lat/lng.
/// - [query]:    a chain/category ("Costco", "pharmacy") → match ANY nearby
///   branch discovered at runtime; `lat`/`lng` are null.
enum LocationType {
  specific,
  query;

  static LocationType fromName(String? value) {
    return LocationType.values.firstWhere(
      (t) => t.name == value,
      // Fallback below is applied by Reminder.fromFirestore for legacy docs.
      orElse: () => LocationType.specific,
    );
  }
}

/// A single location reminder → a document under
/// `users/{uid}/reminders/{reminderId}` (CLAUDE.md §4).
class Reminder {
  const Reminder({
    this.id,
    required this.task,
    required this.locationName,
    this.locationType = LocationType.query,
    this.locationQuery,
    this.address,
    this.lat,
    this.lng,
    this.radiusMeters = 500,
    this.remindAt,
    this.recurrence = Recurrence.none,
    this.status = ReminderStatus.active,
    this.createdAt,
    this.triggeredAt,
    this.completedAt,
  });

  final String? id;

  final String task; // e.g. "buy rice"
  final String locationName; // display label, e.g. "Costco" / "Costco, Cumming"

  final LocationType locationType;

  /// For [LocationType.query]: the search term used to discover branches.
  final String? locationQuery;

  /// For [LocationType.specific] only:
  final String? address;
  final double? lat;
  final double? lng;

  final int radiusMeters; // default 500 m (§4)

  /// Scheduled fire time, if the reminder is time-based (Phase 8). For a
  /// recurring reminder this is the anchor occurrence; the scheduler computes
  /// the next future fire from it + [recurrence].
  final DateTime? remindAt;

  /// How a time-based reminder repeats (Phase 8). [Recurrence.none] = one-shot.
  final Recurrence recurrence;

  final ReminderStatus status;

  final DateTime? createdAt;
  final DateTime? triggeredAt;
  final DateTime? completedAt;

  bool get isDynamic => locationType == LocationType.query;

  /// Fires on a schedule (Phase 8) — has a time.
  bool get isTimeScheduled => remindAt != null;

  /// Fires on arrival — has a usable location trigger. A time-only reminder
  /// (e.g. a birthday) has none, so the geofence path skips it.
  bool get hasLocationTrigger {
    if (locationType == LocationType.specific) {
      return lat != null && lng != null;
    }
    return (locationQuery?.trim().isNotEmpty ?? false) ||
        locationName.trim().isNotEmpty;
  }

  factory Reminder.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();

    // Backward compatibility: legacy docs have no locationType. If they carry
    // coordinates, treat them as specific; otherwise query.
    final rawType = data['locationType'] as String?;
    final type = rawType != null
        ? LocationType.fromName(rawType)
        : (lat != null && lng != null
            ? LocationType.specific
            : LocationType.query);

    return Reminder(
      id: doc.id,
      task: (data['task'] as String?) ?? '',
      locationName: (data['locationName'] as String?) ?? '',
      locationType: type,
      locationQuery: data['locationQuery'] as String?,
      address: data['address'] as String?,
      lat: lat,
      lng: lng,
      radiusMeters: (data['radiusMeters'] as num?)?.toInt() ?? 500,
      remindAt: (data['remindAt'] as Timestamp?)?.toDate(),
      recurrence: Recurrence.fromName(data['recurrence'] as String?),
      status: ReminderStatus.fromName(data['status'] as String?),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      triggeredAt: (data['triggeredAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Serialize user-editable fields. Timestamps are set by the repository with
  /// `FieldValue.serverTimestamp()`. Null location fields are omitted.
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'task': task,
      'locationName': locationName,
      'locationType': locationType.name,
      'radiusMeters': radiusMeters,
      'status': status.name,
    };
    if (locationQuery != null) map['locationQuery'] = locationQuery;
    if (address != null) map['address'] = address;
    if (lat != null) map['lat'] = lat;
    if (lng != null) map['lng'] = lng;
    if (remindAt != null) map['remindAt'] = Timestamp.fromDate(remindAt!);
    if (recurrence != Recurrence.none) map['recurrence'] = recurrence.name;
    return map;
  }

  Reminder copyWith({
    String? id,
    String? task,
    String? locationName,
    LocationType? locationType,
    String? locationQuery,
    String? address,
    double? lat,
    double? lng,
    int? radiusMeters,
    DateTime? remindAt,
    Recurrence? recurrence,
    ReminderStatus? status,
    DateTime? createdAt,
    DateTime? triggeredAt,
    DateTime? completedAt,
  }) {
    return Reminder(
      id: id ?? this.id,
      task: task ?? this.task,
      locationName: locationName ?? this.locationName,
      locationType: locationType ?? this.locationType,
      locationQuery: locationQuery ?? this.locationQuery,
      address: address ?? this.address,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      remindAt: remindAt ?? this.remindAt,
      recurrence: recurrence ?? this.recurrence,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      triggeredAt: triggeredAt ?? this.triggeredAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }
}
