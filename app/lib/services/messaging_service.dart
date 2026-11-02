import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Push messaging (CLAUDE.md §2, Phase 5) via Firebase Cloud Messaging.
///
/// Responsibilities, kept behind an interface (CLAUDE.md §5) so it can be faked
/// in tests:
/// - request notification permission (iOS / Android 13+),
/// - register this app instance and persist its direct-send id (Firebase
///   Installation ID) under the user's profile so the backend can target it,
/// - keep the stored id fresh when it rotates,
/// - surface foreground messages to a callback.
///
/// firebase_messaging 17 replaced the raw FCM token with [FirebaseMessaging.
/// register] + the [FirebaseMessaging.onRegistered] stream, whose value is the
/// Firebase Installation ID (FID) used as the send target.
///
/// This is transport only. The location geofence → local notification path
/// (Phase 2) is unchanged and never involves push or an LLM.
abstract class MessagingService {
  /// Initialise messaging and request permission. Safe to call more than once.
  Future<void> init();

  /// Register this app instance and persist its send-id under
  /// `users/{uid}/devices`, keeping it fresh as it rotates. Call once a user is
  /// signed in.
  Future<void> syncTokenForUser(String uid);

  /// Stop targeting this device for [uid] (e.g. on sign-out): remove the stored
  /// id and unregister the instance.
  Future<void> clearTokenForUser(String uid);

  /// Stream of messages received while the app is in the foreground.
  Stream<RemoteMessage> get onForegroundMessage;
}

class FcmMessagingService implements MessagingService {
  FcmMessagingService({
    FirebaseMessaging? messaging,
    FirebaseFirestore? firestore,
  })  : _messaging = messaging ?? FirebaseMessaging.instance,
        _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseMessaging _messaging;
  final FirebaseFirestore _db;

  bool _initialised = false;

  /// Last registration id we received; retained so sign-out can remove the
  /// right `devices/{id}` doc.
  String? _lastId;

  @override
  Stream<RemoteMessage> get onForegroundMessage => FirebaseMessaging.onMessage;

  @override
  Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    await _messaging.requestPermission();
    // Show heads-up alerts while the app is foregrounded on iOS.
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  @override
  Future<void> syncTokenForUser(String uid) async {
    try {
      // Subscribe BEFORE register() so we don't miss the first emission; the
      // stream also re-fires whenever the id rotates.
      _messaging.onRegistered.listen((id) {
        _lastId = id;
        _storeId(uid, id);
      });
      await _messaging.register();
    } catch (e) {
      // Registration can fail on simulators/emulators without push support
      // (e.g. no APNs token on iOS Simulator). Non-fatal for the demo loop.
      debugPrint('FCM registration skipped: $e');
    }
  }

  Future<void> _storeId(String uid, String id) {
    return _db
        .collection('users')
        .doc(uid)
        .collection('devices')
        .doc(id)
        .set({
      'id': id,
      'platform': defaultTargetPlatform.name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> clearTokenForUser(String uid) async {
    try {
      final id = _lastId;
      if (id != null) {
        await _db
            .collection('users')
            .doc(uid)
            .collection('devices')
            .doc(id)
            .delete();
      }
      await _messaging.unregister();
      _lastId = null;
    } catch (e) {
      debugPrint('FCM unregister skipped: $e');
    }
  }
}

/// Background/terminated-state FCM handler. Must be a top-level (or static)
/// function annotated with @pragma('vm:entry-point') because the OS runs it in
/// a separate isolate with no access to app state. Registered from main().
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // The isolate is fresh — ensure Firebase is available before any use.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Data-only work could go here. Notification payloads are shown by the OS
  // automatically, so there's nothing to do for the demo.
  debugPrint('Handled background FCM message: ${message.messageId}');
}

/// Wire the background handler. Call once from main() before runApp.
void registerMessagingBackgroundHandler() {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
}
