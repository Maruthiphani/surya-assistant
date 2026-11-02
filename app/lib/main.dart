import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/messaging_service.dart';

/// Entry point for the Surya app.
///
/// Firebase is initialized before the first frame (so auth/Firestore are ready),
/// then the tree is wrapped in a [ProviderScope] making Riverpod providers
/// available everywhere. Keeping [main] thin leaves the app shell in [SuryaApp].
Future<void> main() async {
  // Required before any async work ahead of runApp.
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Offline-first (CLAUDE.md §9): Firestore keeps a local cache and queues
  // writes while offline, syncing them automatically on reconnect. Persistence
  // is on by default on mobile, but we set it explicitly (unlimited cache) so
  // reminders survive restarts and simple reminders work fully offline.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Register the FCM background handler before runApp (must be a top-level
  // function, see messaging_service.dart).
  registerMessagingBackgroundHandler();

  runApp(
    const ProviderScope(
      child: SuryaApp(),
    ),
  );
}
