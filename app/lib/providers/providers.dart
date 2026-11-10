import 'package:firebase_auth/firebase_auth.dart';
// Hide Riverpod's internal `Family` type so it doesn't clash with our
// models/family.dart `Family` (Phase 7a).
import 'package:flutter_riverpod/flutter_riverpod.dart' hide Family;

import '../l10n/app_language.dart';
import '../l10n/app_strings.dart';
import '../models/family.dart';
import '../models/idea.dart';
import '../models/inventory_item.dart';
import '../models/reminder.dart';
import '../models/user_profile.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';
import '../services/family_repository.dart';
import '../services/idea_repository.dart';
import '../services/inventory_repository.dart';
import '../services/geofence_coordinator.dart';
import '../services/intent_channel.dart';
import '../services/location_service.dart';
import '../services/messaging_service.dart';
import '../services/notification_service.dart';
import '../services/parsing_metrics.dart';
import '../services/reminder_composer.dart';
import '../services/reminder_repository.dart';
import '../services/reminder_scheduler.dart';
import '../services/store_matcher.dart';
import '../services/subscription_service.dart';
import '../services/speech_service.dart';
import '../services/tts_service.dart';
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

/// Shared family group membership (CLAUDE.md §10, Phase 7a).
final familyRepositoryProvider = Provider<FamilyRepository>((ref) {
  return FirestoreFamilyRepository();
});

/// Shared/personal inventory items (CLAUDE.md §10, Phase 7b).
final inventoryRepositoryProvider = Provider<InventoryRepository>((ref) {
  return FirestoreInventoryRepository();
});

/// Private "My Ideas" notes (CLAUDE.md Phase 10).
final ideaRepositoryProvider = Provider<IdeaRepository>((ref) {
  return FirestoreIdeaRepository();
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

/// Schedules time-based / recurring reminders as local notifications (Phase 8).
final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return LocalReminderScheduler();
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

/// Text-to-speech so Hanu can speak back in the chosen language (Phase 9).
final ttsServiceProvider = Provider<TtsService>((ref) {
  return FlutterTtsService();
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

/// Best display name for the signed-in user (Google name → email local-part →
/// "Member"). Used to stamp inventory edits and populate `memberNames`.
final currentDisplayNameProvider = Provider<String>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  final name = user?.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final email = user?.email?.trim();
  if (email != null && email.contains('@')) return email.split('@').first;
  return 'Member';
});

// --- Per-user data ----------------------------------------------------------

/// Live profile for the signed-in user. Null (data) means "not onboarded yet".
final userProfileProvider = StreamProvider<UserProfile?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(null);
  return ref.watch(userRepositoryProvider).watchProfile(uid);
});

/// The user's chosen language (Phase 9), from their profile. Default English.
final appLanguageProvider = Provider<AppLanguage>((ref) {
  return ref.watch(userProfileProvider).valueOrNull?.preferredLanguage ??
      AppLanguage.english;
});

/// Localized UI strings for the current language. Screens read this instead of
/// hard-coding English chrome.
final stringsProvider = Provider<AppStrings>((ref) {
  return AppStrings.of(ref.watch(appLanguageProvider));
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

// --- Family (Phase 7a) ------------------------------------------------------

/// The family this user points at, from their profile, or null for solo users.
final familyIdProvider = Provider<String?>((ref) {
  return ref.watch(userProfileProvider).valueOrNull?.familyId;
});

/// Live family document for the signed-in user. Data `null` means "no family"
/// (solo user, or the pointed-at family was disbanded — a stale pointer).
final familyProvider = StreamProvider<Family?>((ref) {
  final familyId = ref.watch(familyIdProvider);
  if (familyId == null || familyId.isEmpty) return Stream.value(null);
  return ref.watch(familyRepositoryProvider).watchFamily(familyId);
});

// --- Inventory (Phase 7b) ---------------------------------------------------

/// Which inventory the Inventory screen is showing. Defaults to Personal; the
/// user flips to Family only when they belong to one.
enum InventoryMode { personal, family }

/// Current Personal/Family toggle. A plain UI state (not persisted) — the data
/// itself lives in Firestore under the resolved [inventoryScopeProvider].
final inventoryModeProvider =
    StateProvider<InventoryMode>((ref) => InventoryMode.personal);

/// The resolved target for inventory reads/writes, or null when it can't be
/// resolved yet (signed out, or Family mode with no family).
final inventoryScopeProvider = Provider<InventoryScope?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  final mode = ref.watch(inventoryModeProvider);
  if (mode == InventoryMode.family) {
    final familyId = ref.watch(familyIdProvider);
    if (familyId == null || familyId.isEmpty) return null;
    return InventoryScope.family(familyId);
  }
  return InventoryScope.personal(uid);
});

