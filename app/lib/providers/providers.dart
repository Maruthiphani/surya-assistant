import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/reminder.dart';
import '../models/user_profile.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/geofence_coordinator.dart';
import '../services/intent_channel.dart';
import '../services/location_service.dart';
import '../services/messaging_service.dart';
import '../services/notification_service.dart';
import '../services/parsing_metrics.dart';
import '../services/reminder_composer.dart';
import '../services/reminder_repository.dart';
import '../services/subscription_service.dart';
import '../services/speech_service.dart';
import '../services/user_repository.dart';

/// Central Riverpod wiring. Screens read these providers instead of constructing
/// services directly, which keeps dependencies swappable and testable (override
/// a provider in a widget test to inject a fake).

// --- Service singletons -----------------------------------------------------

final authServiceProvider = Provider<AuthService>((ref) {
  return FirebaseAuthService();
});

final userRepositoryProvider = Provider<UserRepository>((ref) {
  return FirestoreUserRepository();
});

final reminderRepositoryProvider = Provider<ReminderRepository>((ref) {
  return FirestoreReminderRepository();
});

final aiServiceProvider = Provider<AiService>((ref) {
  return HttpAiService();
});

/// Observability counters for the hybrid parser (§9).
final parsingMetricsProvider = Provider<ParsingMetrics>((ref) => ParsingMetrics());

/// Local-first reminder composition: on-device parse → clarify → LLM fallback.
final reminderComposerProvider = Provider<ReminderComposer>((ref) {
  return ReminderComposer(
    aiService: ref.watch(aiServiceProvider),
    metrics: ref.watch(parsingMetricsProvider),
  );
});

final notificationServiceProvider = Provider<NotificationService>((ref) {
  return LocalNotificationService();
});

/// Firebase Cloud Messaging (push). Token registration + foreground handling.
final messagingServiceProvider = Provider<MessagingService>((ref) {
  return FcmMessagingService();
});

/// Billing / Pro entitlement (RevenueCat, Phase 6).
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return RevenueCatSubscriptionService();
});

final speechServiceProvider = Provider<SpeechService>((ref) {
  return SttSpeechService();
});

/// Bridge for text handed in by a platform entry point (iOS Siri Shortcut).
final intentChannelProvider = Provider<IntentChannel>((ref) {
  return IntentChannel();
});

final locationServiceProvider = Provider<LocationService>((ref) {
  final service = GeofenceLocationService();
  ref.onDispose(() => service.stop());
  return service;
});

/// Long-lived coordinator wiring geofence ENTER → notification + status update.
final geofenceCoordinatorProvider = Provider<GeofenceCoordinator>((ref) {
  final coordinator = GeofenceCoordinator(ref);
  ref.onDispose(coordinator.dispose);
  return coordinator;
});

// --- Auth state -------------------------------------------------------------

/// The signed-in Firebase user, or null. Drives top-level routing (AuthGate).
final authStateProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges();
});

/// Convenience: the current uid, or null when signed out.
final currentUidProvider = Provider<String?>((ref) {
  return ref.watch(authStateProvider).valueOrNull?.uid;
});

// --- Per-user data ----------------------------------------------------------

/// Live profile for the signed-in user. Null (data) means "not onboarded yet".
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchProfile(uid);
});

/// Live reminder list for the signed-in user.
final remindersProvider = StreamProvider<List<Reminder>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(reminderRepositoryProvider).watchReminders(uid);
});

/// True while there are local reminder writes awaiting sync (offline queue).
/// Drives the home "changes will sync" banner (Phase 5).
final pendingSyncProvider = StreamProvider<bool>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(false);
  return ref.watch(reminderRepositoryProvider).watchPendingSync(uid);
});

/// Live Pro-entitlement status (Phase 6). False when billing is unavailable.
final isProProvider = StreamProvider<bool>((ref) {
  return ref.watch(subscriptionServiceProvider).proStatus;
});

/// Count of currently active reminders — the figure the free-tier cap applies
/// to (CLAUDE.md §1).
final activeReminderCountProvider = Provider<int>((ref) {
  final list = ref.watch(remindersProvider).valueOrNull ?? const [];
  return list.where((r) => r.status == ReminderStatus.active).length;
});
