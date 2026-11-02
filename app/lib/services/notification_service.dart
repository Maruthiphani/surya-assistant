import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/reminder.dart';

/// Fires local notifications when a reminder's geofence is entered.
///
/// Behind an interface (CLAUDE.md §5) so the notification backend can be swapped
/// or faked in tests.
abstract class NotificationService {
  /// Initialise the plugin + channel. Call once at startup.
  Future<void> init();

  /// Ask the OS for notification permission (Android 13+, iOS). Returns whether
  /// it is granted.
  Future<bool> requestPermission();

  /// Show the "you've arrived" notification for a triggered reminder, phrased
  /// with the user's assistant name.
  Future<void> showReminderTriggered(Reminder reminder, String assistantName);
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _channelId = 'surya_reminders';
  static const String _channelName = 'Reminders';
  static const String _channelDesc =
      'Location reminders that fire when you arrive at a place.';

  @override
  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    // We request iOS permission explicitly in requestPermission(), so don't
    // prompt during init.
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    // Pre-create the Android channel so the first notification is well-formed.
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
  }

  @override
  Future<bool> requestPermission() async {
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ??
          false;
    }
    return true;
  }

  @override
  Future<void> showReminderTriggered(
      Reminder reminder, String assistantName) async {
    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
    );

    // Deterministic id per reminder so re-triggers replace rather than stack.
    final id = reminder.id?.hashCode ?? reminder.hashCode;
    await _plugin.show(
      id,
      '$assistantName reminder',
      "You're near ${reminder.locationName} — ${reminder.task}.",
      details,
      payload: reminder.id,
    );
  }
}
