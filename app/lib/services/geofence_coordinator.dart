import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../models/reminder.dart';
import '../models/user_profile.dart';
import '../providers/providers.dart';
import 'location_service.dart';

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
  }

  final Ref _ref;
  StreamSubscription<String>? _enterSub;
  StreamSubscription<({double lat, double lng})>? _locSub;

  ({double lat, double lng})? _lastSyncLatLng;

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

    final capped = _capToNearest(specs, here);
    await _location.syncGeofences(capped);
  }

  /// Keep only the nearest [_maxGeofencesTotal] geofences (OS region budget).
  List<GeofenceSpec> _capToNearest(
      List<GeofenceSpec> specs, ({double lat, double lng})? here) {
    if (specs.length <= _maxGeofencesTotal) return specs;
    if (here != null) {
      specs.sort((a, b) => geo.Geolocator.distanceBetween(
                  here.lat, here.lng, a.lat, a.lng)
          .compareTo(
              geo.Geolocator.distanceBetween(here.lat, here.lng, b.lat, b.lng)));
    }
    debugPrint(
        'Geofence budget: keeping nearest $_maxGeofencesTotal of ${specs.length}.');
    return specs.sublist(0, _maxGeofencesTotal);
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
        .showReminderTriggered(reminder, assistantName);
    await _ref
        .read(reminderRepositoryProvider)
        .updateStatus(uid, reminderId, ReminderStatus.triggered);
  }

  void dispose() {
    _enterSub?.cancel();
    _locSub?.cancel();
  }
}