/// The signed-in user as an inventory writer (uid + display name), or null when
/// signed out. Stamped onto every add/edit/move so items show "updated by".
final inventoryActorProvider = Provider<InventoryActor?>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return InventoryActor(uid: uid, name: ref.watch(currentDisplayNameProvider));
});

/// Live items in the user's PERSONAL inventory. A source stream (watched
/// independently of the UI toggle) so background store-geofencing can see
/// personal needs even while the screen shows Family (Phase 7c).
final personalInventoryItemsProvider = StreamProvider<List<InventoryItem>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref
      .watch(inventoryRepositoryProvider)
      .watchItems(InventoryScope.personal(uid));
});

/// Live items in the user's FAMILY inventory (empty for solo users). Source
/// stream, as above.
final familyInventoryItemsProvider = StreamProvider<List<InventoryItem>>((ref) {
  final familyId = ref.watch(familyIdProvider);
  if (familyId == null || familyId.isEmpty) return Stream.value(const []);
  return ref
      .watch(inventoryRepositoryProvider)
      .watchItems(InventoryScope.family(familyId));
});

/// Live items for the CURRENT scope (both lists), newest-updated first — what
/// the Inventory screen shows. Picks the right source stream from the toggle so
/// a collection is only listened to once.
final inventoryItemsProvider = Provider<AsyncValue<List<InventoryItem>>>((ref) {
  final scope = ref.watch(inventoryScopeProvider);
  if (scope == null) return const AsyncValue.data([]);
  return scope.isFamily
      ? ref.watch(familyInventoryItemsProvider)
      : ref.watch(personalInventoryItemsProvider);
});

/// "Present Items" — already at home (current scope).
final presentItemsProvider = Provider<List<InventoryItem>>((ref) {
  final items = ref.watch(inventoryItemsProvider).valueOrNull ?? const [];
  return items.where((i) => i.isPresent).toList(growable: false);
});

/// "Need to Buy" — still to purchase (current scope).
final neededItemsProvider = Provider<List<InventoryItem>>((ref) {
  final items = ref.watch(inventoryItemsProvider).valueOrNull ?? const [];
  return items.where((i) => i.isNeeded).toList(growable: false);
});

/// Category/store heuristics for matching needed items to stores (Phase 7c/7d).
final storeMatcherProvider = Provider<StoreMatcher>((ref) => const StoreMatcher());

// --- My Ideas (Phase 10) ----------------------------------------------------

/// Live list of the signed-in user's ideas, newest first.
final ideasProvider = StreamProvider<List<Idea>>((ref) {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return Stream.value(const []);
  return ref.watch(ideaRepositoryProvider).watchIdeas(uid);
});

/// Current search query for the Ideas screen (plain UI state).
final ideaSearchProvider = StateProvider<String>((ref) => '');

/// Ideas filtered by [ideaSearchProvider] (case-insensitive over title + body).
final filteredIdeasProvider = Provider<List<Idea>>((ref) {
  final ideas = ref.watch(ideasProvider).valueOrNull ?? const [];
  final query = ref.watch(ideaSearchProvider);
  return ideas.where((i) => i.matches(query)).toList(growable: false);
});

/// A needed inventory item paired with the scope it lives in — so a store-entry
/// alert knows which inventory to flip on "Bought". Spans personal + family.
typedef ScopedItem = ({InventoryScope scope, InventoryItem item});

/// All currently-needed items across the personal AND family inventories, each
/// tagged with its scope. This is what drives store geofencing + alerts (Phase
/// 7c), independent of which list the Inventory screen is showing.
final geofenceNeedsProvider = Provider<List<ScopedItem>>((ref) {
  final uid = ref.watch(currentUidProvider);
  final familyId = ref.watch(familyIdProvider);
  final out = <ScopedItem>[];
  if (uid != null) {
    final personal = ref.watch(personalInventoryItemsProvider).valueOrNull ?? const [];
    for (final i in personal.where((i) => i.isNeeded)) {
      out.add((scope: InventoryScope.personal(uid), item: i));
    }
  }
  if (familyId != null && familyId.isNotEmpty) {
    final family = ref.watch(familyInventoryItemsProvider).valueOrNull ?? const [];
    for (final i in family.where((i) => i.isNeeded)) {
      out.add((scope: InventoryScope.family(familyId), item: i));
    }
  }
  return out;
});
