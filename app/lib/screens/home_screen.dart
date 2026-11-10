import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder.dart';
import '../models/user_profile.dart';
import '../providers/providers.dart';
import '../services/location_service.dart';
import 'add_reminder_screen.dart';
import 'debug_screen.dart';
import 'ideas_screen.dart';
import 'inventory_screen.dart';
import 'location_permission_screen.dart';
import 'settings_screen.dart';
import 'voice_capture_screen.dart';

/// Home: the live list of the user's reminders (CLAUDE.md Phase 1), now also the
/// place where geofence tracking is started (Phase 2).
///
/// Backed by `remindersProvider`, a Firestore snapshot stream, so the list stays
/// in sync. On mount it initialises notifications, starts the geofence engine if
/// permitted, and re-syncs geofences whenever the active reminders change.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  LocationPermissionLevel _permission = LocationPermissionLevel.denied;

  @override
  void initState() {
    super.initState();
    // Defer until after first frame so provider reads are safe.
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  Future<void> _bootstrap() async {
    // Notifications first so a triggered geofence can alert the user.
    final notifications = ref.read(notificationServiceProvider);
    await notifications.init();
    await notifications.requestPermission();

    // Time-based scheduling (Phase 8): ready the timezone DB + channel.
    await ref.read(reminderSchedulerProvider).init();

    // Text-to-speech (Phase 9): warm up so confirmations can be spoken.
    await ref.read(ttsServiceProvider).init();

    // Push (FCM): init + register this device's token for the signed-in user.
    final messaging = ref.read(messagingServiceProvider);
    await messaging.init();
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      await messaging.syncTokenForUser(uid);
    }

    // Billing (RevenueCat): configure + associate the signed-in user so Pro
    // entitlement is known. No-op when no key is configured (Free mode).
    final subscription = ref.read(subscriptionServiceProvider);
    await subscription.init();
    if (uid != null) {
      await subscription.identify(uid);
    }

    // Siri Shortcut (Phase 5): handle a reminder phrase that launched or is
    // pushed to the app. Warm-start pushes arrive via the handler; cold-start
    // text is consumed once here.
    final intents = ref.read(intentChannelProvider);
    intents.onPrefill(_openComposeWith);
    final pending = await intents.consumePending();
    if (pending != null) _openComposeWith(pending);

    await _refreshPermissionAndTrack();
  }

  /// Open the capture screen pre-filled with command text (from Siri).
  void _openComposeWith(String text) {
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VoiceCaptureScreen(initialText: text),
      ),
    );
  }

  @override
  void dispose() {
    // Drop the warm-start handler so it doesn't fire into a dead context.
    ref.read(intentChannelProvider).onPrefill(null);
    super.dispose();
  }

  Future<void> _refreshPermissionAndTrack() async {
    final level = await ref.read(locationServiceProvider).checkPermission();
    if (mounted) setState(() => _permission = level);
    if (level != LocationPermissionLevel.denied) {
      await ref.read(geofenceCoordinatorProvider).startTrackingIfPermitted();
    }
  }

  Future<void> _signOut() async {
    // Stop targeting this device with push before dropping the session.
    final uid = ref.read(currentUidProvider);
    if (uid != null) {
      await ref.read(messagingServiceProvider).clearTokenForUser(uid);
    }
    await ref.read(reminderSchedulerProvider).cancelAll();
    await ref.read(subscriptionServiceProvider).logOut();
    await ref.read(authServiceProvider).signOut();
  }

  Future<void> _openPermissionFlow() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const LocationPermissionScreen()),
    );
    await _refreshPermissionAndTrack();
  }

  @override
  Widget build(BuildContext context) {
    final remindersAsync = ref.watch(remindersProvider);
    final assistantName =
        ref.watch(userProfileProvider).valueOrNull?.assistantName ??
            UserProfile.defaultAssistantName;

    // Keep geofences + scheduled notifications in sync with the reminders as
    // they change (Phase 8 adds the scheduler alongside the geofence sync).
    ref.listen(remindersProvider, (_, next) {
      if (next.hasValue) {
        ref.read(geofenceCoordinatorProvider).syncActiveReminders();
        ref.read(reminderSchedulerProvider).sync(
              next.value!,
              assistantName: ref.read(userProfileProvider).valueOrNull
                      ?.assistantName ??
                  UserProfile.defaultAssistantName,
            );
      }
    });

    // Re-sync store geofences when the shared/personal Need-to-Buy list changes
    // (Phase 7c): a new needed item should start monitoring matching stores.
    ref.listen(geofenceNeedsProvider, (_, __) {
      ref.read(geofenceCoordinatorProvider).syncActiveReminders();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(assistantName),
        actions: [
          IconButton(
            tooltip: 'Add manually',
            icon: const Icon(Icons.add),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AddReminderScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Inventory',
            icon: const Icon(Icons.inventory_2_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InventoryScreen()),
            ),
          ),
          IconButton(
            tooltip: 'My Ideas',
            icon: const Icon(Icons.lightbulb_outline),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const IdeasScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Debug (simulate geofence)',
            icon: const Icon(Icons.bug_report_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DebugScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(Icons.logout),
            onPressed: _signOut,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VoiceCaptureScreen()),
        ),
        icon: const Icon(Icons.mic),
        label: Text(ref.watch(stringsProvider).speak),
      ),
      body: Column(
        children: [
          if (_permission == LocationPermissionLevel.denied)
            _LocationBanner(onEnable: _openPermissionFlow),
          if (ref.watch(pendingSyncProvider).valueOrNull ?? false)
            const _SyncBanner(),
          Expanded(
            child: remindersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorState(message: '$e'),
              data: (reminders) {
                if (reminders.isEmpty) {
                  return const _EmptyState();
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 96, top: 8),
                  itemCount: reminders.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _ReminderTile(reminder: reminders[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Prompt shown when location permission hasn't been granted yet.
class _LocationBanner extends StatelessWidget {
  const _LocationBanner({required this.onEnable});

  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            Icon(Icons.location_off, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Enable location so reminders can fire when you arrive.',
                style: TextStyle(color: scheme.onSecondaryContainer),
              ),
            ),
            TextButton(onPressed: onEnable, child: const Text('Enable')),
          ],
        ),
      ),
    );
  }
}

/// Actions available on a reminder from the overflow menu.
enum _ReminderAction { complete, cancel, delete }

/// Shown while reminder writes are queued locally and waiting to sync
/// (offline). Clears automatically once Firestore flushes the pending writes.
class _SyncBanner extends StatelessWidget {
  const _SyncBanner();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Row(
          children: [
            Icon(Icons.cloud_upload_outlined,
                color: scheme.onTertiaryContainer, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Offline — your changes are saved and will sync automatically.',
                style: TextStyle(color: scheme.onTertiaryContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Single reminder row with a status badge and an overflow menu for
/// complete / cancel / delete (CLAUDE.md Phase 5).
class _ReminderTile extends ConsumerWidget {
  const _ReminderTile({required this.reminder});

  final Reminder reminder;

  bool get _isOpen =>
      reminder.status == ReminderStatus.active ||
      reminder.status == ReminderStatus.triggered;

  Future<void> _onSelected(
      BuildContext context, WidgetRef ref, _ReminderAction action) async {
    final uid = ref.read(currentUidProvider);
    final id = reminder.id;
    if (uid == null || id == null) return;
    final repo = ref.read(reminderRepositoryProvider);
    final messenger = ScaffoldMessenger.of(context);

    try {
      switch (action) {
        case _ReminderAction.complete:
          await repo.updateStatus(uid, id, ReminderStatus.completed);
          _toast(messenger, 'Marked "${reminder.task}" complete.');
        case _ReminderAction.cancel:
          await repo.updateStatus(uid, id, ReminderStatus.cancelled);
          _toast(messenger, 'Cancelled "${reminder.task}".');
        case _ReminderAction.delete:
          await repo.deleteReminder(uid, id);
          _toast(messenger, 'Deleted "${reminder.task}".');
      }
      // Dropping out of `active` removes this reminder's geofences; the home
      // listener on remindersProvider triggers the re-sync automatically.
    } catch (_) {
      _toast(messenger, 'Could not update. Please try again.');
    }
  }

  void _toast(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// "at Costco", "Nov 7 · 9:00 AM (Yearly)", or both lines combined.
  String _subtitle() {
    final parts = <String>[];
    if (reminder.hasLocationTrigger && reminder.locationName.isNotEmpty) {
      parts.add('at ${reminder.locationName}');
    }
    if (reminder.isTimeScheduled) {
      final t = reminder.remindAt!;
      final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
      final ampm = t.hour < 12 ? 'AM' : 'PM';
      final m = t.minute.toString().padLeft(2, '0');
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      final repeat =
          reminder.recurrence.repeats ? ' (${reminder.recurrence.label})' : '';
      parts.add('${months[t.month - 1]} ${t.day} · $h:$m $ampm$repeat');
    }
    return parts.isEmpty ? 'Reminder' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeOnly = reminder.isTimeScheduled && !reminder.hasLocationTrigger;
    return ListTile(
      leading: Icon(timeOnly ? Icons.schedule : Icons.place_outlined),
      title: Text(reminder.task),
      subtitle: Text(_subtitle()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StatusChip(status: reminder.status),
          PopupMenuButton<_ReminderAction>(
            tooltip: 'Actions',
            onSelected: (a) => _onSelected(context, ref, a),
            itemBuilder: (_) => [
              if (_isOpen) ...[
                const PopupMenuItem(
                  value: _ReminderAction.complete,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.check_circle_outline),
                    title: Text('Mark complete'),
                  ),
                ),
                const PopupMenuItem(
                  value: _ReminderAction.cancel,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.cancel_outlined),
                    title: Text('Cancel'),
                  ),
                ),
              ],
              const PopupMenuItem(
                value: _ReminderAction.delete,
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.delete_outline),
                  title: Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ReminderStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      ReminderStatus.active => (scheme.primaryContainer, scheme.onPrimaryContainer),
      ReminderStatus.triggered => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      ReminderStatus.completed => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      ReminderStatus.cancelled => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Chip(
      label: Text(status.name),
      backgroundColor: bg,
      labelStyle: TextStyle(color: fg, fontSize: 12),
      visualDensity: VisualDensity.compact,
      side: BorderSide.none,
    );
  }
}

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = ref.watch(stringsProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none,
                size: 64, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(s.noRemindersTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              s.noRemindersBody,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'Could not load reminders.\n$message',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
