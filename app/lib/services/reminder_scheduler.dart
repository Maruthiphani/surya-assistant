import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/recurrence.dart';
import '../models/reminder.dart';

/// Schedules time-based reminders as OS-level local notifications (CLAUDE.md
/// Phase 8). This is distinct from the geofence/location path — a reminder can
/// be time-based, location-based, or both. No LLM is ever involved.
///
/// Behind an interface (§5) so it can be faked in tests (the real one needs the
/// platform plugin + timezone database, which only run on a device).
abstract class ReminderScheduler {
  /// Initialise the timezone database + notification channel. Call once.
  Future<void> init();

  /// Make the scheduled notifications match exactly the active time-based
  /// reminders in [reminders]: schedule new ones (at their next occurrence),
  /// cancel ones that are gone/inactive. Idempotent.
  Future<void> sync(List<Reminder> reminders, {required String assistantName});

  /// Cancel every scheduled reminder (e.g. on sign-out).
  Future<void> cancelAll();
}

class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _tzReady = false;

  /// Ids currently scheduled, so a re-sync can cancel ones that disappeared.
  final Set<int> _scheduled = {};

  static const String _channelId = 'surya_scheduled';
  static const String _channelName = 'Scheduled reminders';
  static const String _channelDesc =
      'Reminders that fire at a date/time you set.';

  /// Keep scheduled-reminder ids in a high range so they never collide with the
  /// geofence notification ids (which use the reminder id hashCode directly).
  int _idFor(String reminderId) =>
      0x40000000 | (reminderId.hashCode & 0x3fffffff);

  @override
  Future<void> init() async {
    if (_tzReady) return;
    tzdata.initializeTimeZones();
    try {
      final dynamic local = await FlutterTimezone.getLocalTimezone();
      // flutter_timezone returned a String in 3.x and an object with
      // `.identifier` in 4.x — accept either.
      final name = local is String ? local : local.identifier as String;
      tz.setLocalLocation(tz.getLocation(name));
    } catch (e) {
      debugPrint('Timezone lookup failed ($e) — scheduling in UTC.');
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    _tzReady = true;
  }

  @override
  Future<void> sync(List<Reminder> reminders,
      {required String assistantName}) async {
    await init();
    final now = DateTime.now();

    final wanted = <int>{};
    for (final r in reminders) {
      if (r.status != ReminderStatus.active || !r.isTimeScheduled) continue;
      final id = r.id;
      if (id == null) continue;

      final fire = r.recurrence.nextOccurrence(r.remindAt!, after: now);
      if (fire == null) continue; // past one-shot — nothing to schedule

      final notifId = _idFor(id);
      wanted.add(notifId);
      await _scheduleOne(notifId, r, fire, assistantName);
    }

    // Cancel anything we previously scheduled that's no longer wanted.
    for (final stale in _scheduled.difference(wanted)) {
      await _plugin.cancel(stale);
    }
    _scheduled
      ..clear()
      ..addAll(wanted);
  }

  Future<void> _scheduleOne(
      int id, Reminder r, DateTime fire, String assistantName) async {
    final when = tz.TZDateTime.from(fire, tz.local);
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDesc,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: const DarwinNotificationDetails(),
    );

    await _plugin.zonedSchedule(
      id,
      '$assistantName reminder',
      r.task,
      when,
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: _repeatComponent(r.recurrence),
      payload: r.id,
    );
  }

  /// Map our recurrence onto the plugin's repeat rule so the OS re-fires
  /// automatically (daily/weekly/monthly/yearly). One-shots get no rule.
  static DateTimeComponents? _repeatComponent(Recurrence r) {
    switch (r) {
      case Recurrence.none:
        return null;
      case Recurrence.daily:
        return DateTimeComponents.time;
      case Recurrence.weekly:
        return DateTimeComponents.dayOfWeekAndTime;
      case Recurrence.monthly:
        return DateTimeComponents.dayOfMonthAndTime;
      case Recurrence.yearly:
        return DateTimeComponents.dateAndTime;
    }
  }

  @override
  Future<void> cancelAll() async {
    for (final id in _scheduled) {
      await _plugin.cancel(id);
    }
    _scheduled.clear();
  }
}
