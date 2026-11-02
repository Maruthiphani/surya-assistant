import 'dart:async';

import 'package:geofence_service/geofence_service.dart';
// Prefixed: geolocator and fl_location (re-exported by geofence_service) both
// declare LocationPermission/LocationAccuracy, which would otherwise clash.
import 'package:geolocator/geolocator.dart' as geo;

/// How much location access the user has granted.
enum LocationPermissionLevel { denied, whileInUse, always }

/// One geofence to monitor. For a dynamic reminder, several specs share the same
/// reminder but different ids (reminderId + branch suffix) and coordinates.
class GeofenceSpec {
  const GeofenceSpec({
    required this.id,
    required this.lat,
    required this.lng,
    required this.radiusMeters,
  });

  final String id;
  final double lat;
  final double lng;
  final int radiusMeters;
}

/// Owns OS location permissions and the geofence engine. It registers whatever
/// set of [GeofenceSpec]s it is given (the coordinator decides which, resolving
/// dynamic reminders to nearby branches). ENTER events surface via [onEnter];
/// coarse location updates via [onLocation] (used to trigger refresh — NOT a GPS
/// loop; geofence_service samples at an interval).
abstract class LocationService {
  Future<LocationPermissionLevel> checkPermission();
  Future<LocationPermissionLevel> requestWhenInUse();
  Future<LocationPermissionLevel> requestAlways();
  Future<bool> isLocationServiceEnabled();
  Future<void> openAppSettings();

  Future<void> start();
  Future<void> stop();

  /// Replace the monitored geofences with exactly [specs].
  Future<void> syncGeofences(List<GeofenceSpec> specs);

  /// Best-effort current location (for discovering nearby branches).
  Future<({double lat, double lng})?> currentLatLng();

  /// Emits the geofence id that was just ENTERed.
  Stream<String> get onEnter;

  /// Emits coarse location updates (for movement-based refresh).
  Stream<({double lat, double lng})> get onLocation;
}

class GeofenceLocationService implements LocationService {
  GeofenceLocationService() {
    _service = GeofenceService.instance.setup(
      interval: 5000,
      accuracy: 100,
      statusChangeDelayMs: 10000,
      useActivityRecognition: false,
      allowMockLocations: true, // so emulator `adb emu geo fix` works
      printDevLog: false,
    );
  }

  late final GeofenceService _service;
  final _enterController = StreamController<String>.broadcast();
  final _locationController =
      StreamController<({double lat, double lng})>.broadcast();
  bool _running = false;

  @override
  Stream<String> get onEnter => _enterController.stream;

  @override
  Stream<({double lat, double lng})> get onLocation =>
      _locationController.stream;

  // --- Permissions ----------------------------------------------------------

  LocationPermissionLevel _map(geo.LocationPermission p) {
    switch (p) {
      case geo.LocationPermission.always:
        return LocationPermissionLevel.always;
      case geo.LocationPermission.whileInUse:
        return LocationPermissionLevel.whileInUse;
      case geo.LocationPermission.denied:
      case geo.LocationPermission.deniedForever:
      case geo.LocationPermission.unableToDetermine:
        return LocationPermissionLevel.denied;
    }
  }

  @override
  Future<LocationPermissionLevel> checkPermission() async =>
      _map(await geo.Geolocator.checkPermission());

  @override
  Future<LocationPermissionLevel> requestWhenInUse() async {
    var p = await geo.Geolocator.checkPermission();
    if (p == geo.LocationPermission.denied) {
      p = await geo.Geolocator.requestPermission();
    }
    return _map(p);
  }

  @override
  Future<LocationPermissionLevel> requestAlways() async {
    final p = await geo.Geolocator.requestPermission();
    return _map(p);
  }

  @override
  Future<bool> isLocationServiceEnabled() =>
      geo.Geolocator.isLocationServiceEnabled();

  @override
  Future<void> openAppSettings() => geo.Geolocator.openAppSettings();

  @override
  Future<({double lat, double lng})?> currentLatLng() async {
    try {
      final last = await geo.Geolocator.getLastKnownPosition();
      if (last != null) return (lat: last.latitude, lng: last.longitude);
      final pos = await geo.Geolocator.getCurrentPosition();
      return (lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  // --- Geofencing -----------------------------------------------------------

  @override
  Future<void> start() async {
    if (_running) return;
    _service.addGeofenceStatusChangeListener(_onStatusChanged);
    _service.addLocationChangeListener(_onLocationChanged);
    await _service.start();
    _running = true;
  }

  @override
  Future<void> stop() async {
    if (!_running) return;
    _service.removeGeofenceStatusChangeListener(_onStatusChanged);
    _service.removeLocationChangeListener(_onLocationChanged);
    await _service.stop();
    _running = false;
  }

  @override
  Future<void> syncGeofences(List<GeofenceSpec> specs) async {
    _service.clearGeofenceList();
    _service.addGeofenceList([
      for (final s in specs)
        Geofence(
          id: s.id,
          latitude: s.lat,
          longitude: s.lng,
          radius: [GeofenceRadius(id: 'r', length: s.radiusMeters.toDouble())],
        ),
    ]);
  }

  Future<void> _onStatusChanged(
    Geofence geofence,
    GeofenceRadius geofenceRadius,
    GeofenceStatus geofenceStatus,
    Location location,
  ) async {
    if (geofenceStatus == GeofenceStatus.ENTER) {
      _enterController.add(geofence.id);
    }
  }

  void _onLocationChanged(Location location) {
    _locationController.add((lat: location.latitude, lng: location.longitude));
  }
}
