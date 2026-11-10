import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/family.dart';

/// A user-facing problem creating/joining/leaving a family (bad code, wrong
/// role, etc.). The message is safe to show in a snackbar.
class FamilyException implements Exception {
  const FamilyException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Reads/writes `families/{familyId}` and the `familyCodes/{code}` lookup
/// (CLAUDE.md §10). Also maintains the `users/{uid}.familyId` pointer so the
/// app can find the caller's family.
///
/// Phase 7a is the sharing *foundation* — membership only. The shared inventory
/// (Phase 7b) is added under this family later. This repository never touches
/// reminders or any existing single-user data.
abstract class FamilyRepository {
  /// Live family document; emits null if it doesn't exist (e.g. disbanded).
  Stream<Family?> watchFamily(String familyId);

  /// Create a new family owned by [uid] and point the user at it. Returns the
  /// created family (with its freshly minted invite code). [displayName] is the
  /// creator's own name, stored in `memberNames` for the shared member list.
  Future<Family> createFamily({
    required String uid,
    required String name,
    required String displayName,
  });

  /// Join an existing family by its invite [code]. Returns the familyId.
  /// Throws [FamilyException] on an unknown/expired code. [displayName] is the
  /// joiner's own name, added to `memberNames`.
  Future<String> joinByCode({
    required String uid,
    required String code,
    required String displayName,
  });

  /// Remove [uid] from the family (members only — the owner must disband).
  Future<void> leaveFamily({required String uid, required String familyId});

  /// Delete the family (owner only). Other members' pointers self-heal on next
  /// read via [clearStalePointer].
  Future<void> disbandFamily({required String uid, required String familyId});

  /// Clear this user's `familyId` pointer when the family no longer exists.
  Future<void> clearStalePointer(String uid);
}

class FirestoreFamilyRepository implements FamilyRepository {
  FirestoreFamilyRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _families =>
      _db.collection('families');
  CollectionReference<Map<String, dynamic>> get _codes =>
      _db.collection('familyCodes');
  DocumentReference<Map<String, dynamic>> _user(String uid) =>
      _db.collection('users').doc(uid);

  @override
  Stream<Family?> watchFamily(String familyId) {
    return _families.doc(familyId).snapshots().map(
          (snap) => snap.exists ? Family.fromFirestore(snap) : null,
        );
  }

  @override
  Future<Family> createFamily({
    required String uid,
    required String name,
    required String displayName,
  }) async {
    final cleanName = name.trim().isEmpty ? Family.defaultName : name.trim();
    final cleanDisplay = _cleanDisplayName(displayName);
    final code = await _reserveUniqueCode();
    final familyRef = _families.doc();

    final batch = _db.batch();
    batch.set(familyRef, {
      'name': cleanName,
      'ownerUid': uid,
      'memberUids': [uid],
      'inviteCode': code,
      'memberNames': {uid: cleanDisplay},
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.set(_codes.doc(code), {'familyId': familyRef.id});
    batch.set(_user(uid), {'familyId': familyRef.id}, SetOptions(merge: true));
    await batch.commit();

    return Family(
      id: familyRef.id,
      name: cleanName,
      ownerUid: uid,
      memberUids: [uid],
      inviteCode: code,
      memberNames: {uid: cleanDisplay},
    );
  }

  @override
  Future<String> joinByCode({
    required String uid,
    required String code,
    required String displayName,
  }) async {
    final norm = normalizeInviteCode(code);
    if (norm.length != inviteCodeLength) {
      throw const FamilyException("That code doesn't look right.");
    }

    final codeSnap = await _codes.doc(norm).get();
    if (!codeSnap.exists) {
      throw const FamilyException('No family found for that code.');
    }
    final familyId = codeSnap.data()?['familyId'] as String?;
    if (familyId == null || familyId.isEmpty) {
      throw const FamilyException('No family found for that code.');
    }

    // Don't pre-read the family: the caller isn't a member yet, so the
    // membership read rule would deny it. Instead rely on the rule-guarded
    // update (which may only add the caller to memberUids). arrayUnion is
    // idempotent, so re-joining is harmless. `update` on a missing doc fails
    // with not-found → the family was disbanded.
    try {
      final batch = _db.batch();
      batch.update(_families.doc(familyId), {
        'memberUids': FieldValue.arrayUnion([uid]),
        // Dotted field path writes only this member's entry, leaving the rest
        // of the map untouched (so the join can't clobber other names).
        'memberNames.$uid': _cleanDisplayName(displayName),
      });
      batch.set(_user(uid), {'familyId': familyId}, SetOptions(merge: true));
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        throw const FamilyException('That family no longer exists.');
      }
      rethrow;
    }
    return familyId;
  }

  @override
  Future<void> leaveFamily({
    required String uid,
    required String familyId,
  }) async {
    final famSnap = await _families.doc(familyId).get();
    if (!famSnap.exists) {
      // Family already gone — just drop our stale pointer.
      await clearStalePointer(uid);
      return;
    }
    final family = Family.fromFirestore(famSnap);
    if (family.isOwner(uid)) {
      throw const FamilyException(
        'As the owner, disband the family instead of leaving.',
      );
    }

    final batch = _db.batch();
    batch.update(_families.doc(familyId), {
      'memberUids': FieldValue.arrayRemove([uid]),
    });
    batch.set(_user(uid), {'familyId': FieldValue.delete()},
        SetOptions(merge: true));
    await batch.commit();
  }

  @override
  Future<void> disbandFamily({
    required String uid,
    required String familyId,
  }) async {
    final famSnap = await _families.doc(familyId).get();
    if (famSnap.exists) {
      final family = Family.fromFirestore(famSnap);
      if (!family.isOwner(uid)) {
        throw const FamilyException('Only the owner can disband the family.');
      }
    }

    final batch = _db.batch();
    batch.delete(_families.doc(familyId));
    batch.set(_user(uid), {'familyId': FieldValue.delete()},
        SetOptions(merge: true));
    await batch.commit();
    // The invite-code doc and other members' pointers are left to self-heal
    // (joining a disbanded code fails cleanly; members clear via
    // clearStalePointer). Client rules forbid writing other users' docs.
  }

  @override
  Future<void> clearStalePointer(String uid) {
    return _user(uid).set({'familyId': FieldValue.delete()},
        SetOptions(merge: true));
  }

  /// Keep display names short and non-empty for the shared member list.
  static String _cleanDisplayName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Member';
    return trimmed.length > 40 ? trimmed.substring(0, 40) : trimmed;
  }

  /// Generate an invite code that isn't already taken. A few attempts is plenty
  /// given the code space (32^6 ≈ 1e9).
  Future<String> _reserveUniqueCode() async {
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = generateInviteCode();
      final existing = await _codes.doc(code).get();
      if (!existing.exists) return code;
    }
    // Astronomically unlikely; surface rather than loop forever.
    throw const FamilyException(
      'Could not generate an invite code. Please try again.',
    );
  }
}
