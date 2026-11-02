import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/reminder.dart';

/// CRUD for reminders under `users/{uid}/reminders` (CLAUDE.md §4).
///
/// Kept behind an interface so the UI depends on the contract, not Firestore
/// (CLAUDE.md §5). Geofence registration is NOT this class's job — that lives in
/// `LocationService` in Phase 2.
abstract class ReminderRepository {
  /// Live list of the user's reminders, newest first. Backed by a Firestore
  /// snapshot listener so the home screen stays in sync automatically.
  Stream<List<Reminder>> watchReminders(String uid);

  /// Emits true while there are local writes not yet acknowledged by the
  /// server (i.e. created/updated offline and awaiting sync-on-reconnect).
  /// Drives the "changes will sync" banner (CLAUDE.md Phase 5).
  Stream<bool> watchPendingSync(String uid);

  /// Create a new reminder; returns its generated id.
  Future<String> addReminder(String uid, Reminder reminder);

  /// Move a reminder to a new status (e.g. completed/cancelled). Stamps the
  /// matching timestamp field.
  Future<void> updateStatus(String uid, String reminderId, ReminderStatus status);

  /// Permanently delete a reminder.
  Future<void> deleteReminder(String uid, String reminderId);
}

class FirestoreReminderRepository implements ReminderRepository {
  FirestoreReminderRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('reminders');

  @override
  Stream<List<Reminder>> watchReminders(String uid) {
    return _col(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(Reminder.fromFirestore).toList());
  }

  @override
  Stream<bool> watchPendingSync(String uid) {
    // includeMetadataChanges so we're notified when pending writes flush.
    return _col(uid)
        .snapshots(includeMetadataChanges: true)
        .map((snap) => snap.metadata.hasPendingWrites)
        .distinct();
  }

  @override
  Future<String> addReminder(String uid, Reminder reminder) async {
    final doc = await _col(uid).add({
      ...reminder.toMap(),
      // Server clock, not the device's.
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  @override
  Future<void> updateStatus(
    String uid,
    String reminderId,
    ReminderStatus status,
  ) {
    final update = <String, dynamic>{'status': status.name};
    // Stamp the lifecycle timestamp that matches the new status.
    switch (status) {
      case ReminderStatus.triggered:
        update['triggeredAt'] = FieldValue.serverTimestamp();
      case ReminderStatus.completed:
        update['completedAt'] = FieldValue.serverTimestamp();
      case ReminderStatus.active:
      case ReminderStatus.cancelled:
        break;
    }
    return _col(uid).doc(reminderId).update(update);
  }

  @override
  Future<void> deleteReminder(String uid, String reminderId) {
    return _col(uid).doc(reminderId).delete();
  }
}
