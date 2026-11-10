import 'package:flutter_test/flutter_test.dart';
import 'package:surya/models/idea.dart';

/// Phase 10 (My Ideas): the pure model + search logic tests directly; the
/// Firestore-backed repository is exercised on-device (project convention).
void main() {
  const idea = Idea(
    id: 'i1',
    title: 'Weekend hiking app',
    description: 'Suggests nearby trails by difficulty.',
  );

  group('matches (search)', () {
    test('blank query matches everything', () {
      expect(idea.matches(''), isTrue);
      expect(idea.matches('   '), isTrue);
    });

    test('matches on the title, case-insensitively', () {
      expect(idea.matches('HIKING'), isTrue);
      expect(idea.matches('weekend'), isTrue);
    });

    test('matches on the description', () {
      expect(idea.matches('trails'), isTrue);
    });

    test('no match returns false', () {
      expect(idea.matches('spreadsheet'), isFalse);
    });

    test('description-less idea only searches the title', () {
      const bare = Idea(id: 'i2', title: 'Budget tracker');
      expect(bare.matches('budget'), isTrue);
      expect(bare.matches('trails'), isFalse);
    });
  });

  group('toCreateMap', () {
    test('includes the trimmed title and description', () {
      final map = const Idea(id: '', title: '  Big idea  ', description: '  details  ')
          .toCreateMap();
      expect(map['title'], 'Big idea');
      expect(map['description'], 'details');
    });

    test('omits an empty description', () {
      final map = const Idea(id: '', title: 'Solo').toCreateMap();
      expect(map.containsKey('description'), isFalse);
    });
  });
}
