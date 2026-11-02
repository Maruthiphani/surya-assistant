import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder.dart';
import '../providers/providers.dart';

/// Developer-only screen to test the geofence trigger path without moving.
///
/// "Simulate ENTER" runs the exact production handler (notification +
/// status→triggered), so it verifies the business logic on an emulator where
/// real GPS movement is awkward. See PROGRESS.md for `adb emu geo fix` testing
/// of the live geofence engine.
class DebugScreen extends ConsumerWidget {
  const DebugScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remindersAsync = ref.watch(remindersProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Debug — geofence')),
      body: remindersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (reminders) {
          if (reminders.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Add a reminder first, then simulate entering its geofence.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView(
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Tap "Simulate ENTER" to trigger a reminder as if you walked '
                  'into its geofence. Only active reminders will fire.',
                ),
              ),
              for (final r in reminders)
                ListTile(
                  title: Text(r.task),
                  subtitle: Text('${r.locationName} · ${r.status.name}'),
                  trailing: FilledButton.tonal(
                    onPressed: r.status == ReminderStatus.active
                        ? () async {
                            await ref
                                .read(geofenceCoordinatorProvider)
                                .simulateEnter(r.id!);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text('Simulated ENTER: ${r.task}')),
                              );
                            }
                          }
                        : null,
                    child: const Text('Simulate ENTER'),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
