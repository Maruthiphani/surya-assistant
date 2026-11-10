import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/idea.dart';

/// CRUD for the user's private ideas under `users/{uid}/ideas` (CLAUDE.md
/// Phase 10). Behind an interface (§5) so the UI depends on the contract, not
/// Firestore. Never touches reminders, inventory, or family data.
abstract class IdeaRepository {
  /// Live list of the user's ideas, newest first.
  Stream<List<Idea>> watchIdeas(String uid);

  /// Create a new idea; returns its generated id.
  Future<String> addIdea(String uid,
      {required String title, String? description});

  /// Update an existing idea's title/description.
  Future<void> updateIdea(String uid, String ideaId,
      {required String title, String? description});

  /// Permanently delete an idea.
  Future<void> deleteIdea(String uid, String ideaId);
}

class FirestoreIdeaRepository implements IdeaRepository {
  FirestoreIdeaRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('ideas');

  @override
  Stream<List<Idea>> watchIdeas(String uid) {
    return _col(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map(Idea.fromFirestore).toList(growable: false));
  }

  @override
  Future<String> addIdea(String uid,
      {required String title, String? description}) async {
    final idea = Idea(id: '', title: title, description: description);
    final doc = await _col(uid).add({
      ...idea.toCreateMap(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  @override
  Future<void> updateIdea(String uid, String ideaId,
      {required String title, String? description}) {
    return _col(uid).doc(ideaId).set(
      {
        'title': title.trim(),
        'description': (description == null || description.trim().isEmpty)
            ? FieldValue.delete()
            : description.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> deleteIdea(String uid, String ideaId) {
    return _col(uid).doc(ideaId).delete();
  }
}
