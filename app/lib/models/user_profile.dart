import 'package:cloud_firestore/cloud_firestore.dart';

import '../l10n/app_language.dart';

/// The user document at `users/{uid}` (CLAUDE.md §4).
///
/// Currently just the chosen assistant name + creation time. Pure data class.
class UserProfile {
  const UserProfile({
    required this.uid,
    required this.assistantName,
    this.defaultRadiusMeters = defaultRadius,
    this.preferredLanguage = AppLanguage.english,
    this.familyId,
    this.createdAt,
  });

  final String uid;

  /// User-chosen assistant name, default "Surya". Shown in UI, confirmations
  /// and notifications (CLAUDE.md §1).
  final String assistantName;

  /// Radius (metres) pre-filled for new reminders. User-editable in Settings
  /// (Phase 5); overridable per-reminder on the add screen.
  final int defaultRadiusMeters;

  /// Language Hanu speaks/listens/renders in (CLAUDE.md Phase 9). Default
  /// English; backward compatible (an absent field reads as English).
  final AppLanguage preferredLanguage;

  /// The family this user belongs to, if any (CLAUDE.md §10, Phase 7a).
  /// Null for solo users — the family layer is entirely additive, so every
  /// existing single-user flow keeps working with this unset.
  final String? familyId;

  final DateTime? createdAt;

  /// Default assistant name used until onboarding sets one.
  static const String defaultAssistantName = 'Surya';

  /// Default geofence radius (metres) until the user changes it (CLAUDE.md §4).
  static const int defaultRadius = 500;

  factory UserProfile.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final radius = (data['defaultRadiusMeters'] as num?)?.toInt();
    return UserProfile(
      uid: doc.id,
      assistantName:
          (data['assistantName'] as String?)?.trim().isNotEmpty == true
              ? (data['assistantName'] as String).trim()
              : defaultAssistantName,
      defaultRadiusMeters:
          (radius != null && radius > 0) ? radius : defaultRadius,
      preferredLanguage:
          AppLanguage.fromCode(data['preferredLanguage'] as String?),
      familyId: (data['familyId'] as String?)?.trim().isNotEmpty == true
          ? (data['familyId'] as String).trim()
          : null,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
