import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../models/reminder.dart';

/// Fires local notifications when a reminder's geofence is entered, or when a
/// family member reaches a store carrying needed items (Phase 7c).
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
  /// with the user's assistant name. [strings] localizes the title/body
  /// (Phase 9); null falls back to English.
  Future<void> showReminderTriggered(Reminder reminder, String assistantName,
      {AppStrings? strings});

  /// Show a store-entry alert listing the needed items this store is likely to
  /// carry (Phase 7c). [payload] is an opaque token handed back to the action
  /// handler so a one-tap "Bought" can flip the items to present.
  Future<void> showStoreNeeds({
    required String assistantName,
    required String storeLabel,
    required List<String> neededNames,
    required List<String> presentNames,
    required String payload,
  });

  /// Register a handler for notification taps/actions. [actionId] is the action
  /// button id (or null for a plain tap); [payload] is what was attached to the
  /// notification. Used to wire the "Bought" action back to the inventory.
  void setActionHandler(
      void Function(String? actionId, String? payload)? handler);
}

class LocalNotificationService implements NotificationService {
  LocalNotificationService({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const String _channelId = 'surya_reminders';
  static const String _channelName = 'Reminders';
  static const String _channelDesc =
      'Location reminders that fire when you arrive at a place.';

  static const String _needsChannelId = 'surya_store_needs';
  static const String _needsChannelName = 'Shopping alerts';
  static const String _needsChannelDesc =
      'Alerts when you reach a store that likely has items on your list.';

  /// Action id for the one-tap "Bought" button on a store-needs notification.
  static const String boughtActionId = 'mark_bought';

  void Function(String? actionId, String? payload)? _actionHandler;

  @override
  void setActionHandler(
      void Function(String? actionId, String? payload)? handler) {
    _actionHandler = handler;
  }

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
      onDidReceiveNotificationResponse: (response) {
        _actionHandler?.call(response.actionId, response.payload);
      },
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    // Pre-create both Android channels so the first notification is well-formed.
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelId,
        _channelName,
        description: _channelDesc,
        importance: Importance.high,
      ),
    );
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _needsChannelId,
        _needsChannelName,
        description: _needsChannelDesc,
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
      Reminder reminder, String assistantName,
      {AppStrings? strings}) async {
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

    final s = strings ?? AppStrings.of(AppLanguage.english);
    // Deterministic id per reminder so re-triggers replace rather than stack.
    final id = reminder.id?.hashCode ?? reminder.hashCode;
    await _plugin.show(
      id,
      s.reminderTitle(assistantName),
      s.nearBody(reminder.locationName, reminder.task),
      details,
      payload: reminder.id,
    );
  }

  @override
  Future<void> showStoreNeeds({
    required String assistantName,
    required String storeLabel,
    required List<String> neededNames,
    required List<String> presentNames,
    required String payload,
  }) async {
    if (neededNames.isEmpty) return; // never alert with an empty list (§10)

    final needLine = neededNames.join(', ');
    final body = StringBuffer("You're near $storeLabel — need: $needLine.");
    if (presentNames.isNotEmpty) {
      // Help avoid duplicate buys: show what's already at home (§10 goal).
      body.write(' Already home: ${presentNames.join(', ')}.');
    }

    final androidDetails = AndroidNotificationDetails(
      _needsChannelId,
      _needsChannelName,
      channelDescription: _needsChannelDesc,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body.toString()),
      actions: const [
        AndroidNotificationAction(boughtActionId, 'Bought',
            showsUserInterface: false),
      ],
    );
    final details = NotificationDetails(
      android: androidDetails,
      // iOS action buttons need a registered category (device task); a plain
      // tap still opens the app and routes via the payload.
      iOS: const DarwinNotificationDetails(),
    );

    // Stable id per store so standing in the store updates rather than stacks.
    final id = storeLabel.hashCode & 0x7fffffff;
    await _plugin.show(
      id,
      '$assistantName — ${neededNames.length} to buy here',
      body.toString(),
      details,
      payload: payload,
    );
  }
}
