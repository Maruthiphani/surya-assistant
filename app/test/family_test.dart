import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:surya/models/family.dart';

/// Phase 7a (CLAUDE.md §10): unit-tests the pure family logic — the invite-code
/// helpers and the Family membership helpers. The Firestore-backed repository
/// (like UserRepository/ReminderRepository) is exercised on-device, not here.
void main() {
  group('invite code', () {
    test('generated code has the fixed length', () {
      expect(generateInviteCode().length, inviteCodeLength);
    });

    test('generated code avoids ambiguous glyphs I, O, 0, 1', () {
      final rnd = Random(42);
      for (var i = 0; i < 200; i++) {
        final code = generateInviteCode(rnd);
        expect(code.contains(RegExp('[IO01]')), isFalse,
            reason: 'code "$code" contains an ambiguous character');
      }
    });

    test('generation is deterministic for a seeded RNG', () {
      expect(generateInviteCode(Random(7)), generateInviteCode(Random(7)));
    });

    test('normalize uppercases and strips spaces/dashes', () {
      expect(normalizeInviteCode(' 7kq-4 mp '), '7KQ4MP');
      expect(normalizeInviteCode('abc123'), 'ABC123');
    });
  });

  group('Family membership helpers', () {
    const family = Family(
      id: 'fam1',
      name: 'Sharma family',
      ownerUid: 'owner',
      memberUids: ['owner', 'member2'],
      inviteCode: '7KQ4MP',
    );

    test('isOwner only true for the owner', () {
      expect(family.isOwner('owner'), isTrue);
      expect(family.isOwner('member2'), isFalse);
    });

    test('isMember true for any member, false otherwise', () {
      expect(family.isMember('owner'), isTrue);
      expect(family.isMember('member2'), isTrue);
      expect(family.isMember('stranger'), isFalse);
    });

    test('memberCount reflects the member list', () {
      expect(family.memberCount, 2);
    });
  });

  group('Family display names (Phase 7b)', () {
    const family = Family(
      id: 'fam1',
      name: 'Sharma family',
      ownerUid: 'owner-uid',
      memberUids: ['owner-uid', 'member-two-uid'],
      inviteCode: '7KQ4MP',
      memberNames: {'owner-uid': 'Asha'},
    );

    test('returns the stored name when present', () {
      expect(family.displayNameFor('owner-uid'), 'Asha');
    });

    test('falls back to a short id when no name is stored', () {
      expect(family.displayNameFor('member-two-uid'), '…wo-uid');
    });
  });
}
