import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/location_service.dart';

/// Guided location-permission flow (CLAUDE.md §5): ask for **When In Use**
/// first, then show an explanation of why background ("Always") access is needed
/// before requesting it. Starts the geofence engine once permission is granted.
class LocationPermissionScreen extends ConsumerStatefulWidget {
  const LocationPermissionScreen({super.key});

  @override
  ConsumerState<LocationPermissionScreen> createState() =>
      _LocationPermissionScreenState();
}

enum _Step { intro, explainAlways }

class _LocationPermissionScreenState
    extends ConsumerState<LocationPermissionScreen> {
  _Step _step = _Step.intro;
  bool _busy = false;

  LocationService get _location => ref.read(locationServiceProvider);

  Future<void> _requestWhenInUse() async {
    setState(() => _busy = true);
    final level = await _location.requestWhenInUse();
    setState(() => _busy = false);
    if (!mounted) return;
    if (level == LocationPermissionLevel.denied) {
      _snack('Location permission is needed for reminders to work.');
      return;
    }
    // Got at least When-In-Use → explain why we also want Always.
    setState(() => _step = _Step.explainAlways);
  }

  Future<void> _requestAlways() async {
    setState(() => _busy = true);
    final level = await _location.requestAlways();
    setState(() => _busy = false);
    if (!mounted) return;
    if (level != LocationPermissionLevel.always) {
      // Many Android versions only grant "Always" from settings.
      _snack('To fire reminders in the background, choose "Allow all the time" '
          'in settings.');
    }
    await _finish();
  }

  /// Continue with whatever was granted (When-In-Use is enough for foreground).
  Future<void> _finish() async {
    await ref.read(geofenceCoordinatorProvider).startTrackingIfPermitted();
    if (mounted) Navigator.of(context).pop();
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Location access')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _step == _Step.explainAlways
              ? _buildExplainAlways(context)
              : _buildIntro(context),
        ),
      ),
    );
  }

  Widget _buildIntro(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Icon(Icons.my_location, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('Reminders need your location',
            style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          'Surya checks when you arrive at a reminder\'s place and notifies you. '
          'First, allow location access while using the app.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        FilledButton(
          onPressed: _busy ? null : _requestWhenInUse,
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Allow location'),
        ),
      ],
    );
  }

  Widget _buildExplainAlways(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Icon(Icons.notifications_active,
            size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 24),
        Text('Fire reminders in the background',
            style: theme.textTheme.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 12),
        Text(
          'To alert you even when the app is closed or your phone is locked, '
          'Surya needs "Allow all the time" location access. Your location never '
          'leaves your device — geofences are checked on-device.',
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const Spacer(),
        FilledButton(
          onPressed: _busy ? null : _requestAlways,
          style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14)),
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Allow all the time'),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: _busy ? null : _finish,
          child: const Text('Not now'),
        ),
      ],
    );
  }
}
