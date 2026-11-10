import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

/// A shared family group at `families/{familyId}` (CLAUDE.md §10).
///
/// Phase 7a foundation: an owner creates a family and others join with the
/// [inviteCode]. Every member can read/write the shared data later (inventory,
/// Phase 7b); for now this just models membership. Pure data class.
class Family {
  const Family({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.memberUids,
    required this.inviteCode,
    this.memberNames = const <String, String>{},
    this.createdAt,
  });

  final String id;

  /// Display name, e.g. "Sharma family". Falls back to a friendly default.
  final String name;

  /// uid of the member who created the family. Only the owner can disband it.
  final String ownerUid;

  /// All member uids (includes the owner). Membership gate for security rules.
  final List<String> memberUids;

  /// Short code another user types to join (see [generateInviteCode]).
  final String inviteCode;

  /// Denormalised uid → display name map, so the member list and "updated by"
  /// labels can show real names without reading other users' profile docs
  /// (which the security rules forbid). Each member writes their own entry on
  /// create/join (CLAUDE.md §10, Phase 7b).
  final Map<String, String> memberNames;

  final DateTime? createdAt;

  bool isOwner(String uid) => uid == ownerUid;
  bool isMember(String uid) => memberUids.contains(uid);
  int get memberCount => memberUids.length;

  /// Best display name for [uid]: the stored name, else a short id fallback.
  String displayNameFor(String uid) {
    final name = memberNames[uid]?.trim();
    if (name != null && name.isNotEmpty) return name;
    return uid.length <= 6 ? uid : '…${uid.substring(uid.length - 6)}';
  }

  static const String defaultName = 'My family';

  factory Family.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    final name = (data['name'] as String?)?.trim();
    return Family(
      id: doc.id,
      name: (name != null && name.isNotEmpty) ? name : defaultName,
      ownerUid: (data['ownerUid'] as String?) ?? '',
      memberUids:
          (data['memberUids'] as List?)?.whereType<String>().toList() ??
              const <String>[],
      inviteCode: (data['inviteCode'] as String?) ?? '',
      memberNames: ((data['memberNames'] as Map?) ?? const {})
          .map((k, v) => MapEntry('$k', '$v')),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

/// Length of a generated invite code.
const int inviteCodeLength = 6;

/// Alphabet for invite codes. Deliberately omits the ambiguous glyphs
/// I, O, 0 and 1 so codes are easy to read aloud and type.
const String _inviteAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/// Generate a random [inviteCodeLength]-char invite code. Pass a seeded
/// [random] in tests for determinism; defaults to a secure RNG.
String generateInviteCode([Random? random]) {
  final rnd = random ?? Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < inviteCodeLength; i++) {
    buf.write(_inviteAlphabet[rnd.nextInt(_inviteAlphabet.length)]);
  }
  return buf.toString();
}

/// Normalise a user-typed code for lookup: uppercase and strip anything that
/// isn't a letter/digit (spaces, dashes). The generation alphabet avoids
/// ambiguous characters, so no look-alike remapping is needed.
String normalizeInviteCode(String input) {
  return input.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
}
