import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../models/inventory_item.dart';
import '../models/reminder.dart';
import '../models/user_profile.dart';
import '../providers/providers.dart';
import 'location_service.dart';
import 'notification_service.dart';
import 'store_matcher.dart';

/// Glue between geofence ENTER events, place discovery, notifications and the
/// repository.
///
/// - Specific reminders → one geofence at their fixed coordinates.
/// - Dynamic (query) reminders → discover nearby branches via the backend and
///   register one geofence per branch; the geofence id is `reminderId::index`
///   so an ENTER maps back to the reminder. A dynamic reminder fires once on
///   entering ANY branch (idempotent, §5).
/// - Branch sets refresh when the user moves beyond [_refreshThresholdM],
///   driven by coarse location updates (not a GPS loop).
class GeofenceCoordinator {
  GeofenceCoordinator(this._ref) {
    final location = _ref.read(locationServiceProvider);
    _enterSub = location.onEnter.listen(_handleEnter);
    _locSub = location.onLocation.listen(_onLocation);
    // Wire the notification "Bought" action back to the inventory (Phase 7c).
    _ref.read(notificationServiceProvider).setActionHandler(_handleAction);
  }

  final Ref _ref;
  StreamSubscription<String>? _enterSub;
  StreamSubscription<({double lat, double lng})>? _locSub;

  ({double lat, double lng})? _lastSyncLatLng;

  /// Prefix marking a geofence that wraps a store (vs a reminder). Id shape:
  /// `store::<targetKey>::<branchIndex>` (Phase 7c/7d).
  static const String _storePrefix = 'store';

  /// Per-store-geofence dedupe: don't re-alert the same monitored store within
  /// this window while the user lingers / re-enters (CLAUDE.md §10 relevance).
  static const Duration _storeAlertWindow = Duration(minutes: 30);
  final Map<String, DateTime> _lastStoreAlert = {};

  final StoreMatcher _matcher = const StoreMatcher();

  // Keep within OS limits. iOS monitors ≤ 20 regions app-wide; Android allows
  // ~100 per app. We stay safely under each (CLAUDE.md §5).
  static const int _maxGeofencesIos = 20;
  static const int _maxGeofencesAndroid = 90;
  static const int _maxBranchesPerReminder = 10;
  static const int _discoveryRadiusM = 30000;
  static const double _refreshThresholdM = 2000;

  /// Platform-aware app-wide geofence budget. Defaults to the stricter iOS
  /// limit on anything that isn't Android (also safest for tests/desktop).
  static int get _maxGeofencesTotal {
    try {
      return Platform.isAndroid ? _maxGeofencesAndroid : _maxGeofencesIos;
    } catch (_) {
      // Platform may be unavailable (e.g. pure Dart test host) — be safe.
      return _maxGeofencesIos;
    }
  }

  LocationService get _location => _ref.read(locationServiceProvider);

