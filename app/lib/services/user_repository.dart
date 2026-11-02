import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/user_profile.dart';

/// Reads/writes the `users/{uid}` profile document (CLAUDE.md §4).
abstract class UserRepository {
  /// Live stream of the profile; emits null until the doc exists (i.e. the user
  /// still needs onboarding).
  Stream<UserProfile?> watchProfile(String uid);

  /// One-off fetch of the profile.
  Future<UserProfile?> getProfile(String uid);

  /// Create (or update) the profile with the chosen assistant name. Used by the
  /// onboarding screen and Settings (Phase 5).
  Future<void> setAssistantName(String uid, String assistantName);

  /// Update the default geofence radius used to pre-fill new reminders
  /// (Settings, Phase 5).
  Future<void> setDefaultRadius(String uid, int radiusMeters);
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid);

  @override
  Stream<UserProfile?> watchProfile(String uid) {
    return _doc(uid).snapshots().map(
          (snap) => snap.exists ? UserProfile.fromFirestore(snap) : null,
        );
  }

  @override
  Future<UserProfile?> getProfile(String uid) async {
    final snap = await _doc(uid).get();
    return snap.exists ? UserProfile.fromFirestore(snap) : null;
  }

  @override
  Future<void> setAssistantName(String uid, String assistantName) {
    // merge:true so we create the doc on first onboarding and update it later
    // (e.g. from Settings in Phase 5) without clobbering other fields.
    return _doc(uid).set(
      {
        'assistantName': assistantName.trim(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> setDefaultRadius(String uid, int radiusMeters) {
    // merge:true so we only touch the radius field, leaving the name intact.
    return _doc(uid).set(
      {'defaultRadiusMeters': radiusMeters},
      SetOptions(merge: true),
    );
  }
}
