import 'package:cloud_firestore/cloud_firestore.dart';

/// A saved idea → a document under `users/{uid}/ideas/{ideaId}` (CLAUDE.md
/// Phase 10, "My Ideas"). Personal and private to the user. Pure data class.
class Idea {
  const Idea({
    required this.id,
    required this.title,
    this.description,
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Short headline, e.g. "App for splitting bills".
  final String title;

  /// Optional longer note.
  final String? description;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Case-insensitive search over title + description. An empty/blank query
  /// matches everything (so the list shows all ideas by default).
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return title.toLowerCase().contains(q) ||
        (description?.toLowerCase().contains(q) ?? false);
  }

  factory Idea.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const <String, dynamic>{};
    return Idea(
      id: doc.id,
      title: ((data['title'] as String?) ?? '').trim(),
      description: (data['description'] as String?)?.trim().isNotEmpty == true
          ? (data['description'] as String).trim()
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Payload for a new idea; timestamps are set by the repository.
  Map<String, dynamic> toCreateMap() => {
        'title': title.trim(),
        if (description != null && description!.trim().isNotEmpty)
          'description': description!.trim(),
      };
}