  Future<bool> startTrackingIfPermitted() async {
    final level = await _location.checkPermission();
    if (level == LocationPermissionLevel.denied) return false;
    try {
      await _location.start();
      await syncActiveReminders();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Rebuild the geofence set from the current active reminders.
  Future<void> syncActiveReminders() async {
    final list = _ref.read(remindersProvider).valueOrNull ?? const <Reminder>[];
    final active =
        list.where((r) => r.status == ReminderStatus.active).toList();

    final here = await _location.currentLatLng();
    _lastSyncLatLng = here;

    final specs = <GeofenceSpec>[];
    for (final r in active) {
      if (r.id == null) continue;
      // Time-only reminders (e.g. birthdays) have no location trigger — the
      // scheduler handles them, the geofence path skips them (Phase 8).
      if (!r.hasLocationTrigger) continue;
      if (r.locationType == LocationType.specific) {
        if (r.lat != null && r.lng != null) {
          specs.add(GeofenceSpec(
            id: r.id!, lat: r.lat!, lng: r.lng!, radiusMeters: r.radiusMeters));
        }
      } else {
        // Dynamic: discover nearby branches (needs current location + backend).
        if (here == null) continue;
        final query = r.locationQuery ?? r.locationName;
        try {
          final branches = await _ref.read(aiServiceProvider).nearby(
                query, here.lat, here.lng,
                radiusMeters: _discoveryRadiusM,
                limit: _maxBranchesPerReminder,
              );
          for (var i = 0; i < branches.length; i++) {
            specs.add(GeofenceSpec(
              id: '${r.id}::$i',
              lat: branches[i].lat,
              lng: branches[i].lng,
              radiusMeters: r.radiusMeters,
            ));
          }
        } catch (e) {
          // Places not configured / unreachable — skip discovery for now.
          debugPrint('nearby discovery failed for "$query": $e');
        }
      }
    }

    // Reminders take priority in the OS region budget; store geofences (Phase
    // 7c/7d) fill whatever remains, nearest-first.
    final cappedReminders = _capToNearest(specs, here, _maxGeofencesTotal);
    final remaining = _maxGeofencesTotal - cappedReminders.length;
    final storeSpecs =
        remaining <= 0 ? <GeofenceSpec>[] : await _buildStoreSpecs(here);
    final cappedStores = _capToNearest(storeSpecs, here, remaining);

    await _location.syncGeofences([...cappedReminders, ...cappedStores]);
  }

  /// Build geofences around stores that likely carry a currently-needed item
  /// (Phase 7c/7d). Reuses the dynamic `/v1/nearby` discovery: each distinct
  /// store target (explicit hint or derived category) becomes one query, and
  /// each nearby branch a geofence with id `store::<targetKey>::<index>`.
  ///
  /// Empty when nothing is needed or we can't discover branches — so there are
  /// no store geofences (and so no alerts) unless the list is non-empty.
  Future<List<GeofenceSpec>> _buildStoreSpecs(
      ({double lat, double lng})? here) async {
    if (here == null) return const [];
    final needs = _ref.read(geofenceNeedsProvider);
    if (needs.isEmpty) return const [];

    final targets = _matcher.targetsFor(needs.map((n) => n.item));
    final specs = <GeofenceSpec>[];
    for (final target in targets) {
      try {
        final branches = await _ref.read(aiServiceProvider).nearby(
              target, here.lat, here.lng,
              radiusMeters: _discoveryRadiusM,
              limit: _maxBranchesPerReminder,
            );
        for (var i = 0; i < branches.length; i++) {
          specs.add(GeofenceSpec(
            id: '$_storePrefix::$target::$i',
            lat: branches[i].lat,
            lng: branches[i].lng,
            radiusMeters: UserProfile.defaultRadius,
          ));
        }
      } catch (e) {
        debugPrint('store discovery failed for "$target": $e');
      }
    }
    return specs;
  }

  /// Keep only the nearest [limit] geofences (OS region budget).
  List<GeofenceSpec> _capToNearest(
      List<GeofenceSpec> specs, ({double lat, double lng})? here, int limit) {
    if (specs.length <= limit) return specs;
    if (here != null) {
      specs.sort((a, b) => geo.Geolocator.distanceBetween(
                  here.lat, here.lng, a.lat, a.lng)
          .compareTo(
              geo.Geolocator.distanceBetween(here.lat, here.lng, b.lat, b.lng)));
    }
    debugPrint('Geofence budget: keeping nearest $limit of ${specs.length}.');
    return specs.sublist(0, limit);
  }

  void _onLocation(({double lat, double lng}) loc) {
    final last = _lastSyncLatLng;
    if (last == null) {
      _lastSyncLatLng = loc;
      return;
    }
    final moved =
        geo.Geolocator.distanceBetween(last.lat, last.lng, loc.lat, loc.lng);
    if (moved >= _refreshThresholdM) {
      _lastSyncLatLng = loc;
      syncActiveReminders(); // re-discover branches around the new area
    }
  }

  /// Simulate a geofence ENTER (debug screen) — accepts a reminder id.
  Future<void> simulateEnter(String reminderId) => _handleEnter(reminderId);

  Future<void> _handleEnter(String geofenceId) async {
    // Store geofences (Phase 7c) use a distinct id namespace and fire a
    // needs-summary alert rather than triggering a reminder.
    if (geofenceId.startsWith('$_storePrefix::')) {
      await _handleStoreEnter(geofenceId);
      return;
    }

    // Composite ids for dynamic branches are "reminderId::index".
    final reminderId = geofenceId.split('::').first;

    final uid = _ref.read(currentUidProvider);
    if (uid == null) return;

    final list = _ref.read(remindersProvider).valueOrNull ?? const <Reminder>[];
    Reminder? reminder;
    for (final r in list) {
      if (r.id == reminderId) {
        reminder = r;
        break;
      }
    }

    // Idempotent: unknown or already-handled → ignore (fires once per reminder,
    // even if several branch geofences trigger).
    if (reminder == null || reminder.status != ReminderStatus.active) return;

    final assistantName =
        _ref.read(userProfileProvider).valueOrNull?.assistantName ??
            UserProfile.defaultAssistantName;

    await _ref
        .read(notificationServiceProvider)
        .showReminderTriggered(reminder, assistantName,
            strings: _ref.read(stringsProvider));
    await _ref
        .read(reminderRepositoryProvider)
        .updateStatus(uid, reminderId, ReminderStatus.triggered);
  }

  /// A member reached a store likely to carry needed items (Phase 7c). Alerts
  /// only the member physically there (this fires on *their* device), only when
  /// the needs list for this store is non-empty, and dedupes repeat entries to
  /// the same monitored store within [_storeAlertWindow].
  Future<void> _handleStoreEnter(String geofenceId) async {
    final parts = geofenceId.split('::');
    if (parts.length < 2) return;
    final targetKey = parts[1];

    // Dedupe: ignore re-entries/lingering within the window.
    final last = _lastStoreAlert[geofenceId];
    final now = DateTime.now();
    if (last != null && now.difference(last) < _storeAlertWindow) return;

    final needs = _ref.read(geofenceNeedsProvider);
    final matching = _matcher
        .needsForTarget(needs.map((n) => n.item), targetKey)
        .map((i) => i.name)
        .toList();
    if (matching.isEmpty) return; // nothing relevant here → no notification

    // "Already home" line (anti-duplicate goal): present items for this store.
    final present = _allItems()
        .where((i) => i.isPresent && _matcher.resolveTarget(i) == targetKey)
        .map((i) => i.name)
        .toList();

    _lastStoreAlert[geofenceId] = now;

    final assistantName =
        _ref.read(userProfileProvider).valueOrNull?.assistantName ??
            UserProfile.defaultAssistantName;

    await _ref.read(notificationServiceProvider).showStoreNeeds(
          assistantName: assistantName,
          storeLabel: _matcher.labelFor(targetKey),
          neededNames: matching,
          presentNames: present,
          payload: targetKey, // the action recomputes matches live from this
        );
  }

  /// One-tap "Bought" from a store-needs notification (Phase 7c): flip every
  /// needed item for that store to present, each in its own inventory scope.
  /// Recomputed from the live list via the payload so it's never stale.
  Future<void> _handleAction(String? actionId, String? payload) async {
    if (actionId != LocalNotificationService.boughtActionId) return;
    final targetKey = payload;
    if (targetKey == null || targetKey.isEmpty) return;

    final actor = _ref.read(inventoryActorProvider);
    if (actor == null) return;
    final repo = _ref.read(inventoryRepositoryProvider);

    final needs = _ref.read(geofenceNeedsProvider);
    for (final scoped in needs) {
      if (_matcher.resolveTarget(scoped.item) == targetKey) {
        await repo.moveTo(scoped.scope, scoped.item.id, ItemState.present,
            actor: actor);
      }
    }
  }

  /// Current items across the personal + family inventories (for the present
  /// "already home" line).
  List<InventoryItem> _allItems() {
    final personal =
        _ref.read(personalInventoryItemsProvider).valueOrNull ?? const [];
    final family =
        _ref.read(familyInventoryItemsProvider).valueOrNull ?? const [];
    return [...personal, ...family];
  }

  void dispose() {
    _ref.read(notificationServiceProvider).setActionHandler(null);
    _enterSub?.cancel();
    _locSub?.cancel();
  }
}
