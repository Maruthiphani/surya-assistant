# Surya — Progress Log

Updated after each phase (CLAUDE.md §5). One phase at a time; a phase is "done"
only when confirmed on a real iPhone.

---

## Phase 0 — Environment & scaffold

**Date:** 2026-10-22
**Status:** Scaffold complete. Pending on-device `flutter run` (needs a Mac +
Xcode — see "Known issues").

### What was built
- **Monorepo layout** (CLAUDE.md §6): `app/` (Flutter) + `backend/` (FastAPI),
  with `CLAUDE.md` and this `PROGRESS.md` at the root.
- **Flutter app** (`app/`): created with `--org com.suryaapp --project-name
  surya --platforms ios,android` (mobile only — no web/desktop).
  - Riverpod added (`flutter_riverpod`); `ProviderScope` wraps the app in
    `lib/main.dart`.
  - Layered structure: `lib/app.dart` (MaterialApp shell), `lib/theme/`
    (`AppTheme`, Material 3, single seed colour), `lib/screens/home_screen.dart`
    (a `ConsumerWidget` placeholder), and `models/ services/ providers/`
    directories with READMEs describing their Phase 1+ contents.
  - Smoke test in `test/widget_test.dart` replaces the default counter test.
  - **No Firebase yet** (per Phase 0 instructions).
- **Backend** (`backend/`): FastAPI skeleton.
  - `app/main.py` — public `GET /health` returning `{status, env}` (the only
    anonymous endpoint, per §5).
  - `app/config.py` — pydantic-settings config reading `$APP_ENV`, `$PORT`
    (Cloud Run compatible).
  - `Dockerfile` — Python **3.12**-slim, binds uvicorn to `$PORT`.
  - `requirements.txt` (minimal: fastapi, uvicorn, pydantic, pydantic-settings,
    pytest, httpx), `.env.example`, `.dockerignore`.
  - `tests/test_health.py` — asserts `/health` → 200.
- **.gitignore**: root + `app/` (Flutter default) + `backend/`. Secrets
  (`.env`, `google-services.json`, `GoogleService-Info.plist`, service-account
  JSON) are ignored everywhere.
- **Git**: repository initialised with an initial commit.

### Tested
- `flutter analyze` → **0 issues**.
- `flutter test` → **1 passing** (app boots, home screen renders).
- Backend `pytest` → **1 passing** (`/health` 200) on local Python 3.13 venv.
- **Not yet tested on a physical iPhone.**

### How to run
- Flutter: `cd app && flutter run` (needs a connected device/simulator).
- Backend (local): `cd backend && uvicorn app.main:app --reload` then
  `GET http://localhost:8000/health`.
- Backend (docker): `docker build -t surya-api backend/ && docker run -p
  8080:8080 surya-api`.

### Known issues / notes
- **iPhone run is pending**: the dev machine for this scaffold is Windows, so
  building for a connected iPhone (the Phase 0 "done" criterion) must be done on
  a Mac with Xcode. Everything else (analyze, tests, Android build inputs) is in
  place for that step.
- Local backend venv uses Python 3.13; the Docker image pins 3.12 to match the
  spec — the source of truth for deploys.
- A few transitive Flutter packages have newer versions available; left pinned
  to the Flutter 3.27.3 stable constraints (no action needed).

---

## Phase 0 — Local verification on Windows (Android emulator target)

**Date:** 2026-10-22 (updated 2026-10-23)
**Status:** Verified on Windows — analyze/tests green, backend `/health` 200,
and **Surya runs on an Android emulator with the Home Screen rendering
correctly**. iPhone verification remains pending (needs Mac + Xcode).

### `flutter doctor -v` summary
- [√] Flutter 3.27.3 (stable), Dart 3.6.1 — OK.
- [√] VS Code + Flutter extension 3.144.0 — OK.
- [√] Chrome, Visual Studio Build Tools 2019 — OK (not used; mobile-only).
- [X] **Android toolchain — Android SDK not found.**
- [!] **Android Studio — not installed.**
- Connected devices: Windows desktop, Chrome, Edge only. **No Android device/emulator.**
- `flutter emulators` → no AVDs available.
- Note: the "Windows Version" doctor check crashes with
  `Failed to find "powershell" in the search path` — this is a doctor-only quirk
  of this shell (PowerShell not on PATH); it does not affect building or running.

### Verified green
- `flutter analyze` → **No issues found**.
- `flutter test` → **1 passing** (app boots, home screen renders).
- Backend `pytest` → **1 passing**.
- Backend `GET /health` → **HTTP 200** `{"status":"ok","env":"development"}`.
  - Verified on port **8010**: port 8000 was already occupied by an unrelated
    `uvicorn`/python process (returns 404 on `/health`, not ours). Free port 8000
    or run the backend on another port before testing on 8000.

### Android emulator setup (completed 2026-10-23)
Installed and configured so Surya runs on a local Android emulator on Windows:
- **Android Studio 2026.2.1.8** via `winget install -e --id Google.AndroidStudio`.
- **Android SDK** at `C:\Users\maruthi\AppData\Local\Android\Sdk` via the
  command-line tools (`sdkmanager`): `platform-tools` (37.0.1), `emulator`
  (37.2.12), `platforms;android-35`, `build-tools;35.0.0` (plus `33.0.1` pulled
  in by the build), and `system-images;android-35;google_apis;x86_64`.
  Licenses accepted (`flutter doctor --android-licenses`).
- **AVD** `surya_pixel` (Pixel 7, android-35, x86_64) created with `avdmanager`.
- `flutter config --android-sdk "<sdk path>"`.

### Issue fixed: Gradle/JDK incompatibility
The first `flutter run` failed with *"Unsupported class file major version 69"* —
Android Studio 2026.2 bundles a **Java 25** runtime (JBR), but the generated
project's **Gradle 8.3 + AGP 8.1.0** only supports up to Java 20.
**Fix (no project/architecture changes):** installed **Temurin JDK 17**
(extracted to `C:\Users\maruthi\jdk17\jdk-17.0.20.1+1`, no admin needed) and
pointed Flutter at it with `flutter config --jdk-dir "<jdk17>"`. Gradle, AGP,
and Kotlin versions in the project were left untouched.

### Android run — VERIFIED
- `flutter run -d emulator-5554` → APK built + installed, app launched
  (`com.suryaapp.surya/.MainActivity` in foreground).
- **Home Screen renders correctly** (verified via screenshot): app bar "Surya",
  location-pin icon, "Surya is ready", "Phase 0 scaffold — voice and location
  reminders coming soon." Material 3 theme applied.

### Blocked / remaining
- **iPhone verification still pending** (needs Mac + Xcode) — unchanged, per
  the Phase 0 "done" criterion.
- Port 8000 is occupied on this machine by an unrelated uvicorn process; run the
  Surya backend on another port (e.g. 8010) or free 8000 first.

---

## Phase 1 — Auth + onboarding + Firestore CRUD

**Date:** 2026-10-23
**Status:** ✅ Complete and verified on the Android emulator — Google Sign-In,
assistant-name onboarding, and reminder CRUD with a live Firestore listener all
working under secure rules. iPhone verification still pending (needs Mac + Xcode).

### What was built (Dart)
- **Models**: `reminder.dart` (+ `ReminderStatus` enum), `user_profile.dart` —
  pure data classes with Firestore (de)serialization, mapping to CLAUDE.md §4.
- **Services (behind interfaces, §5)**:
  - `AuthService` / `FirebaseAuthService` — Google Sign-In implemented; Apple
    stubbed (throws a friendly "coming soon" until we're on a Mac).
  - `UserRepository` / `FirestoreUserRepository` — `users/{uid}` profile; live
    `watchProfile`, `setAssistantName` (merge write + server timestamp).
  - `ReminderRepository` / `FirestoreReminderRepository` — `watchReminders`
    (live snapshot stream, newest first), `addReminder`, `updateStatus`,
    `deleteReminder`.
- **Providers** (`providers/providers.dart`): service singletons, `authStateProvider`,
  `currentUidProvider`, `userProfileProvider`, `remindersProvider`.
- **Screens**: `login_screen` (Google live / Apple disabled), `onboarding_screen`
  (assistant name → `users/{uid}`), `home_screen` (live reminder list + status
  chips + empty state + sign-out), `add_reminder_screen` (manual task + location,
  placeholder lat/lng until Phase 3), and `auth_gate` (routes login → onboarding
  → home from auth + profile streams).
- `main.dart` initializes Firebase before `runApp`.
- Removed the now-redundant placeholder READMEs in models/services/providers.

### Firebase / security
- FlutterFire configured (project `surya-assistance`): `firebase_options.dart`,
  `android/app/google-services.json`. (iOS plist to be regenerated on the Mac.)
- **Secure Firestore rules** written (`firestore.rules`) and **deployed**: a user
  can read/write only their own `users/{uid}` and `users/{uid}/reminders/**`;
  everything else denied. Replaced the temporary test-mode rules. `firebase.json`
  + `.firebaserc` added for `firebase deploy --only firestore:rules`.

### Build-config changes forced by the Firebase 7.x Android SDKs
Each was the minimum needed to make the chosen stack compile (no app/architecture
changes):
- `minSdk` 21 → **24** (cloud_firestore requirement).
- Kotlin Gradle plugin 1.8.22 → **2.4.0** (Firebase SDKs ship Kotlin 2.4 metadata).
- Android Gradle Plugin 8.1.0 → **8.5.2** (required by Kotlin 2.4).
- Gradle 8.3 → **8.7** (required by AGP 8.5.2). JDK 17 already satisfies AGP 8.5.

### Verified on the emulator
- `flutter analyze` → **No issues found**; `flutter test` → **passing** (login
  shows when signed out, with `authStateProvider` overridden — no real Firebase).
- App **builds, installs, runs**; Firebase/Auth/Firestore plugins initialize with
  no Dart exceptions.
- **Login screen renders correctly** (verified via screenshot).
- **Google Sign-In → onboarding → Home verified by developer** (after adding the
  debug SHA-1). Chosen assistant name ("Hanu") saved to `users/{uid}` and shown
  in the Home app bar — confirms the profile write/read + security rules work
  with real auth. Home empty state renders correctly.
- **Add-reminder → live list verified by developer**: a reminder created via the
  add-reminder form appears in the Home list via the Firestore live listener
  (write → `users/{uid}/reminders` under the security rules → snapshot → UI).

### Phase 1 result
Complete and verified on the Android emulator: sign-in, assistant-name
onboarding, and reminder CRUD with a live Firestore listener all work under the
secure rules. iPhone verification remains pending (needs Mac + Xcode).

### Known issues / caveats
- **Emulator rendering**: with the default Impeller/Vulkan backend this emulator
  intermittently shows a blank white screen (its host-GPU Vulkan became unstable
  during a long session). Workaround that renders reliably: boot the emulator
  with `-gpu swiftshader_indirect` and/or run `flutter run --no-enable-impeller`.
  This is an emulator/GPU quirk, not an app bug — Impeller remains the default for
  real devices.
- **Google Sign-In needs the debug SHA-1** registered in Firebase (otherwise it
  fails with ApiException 10). Debug SHA-1:
  `17:33:96:BE:BF:C4:2E:91:C4:45:79:5A:CC:05:CB:8C:AA:C1:14:F0`. After adding it
  in the console, re-download `google-services.json` (or re-run
  `flutterfire configure`). Testing sign-in on the emulator also needs a Google
  account added to the emulator.
- **iPhone verification still pending** (needs Mac + Xcode) — unchanged.

---

## Phase 2 — Geofencing + local notifications

**Date:** 2026-10-24
**Status:** Code complete; builds and runs on the Android emulator. The core
trigger path (geofence ENTER → notification → `status=triggered`, idempotent) is
**verified** via the in-app debug simulator. Live OS-geofence firing is best
confirmed on a real device (emulator `geo fix` is unreliable). iPhone
verification still pending.

### What was built (Dart)
- **`NotificationService` / `LocalNotificationService`** (flutter_local_notifications):
  creates a high-importance `surya_reminders` channel, requests POST_NOTIFICATIONS
  (Android 13+) / iOS permission, and shows "<assistantName> reminder — You're
  near <place> — <task>." on trigger.
- **`LocationService` / `GeofenceLocationService`** (geofence_service + geolocator):
  owns the geofence engine; registers one geofence per *active* reminder;
  exposes `onEnter` (reminder id stream). Permission helpers implement the
  When-In-Use → Always flow (geolocator). `allowMockLocations: true` for testing.
- **`GeofenceCoordinator`**: on ENTER (real or simulated) fires the notification
  and sets `status=triggered` — only if still `active`, so a reminder never fires
  twice (§5). `syncActiveReminders()` keeps geofences in step with the list;
  `simulateEnter()` runs the identical path for the debug screen.
- **Screens**: `location_permission_screen` (When-In-Use → explanation → Always),
  `debug_screen` (per-reminder "Simulate ENTER"). Home now bootstraps
  notifications + geofence tracking, shows a "location off" banner when needed,
  and re-syncs geofences when reminders change (+ debug entry in the app bar).

### Native config
- **Android** (`AndroidManifest.xml`): FINE/COARSE/BACKGROUND location,
  POST_NOTIFICATIONS, FOREGROUND_SERVICE(+LOCATION), WAKE_LOCK,
  RECEIVE_BOOT_COMPLETED. Core-library desugaring enabled (required by
  flutter_local_notifications 19).
- **iOS** (`Info.plist`): `NSLocationWhenInUseUsageDescription`,
  `NSLocationAlwaysAndWhenInUseUsageDescription`, Background Modes → location
  (configured now; exercised on the Mac later).

### Toolchain upgrade (approved) — root-cause fix
The Phase 2 packages require Flutter ≥ 3.29 / Dart ≥ 3.7. **Upgraded Flutter
3.27.3 → 3.47.8 (Dart 3.13.7)**, which resolved the `toARGB32` / `js_interop` /
web-plugin-exclusion compile errors. That then required Android toolchain bumps
(all build-config only): **Gradle 8.7 → 8.14**, **AGP 8.5.2 → 8.11.1** (Kotlin
2.4.0, minSdk 24 as before). Note: `flutter`/tooling now needs PowerShell on PATH
(`C:\Windows\System32\WindowsPowerShell\v1.0`).

### Verified on the emulator
- `flutter analyze` → **No issues found**; `flutter test` → **passing**.
- App **builds, installs, runs**; Home renders; location banner correctly hides
  once location permission is granted.
- **Trigger path verified** via Debug → *Simulate ENTER* (screenshot): heads-up
  notification *"Hanu reminder — You're near Costco — Rice."* fired, reminder
  flipped **active → triggered**, and the Simulate button became **disabled**
  (idempotent — won't re-fire). `triggered` round-tripped through Firestore.

### Known issues / caveats
- **Live OS geofence on emulator**: `adb emu geo fix` did not reliably trigger
  the geofence_service engine on the emulator (common emulator/fused-location
  limitation). The debug simulator verifies the business logic; real geofence
  firing should be confirmed on a physical device.
- **Emulator stability**: launching the AVD from a headless shell is flaky
  (Impeller/Vulkan blank screen on host GPU; ANRs on software GPU). Reliable
  combo used: host-GPU emulator + `flutter run --no-enable-impeller`. On a
  normally-launched emulator (e.g. from VS Code) the default Impeller works.
- **iPhone verification still pending** (needs Mac + Xcode) — unchanged.

### How to test geofencing (emulator & device)
- **Emulator (logic):** app bar bug icon → *Simulate ENTER* on an active reminder
  → notification fires + status → triggered.
- **Emulator (live engine):** grant location "Allow all the time", then
  `adb emu geo fix <lng> <lat>` at the reminder's coordinates (unreliable).
- **iPhone (Xcode simulated location):** run from Xcode → Debug → Simulate
  Location, or add a GPX file, and set it to the reminder's coordinates; or
  Features → Location in the iOS Simulator. Confirm the notification fires once
  on entry and the reminder never fires again.

---

## Phase 3 — Backend AI + dynamic discovery

**Date:** 2026-10-24
**Status:** **Backend + app-side built and verified (mocked/debug).** Dynamic
chain/category reminders work end-to-end in the app via the debug simulator.
**Gemini key confirmed VALID** (2026-10-26, HTTP 200 on model-list) — the `AQ.`
format is the current Gemini key format. Fixed the model: `gemini-2.0-flash`
(retired) → `gemini-flash-latest`; added 429/503 retry. Live `/v1/parse` not yet
demoed only because the Gemini API was returning transient 503/429 (high demand).
Remaining: a **Places-enabled** key for real discovery + Cloud Run deploy. iPhone pending.

### Backend built (`/backend`)
- `schemas.py` — Pydantic models incl. `locationType` specific/query, parse /
  nearby / confirm contracts (CLAUDE.md §4).
- `gemini.py` — `AiExtractor` interface + `GeminiExtractor` (google-genai,
  structured JSON). Mockable.
- `places.py` — `PlacesClient` interface + `GooglePlacesClient` (Places API v1
  Text Search; `find_candidates` for specific, `find_nearby` nearest-first for
  dynamic). Mockable.
- `graph.py` — LangGraph flow: extract → validate (retry once, else 422) →
  places-if-specific. `query` reminders carry the search term; no branch chosen.
- `auth.py` — Firebase ID-token verification dependency (lazy init; `AUTH_DISABLED`
  dev bypass).
- `deps.py` / `tracing.py` — DI providers (503 when unconfigured; Places degrades
  to no candidates in parse) + defensive no-op Langfuse tracing.
- `main.py` — `GET /health`, `POST /v1/parse`, `POST /v1/nearby`, `POST /v1/confirm`.
- `requirements.txt` (google-genai, langgraph, firebase-admin, langfuse),
  `.env.example`, `deploy.sh` (Cloud Run + Secret Manager).

### Verified
- `pytest` → **9 passing** (real LangGraph flow with fake Gemini/Places:
  query-vs-specific, retry-once, invalid→422; /v1/nearby incl. 503-when-unconfigured
  + limit; /v1/confirm message).
- Live local boot (uvicorn, `AUTH_DISABLED=true`): `/health` 200, `/v1/confirm`
  correct, `/v1/nearby` → 503 (Places not configured, as designed).

### App side — built & verified (mock/debug)
- **Reminder model + repo**: added `locationType` (specific|query) + `locationQuery`;
  `lat/lng/address` now optional; backward compatible (legacy docs with coords →
  specific). `toMap`/`fromFirestore`/`copyWith` updated.
- **`AiService`** (`ai_service.dart`): dart:io HTTP client for `/v1/parse`,
  `/v1/nearby`, `/v1/confirm`, attaching the Firebase ID token; base URL in
  `config/app_config.dart` (`10.0.2.2:8011` for emulator → host; override via
  `--dart-define=API_BASE_URL`).
- **LocationService**: generalised to `syncGeofences(List<GeofenceSpec>)` (one
  reminder can map to many branch geofences) + `onLocation` stream +
  `currentLatLng()`.
- **GeofenceCoordinator**: specific → one geofence; dynamic → discover branches
  via `/v1/nearby` and register one geofence per branch (id `reminderId::index`);
  caps to nearest 20 (OS budget); refreshes when the user moves ≥ 2 km (coarse
  location updates, not a GPS loop); fires once on ANY branch (idempotent).
- **AddReminderScreen**: "Match any branch" toggle (dynamic by default) — no
  picker for dynamic; specific still available.
- Android manifest: `usesCleartextTraffic` (dev, for local http backend).

### Verified
- `flutter analyze` clean; `flutter test` passing; backend `pytest` 9 passing.
- On the emulator: created a **dynamic** reminder ("buy milk" / "Walmart", Match
  any branch ON) → saved as `query` to Firestore and shown in the live list;
  Debug → Simulate ENTER fired the correct notification **"Hanu reminder — You're
  near Walmart — buy milk."** Legacy specific reminder ("Rice"/"Costco") still
  works (backward compat). Toggle correctly switches specific/dynamic UI.

### Remaining in Phase 3 (blocked on key / deferred)
- **Valid `AIza…` Gemini key** (+ Places-enabled key) → live `/v1/parse` and real
  branch discovery/geofencing (`/v1/nearby`). Code paths are built; discovery is
  skipped gracefully when Places is unconfigured.
- **Cloud Run deploy** (deferred; `deploy.sh` ready).

### Known caveats
- Emulator rendering/ANR flakiness persists when launched headlessly; functional
  checks were confirmed via notification/dumpsys when the display froze.

---

## Phase 3.5 — Hybrid local-first parsing (CLAUDE.md §9)

**Date:** 2026-10-26
**Status:** **Implemented and unit-verified.** The on-device parser + composer
handle common commands with no LLM call; Gemini is now a fallback. Wiring into
the mic button + confirmation screen is Phase 4. iPhone pending.

### Built (Dart, `app/lib`)
- `parsing/time_grammar.dart` — recognises + strips time expressions (clock,
  `tomorrow [morning]`, `in N hours`, `[next] weekday`), resolving a best-effort
  `remindAt`. This is what stops "5 PM" being read as a place.
- `parsing/place_dictionaries.dart` — small chain/category/saved-place sets +
  `typeLocation` → specific / query / **unknown** (unknown ⇒ fall back).
- `parsing/intent_parser.dart` — normalise → "remind me" anchor → time-first →
  split on location connector → type location. **Structural gate** (not a float)
  yields `RESOLVED | CLARIFY | UNPARSEABLE`.
- `models/parsed_intent.dart`; `models/reminder.dart` gained optional `remindAt`
  (recognised, not yet scheduled — location is still the trigger).
- `services/reminder_composer.dart` — orchestrates local parse → RESOLVED draft /
  CLARIFY question / LLM fallback (`AiService.parse`), with an LRU cache keyed on
  the **time-stripped** transcript (so "tomorrow" is never cached).
- `services/parsing_metrics.dart` + `utils/lru_cache.dart` — minimal counters
  (local-resolved / clarify / fallback / errors, fallback rate) and the cache.
- Providers: `parsingMetricsProvider`, `reminderComposerProvider`.

### Verified (`flutter test` — 22 passing, + analyze clean)
- Golden corpus: the 5 example commands parse correctly.
- Accuracy: "call Mom at 5 PM" → time recognised (17:00), **not** a location →
  CLARIFY for a place; "buy rice at Costco tomorrow" → **both** location (query)
  and time extracted → RESOLVED.
- Routing: unknown place / multi-instruction / no-anchor → UNPARSEABLE → LLM.
- Composer: local RESOLVED/CLARIFY make **zero** backend calls; UNPARSEABLE hits
  the (fake) LLM once and caches it; offline+unparseable → `ComposeFailed` (never
  a silently-wrong reminder). Metrics increment correctly.

### Estimated impact (ASSUMPTIONS — not yet measured)
- If 70–85% of real commands fit the templates, Gemini calls drop ~70–85% and
  those commands resolve in <5 ms locally vs a ~0.4–1.5 s round-trip. The metrics
  counters exist specifically to replace these assumptions with real numbers once
  voice (Phase 4) is wired.

### Remaining / deferred
- **Phase 4** wires `ReminderComposer` to the mic button + always-on confirmation
  screen (local-first; LLM only on UNPARSEABLE; offline-capable).
- Live Gemini/Places keys + Cloud Run deploy (unchanged from Phase 3).

---

## Phase 4 — Voice + full wiring (local-first)

**Date:** 2026-10-27
**Status:** **Implemented; full flow verified on the emulator via the text path
(offline).** Real speech recognition + live LLM/Places need a device + network
(spec's "end-to-end on iPhone" remains the DoD). iPhone verification pending.

### Built
- `services/speech_service.dart` — `speech_to_text` behind an interface.
- `screens/voice_capture_screen.dart` — mic button (live transcript) **+ a typed
  fallback** (so the flow is testable without a working emulator mic). Routes the
  transcript through `ReminderComposer` (§9): RESOLVED/CLARIFY open the review
  screen prefilled; UNPARSEABLE already hit the LLM inside the composer; failures
  show a retry message.
- `screens/pick_location_screen.dart` — candidate picker for specific places (>1).
- `AddReminderScreen` upgraded into the **always-on editable confirmation**
  screen: accepts a prefill `Reminder`; dynamic saves offline; specific geocodes
  via `/v1/nearby` (picker if >1); shows a parsed time note; calls `/v1/confirm`
  (local fallback offline).
- Home: **"Speak" mic FAB** (primary) + manual add moved to an app-bar "+".
- Permissions: Android `RECORD_AUDIO` + speech query; iOS mic/speech usage strings.
- Providers: `speechServiceProvider`. `ComposeClarify` now carries a prefill draft.

### Verified (`flutter analyze` clean, 22 tests pass; on emulator — offline)
- Home shows the mic **"Speak"** FAB; voice capture screen renders (mic + text
  fallback).
- Typed *"remind me to buy eggs at Target"* → parsed **on-device (no network/LLM)**
  → RESOLVED → review screen prefilled (task "buy eggs", "target", Match-any-branch
  ON) → **Save** → reminder appears in the live list as **"buy eggs at target ·
  active"** → confirmation snackbar *"Got it — I'll remind you to buy eggs when you
  reach target."* (offline local-fallback message).
- Offline graceful degradation confirmed (Firestore cache write; `/v1/confirm`
  fallback).

### Not verified on emulator (needs device/network — acceptable)
- Actual **speech recognition** (emulator has no usable mic) — text path proves the
  downstream wiring; real voice is a device task.
- **LLM fallback** (`/v1/parse`) + **specific-place geocoding** (`/v1/nearby`) +
  live `/v1/confirm` — emulator was offline this session; Gemini also still
  rate-limited (503/429). Code paths are built + unit-tested with fakes.
- Real **geofence firing** — device task (per §8 definition of done).

### Phase 4 definition of done (§8)
On a real iPhone: speak a reminder → correct extraction (locally when possible) →
appears in list → walk into radius → notification fires once → complete → never
again. Still to be done on-device.

---
```
(demo loop built; remaining: on-device voice + live LLM/Places + geofence, Cloud
Run deploy. Then Phase 5 — push/sync/polish.)
```

---

## Phase 5 — Push, sync, settings, complete/cancel, Siri Shortcut

**Date:** 2026-10-28
**Status:** **Implemented; `flutter analyze` clean, 26 tests pass.** Verified on
the toolchain (analyze + unit tests). Native/push bits that need a device or
Firebase console setup are built but not device-verified (see below).

### Built (Dart, `app/lib`)
- **Settings screen** (`screens/settings_screen.dart`): rename the assistant and
  set a **default radius**. New `defaultRadiusMeters` on `UserProfile` (default
  500, backward compatible) + `UserRepository.setDefaultRadius`. `AddReminderScreen`
  now pre-fills radius from the profile default. Reachable from a new gear icon in
  the home app bar.
- **Complete / cancel / delete actions**: `_ReminderTile` is now a `ConsumerWidget`
  with an overflow menu wired to the existing `ReminderRepository.updateStatus` /
  `deleteReminder`. Dropping a reminder out of `active` removes its geofences
  automatically (home already listens to `remindersProvider` → `syncActiveReminders`).
- **Offline cache + sync-on-reconnect**: Firestore persistence enabled explicitly
  in `main.dart` (`persistenceEnabled`, unlimited cache). New
  `ReminderRepository.watchPendingSync` surfaces `snapshot.metadata.hasPendingWrites`
  via `pendingSyncProvider`; home shows an **offline/sync banner** while writes are
  queued. No new dependency — uses Firestore snapshot metadata.
- **Push (FCM)** (`services/messaging_service.dart`): `MessagingService` behind an
  interface. `firebase_messaging: ^17.0.1`. Uses the 17.x API (`register()` +
  `onRegistered` FID, not the deprecated token API). Registers the send-id under
  `users/{uid}/devices/{id}`, refreshes on rotation, clears on sign-out. Top-level
  `@pragma('vm:entry-point')` background handler registered in `main.dart`.
  Bootstrapped on home mount.
- **Siri Shortcut bridge** (`services/intent_channel.dart`): method channel
  `surya/intents`. Cold start → Flutter pulls `consumePendingReminder`; warm start →
  native pushes `prefillReminder`. Home routes the phrase into
  `VoiceCaptureScreen(initialText: …)` (new param) → `ReminderComposer` → confirm →
  save. Contract locked by `test/intent_channel_test.dart` (4 tests).

### Built (native iOS)
- `ios/Runner/SuryaIntents.swift`: `AddReminderIntent` (App Intent, iOS 16+,
  `openAppWhenRun`) + `SuryaShortcuts` AppShortcutsProvider ("Tell <app> to remind
  me", "Ask <app> to remind me", "Add a reminder in <app>"). Added to the Runner
  target in `project.pbxproj` (build file + file ref + group + sources phase).
- `ios/Runner/AppDelegate.swift`: sets up the `surya/intents` channel; cold-launch
  activation defers to Flutter's pull, later activations push the pending phrase
  (no double-consume).
- `Info.plist`: `remote-notification` background mode + `FirebaseAppDelegateProxyEnabled`.
- `ios/Runner/Runner.entitlements`: `aps-environment=development`; wired via
  `CODE_SIGN_ENTITLEMENTS` in all three Runner build configs.

### Verified (toolchain)
- `flutter analyze`: no issues. `flutter test`: 26/26 pass (incl. new intent-channel
  contract tests).

### Not verified — needs a device / console (acceptable, iPhone phase)
- **Actual push delivery**: requires the APNs auth key uploaded to Firebase, the
  **Push Notifications** capability enabled in Xcode, and a real device (FID
  registration is skipped on the iOS Simulator). The Dart/token plumbing is built.
- **Siri invocation + native compile**: Swift can't be compiled on this Windows
  toolchain; `SuryaIntents.swift`/`AppDelegate.swift` and the pbxproj wiring are
  written but need an Xcode build + on-device Siri test. Developer must also confirm
  the **Push Notifications** capability in Xcode (it re-asserts the entitlements ref).
- Siri spoken "<name>" is the **app name**, not the user-chosen assistant name
  (App Shortcut phrases are static at build time); in-app UI still uses the chosen name.

### Remaining / deferred
- Phase 6 — Android background-location polish, RevenueCat Free/Pro tiers, store
  assets, privacy policy, TestFlight/Play internal testing.
- Still open from earlier phases: live Gemini/Places keys + Cloud Run deploy;
  on-device voice + real geofence firing (§8 DoD).

---

## Phase 6 — Android + Free/Pro tiers + store prep

**Date:** 2026-10-28
**Status:** **Implemented; `flutter analyze` clean, 27 tests pass, and the Android
debug APK builds successfully** (`assembleDebug` OK — RevenueCat + FCM native
plugins compile/merge). Store-console, signing, APNs and `firebase deploy` steps
are documented but account-gated (not executed here).

### Built (Dart, `app/lib`)
- **Platform-aware geofence budget** (`services/geofence_coordinator.dart`):
  `_maxGeofencesTotal` is now a getter — iOS ≤ 20, Android 90 — falling back to the
  stricter iOS value off-device (tests/desktop). Respects OS region limits (§5).
- **Billing** (`services/subscription_service.dart`): `SubscriptionService` behind
  an interface + `RevenueCatSubscriptionService` using `purchases_flutter: ^9.7.1`
  (9.16.2 resolved). **Graceful degradation**: with no platform key configured the
  app is Free-only and never calls the store plugin. Uses the non-deprecated
  `Purchases.purchase(PurchaseParams.package(...))`. init / identify(uid) / logOut
  wired into the home bootstrap + sign-out.
- **Providers**: `subscriptionServiceProvider`, `isProProvider` (live entitlement),
  `activeReminderCountProvider` (the figure the cap applies to).
- **Free-tier enforcement**: `AddReminderScreen._ensureWithinFreeLimit()` blocks a
  new active reminder past `AppConfig.freeActiveReminderLimit` (5) unless Pro, and
  routes to the paywall. This is the single save chokepoint (covers manual + voice).
- **Paywall** (`screens/paywall_screen.dart`): benefits, RevenueCat offerings,
  purchase + restore, and a clear "billing unavailable" state when unconfigured.
  Settings gained a **Subscription** tile (tier + "N of 5 used" + upgrade).
- **Config** (`config/app_config.dart`): `RC_API_KEY_ANDROID/IOS` dart-defines,
  `proEntitlementId = 'pro'`, `freeActiveReminderLimit = 5`.

### Built (native / infra)
- Android: manifest + Gradle already carried background location,
  `POST_NOTIFICATIONS`, foreground-service, google-services, `minSdk 24`
  (RevenueCat needs 21+) — verified, no change needed. FCM service auto-merges.
- **Privacy policy on Firebase Hosting**: `public/privacy.html` + `public/index.html`;
  root `firebase.json` gains a `hosting` block with a `/privacy` rewrite. Deploy with
  `firebase deploy --only hosting` → `https://surya-assistance.web.app/privacy`.
- **Store prep** (`store/`): `listings.md` (App Store + Play copy, keywords, data-
  safety summary, asset checklist) and `RELEASE.md` (dart-defines, RevenueCat setup,
  APNs, TestFlight + Play internal-testing steps, pre-submission checklist).

### Verified
- `flutter analyze`: no issues. `flutter test`: **27/27** pass (added
  `subscription_service_test.dart` locking the Free-mode degradation contract).
- `flutter build apk --debug`: **success** — confirms the new native plugins
  (purchases_flutter, firebase_messaging) build and merge on Android.

### Not verified — account/device-gated (acceptable)
- **Real purchases / Pro unlock**: need a RevenueCat project, products in App Store
  Connect + Play Console, the `pro` entitlement + offering, and the public SDK keys
  injected via dart-define. Code degrades to Free until then.
- **Store submission**: App Store Connect / Play Console setup, release signing
  (replace debug keystore), screenshots, TestFlight / Play internal testing,
  background-location justification for Play review — all in `store/RELEASE.md`.
- **Privacy policy live URL**: needs `firebase deploy --only hosting`.
- Android geofence firing on-device + the §8 iPhone demo loop remain device tasks.

### Remaining (post-Phase-6, to ship)
- Cloud Run backend deploy + live Gemini/Places keys (code ready since Phase 3).
- On-device verification of the §8 definition-of-done loop (iOS + Android).
- Execute the account-gated store/billing steps above.

---

## Phase 7 — Family inventory & shared lists (CLAUDE.md §10)

**Date:** 2026-11-02
**Status:** **Designed (full §10); Phase 7a implemented.** Design added to CLAUDE.md
(§1 decision + §7 sub-phases 7a–7e + §10). **7a (family + sharing foundation) is now
built, `flutter analyze` clean, 34 tests pass.** 7b–7e not started. The §8 iPhone demo
loop remains the gate before deeper family work.

### Phase 7a — Family + sharing foundation (IMPLEMENTED 2026-11-02)
**Additive only — no change to the single-user reminder/geofence/parsing flow.**

Built (Dart, `app/lib`):
- **`models/family.dart`** — `Family` data class (`id, name, ownerUid, memberUids,
  inviteCode, createdAt`) + membership helpers (`isOwner/isMember/memberCount`), and
  pure invite-code helpers: `generateInviteCode` (6 chars, alphabet excludes ambiguous
  I/O/0/1) + `normalizeInviteCode`.
- **`services/family_repository.dart`** — `FamilyRepository` interface +
  `FirestoreFamilyRepository`: `watchFamily`, `createFamily`, `joinByCode`,
  `leaveFamily`, `disbandFamily`, `clearStalePointer`. Uses batched writes across
  `families/{id}`, the `familyCodes/{code}` lookup, and the `users/{uid}.familyId`
  pointer. `FamilyException` carries user-safe messages.
- **`models/user_profile.dart`** — added optional `familyId` (backward compatible;
  null = solo user).
- **`providers/providers.dart`** — `familyRepositoryProvider`, `familyIdProvider`
  (from profile), `familyProvider` (live family stream). Riverpod's own `Family` type
  hidden on import to avoid the name clash.
- **`screens/family_screen.dart`** — create a family / join by code / show invite code
  (copyable) + member list / leave (member) / disband (owner), plus a stale-pointer
  recovery view when the owner disbanded the family.
- **`screens/settings_screen.dart`** — new **Family** tile (shows family name + member
  count, or "Not in a family") → opens FamilyScreen. Only entry point; home untouched.

Design decisions (made for free-tier + offline, no backend dependency yet):
- **Invite = short join code**, not email (no email infra; works without the
  not-yet-deployed backend; testable on two devices).
- **`familyCodes/{code}` lookup doc** lets a non-member resolve a code → familyId
  without reading other families (membership rules forbid that). Join adds only the
  caller to `memberUids`, enforced by a tight security rule (`hasAll` + `hasOnly`).
- **One family per user** (enforced in repo/UI via `users/{uid}.familyId`).
- **Owner disbands; members leave.** On disband, other members' pointers + the code doc
  self-heal lazily (watchFamily → null → stale-pointer view; joining a dead code fails
  cleanly) because client rules forbid writing other users' docs.

Security rules (`firestore.rules`) — **additive; users/reminders rules unchanged**:
- `families/{familyId}`: read/update for members; create only as sole-owner; join-update
  may add only self; delete (disband) owner-only.
- `familyCodes/{code}`: read for any signed-in user; create shape-checked; immutable.

Verified: `flutter analyze` → no issues; `flutter test` → **34/34** (added
`test/family_test.dart` — invite-code length/alphabet/determinism/normalize + Family
membership helpers). Firestore-backed repo paths follow the existing
User/ReminderRepository convention (exercised on device, not unit-tested).

**Not yet done (developer / on-device):**
- **Deploy the new rules**: `firebase deploy --only firestore:rules` (required before
  create/join works against live Firestore).
- **Two-device test** of invite → join → leave/disband (the 7a "done" criterion).
- Member rows currently show "You"/"Owner" + a short uid (no shared display names yet —
  a Phase 7b addition).

### What this adds
Turns Surya from a personal reminder app into a **shared family assistant**: an owner
invites members into a family; everyone shares one inventory split into **Present Items**
(at home, with `lastUpdatedAt`) and **Need to Buy**. Location alerts surface the shared
Need-to-Buy list to *whichever member* enters a store likely to carry a needed item —
to avoid duplicate purchases and keep the family in sync. The family layer is **additive**
(solo users unchanged, §4 intact) and **reuses** the existing dynamic `query`/geofence/
`/v1/nearby` machinery (§3/§9). No LLM in the geofence/notification path (unchanged).

### Planned sub-phases (sequence; confirm each on device before the next)
- **7a** Family + sharing foundation — `families/{familyId}` (owner + `memberUids`),
  invite flow (code/email), membership-based Firestore security rules, `FamilyRepository`,
  one family per user. Solo users keep working.
- **7b** Shared inventory — `families/{familyId}/items/{itemId}` with `state`
  present|needed + `lastUpdatedAt`/`updatedBy`; Present Items + Need-to-Buy screens (live);
  one-tap **"bought it"** moves needed → present for everyone (the anti-duplicate loop).
- **7c** Location alerts from the shared list — on store ENTER, notify the member who is
  physically there with matching Need-to-Buy items; only when the list is non-empty and
  an item matches the store category; dedupe repeat entries.
- **7d** Dynamic store detection for family needs — "buy rice" with no store → needed item
  + dynamic query reminder; discover nearby relevant stores and geofence per §3; fire once
  on ANY match.
- **7e** Per-member notifications — `users/{uid}/dismissedAlerts`; the trash icon dismisses
  a member's OWN notification WITHOUT deleting the shared product/reminder.

### Design decisions locked in CLAUDE.md §10
- **Availability = store-likelihood, NOT real stock.** Category heuristics from Places
  ("grocery store likely has rice"); label as "likely." True SKU-level inventory is
  OUT OF SCOPE until a retail partnership. Never claim exact stock.
- **Membership-gated security rules are the source of truth** (never client-only checks);
  backend re-checks family membership server-side.
- **Per-member dismissal ≠ delete**: personal alert state only; shared inventory intact.
- Prefer client-side category heuristics / reuse of `/v1/parse` + `/v1/nearby` to stay on
  free tiers; ask before adding any new paid API (§5).

### Open questions to resolve before 7a
- Invite mechanism: short join code vs email invite (or both)?
- Store detection for local/regional independents (e.g. a neighbourhood market) — Places
  coverage is patchy; decide the fallback when a named local store isn't discoverable.

---

### Phase 7b — Shared inventory + Personal/Family modes (IMPLEMENTED 2026-11-05)
**Status:** Implemented; `flutter analyze` clean, **45 tests pass** (was 34; +9
inventory, +2 family display-name). Additive — the single-user reminder/geofence/
parsing flow is untouched. Not yet deployed to live Firestore / two-device tested.

Covers the user's feature groups **1 (Smart Inventory)** and **2 (Personal & Family
Sharing)**.

Built (Dart, `app/lib`):
- **`models/inventory_item.dart`** — `InventoryItem` (`name, state, quantity?,
  locationQuery?, updatedBy, updatedByName, createdBy, lastUpdatedAt, createdAt`) +
  `ItemState` (present|needed) with a `wire`/`fromWire` codec (unknown → needed so an
  item never disappears). `dedupeKey` (trim+lowercase) powers the duplicate guard.
  `locationQuery` is the hook Phase 7c/7d reuses for store matching.
- **`services/inventory_repository.dart`** — `InventoryRepository` interface +
  `FirestoreInventoryRepository`. An `InventoryScope` (personal `users/{uid}/items` vs
  family `families/{fid}/items`) means add/edit/move/delete, the live listener, and the
  one-tap Bought loop are written **once** and serve both inventories. `InventoryActor`
  (uid + display name) stamps every write so items show "updated by".
- **`providers/providers.dart`** — `inventoryRepositoryProvider`,
  `inventoryModeProvider` (Personal/Family toggle), `inventoryScopeProvider` (resolves
  mode → scope; null when Family-mode with no family), `inventoryActorProvider`,
  `currentDisplayNameProvider` (Google name → email local-part → "Member"),
  `inventoryItemsProvider` (live) + derived `presentItemsProvider` / `neededItemsProvider`.
- **`screens/inventory_screen.dart`** — Personal⇄Family `SegmentedButton` (Family
  disabled with a hint until you're in one), **Present / Need-to-Buy** tabs (live), add/
  edit bottom sheet (name, quantity, where-to-buy hint, which list), per-item Edit/Delete
  menu, and the move actions: **Bought** (needed→present, one tap — the anti-duplicate
  loop) and **Need** (present→needed). Adding a needed item that's already in Present
  warns before duplicating. "Updated 5m ago by <name>" shown for shared items.
- **Display names**: `Family` gained a denormalised `memberNames` map +
  `displayNameFor(uid)`; `FamilyRepository.createFamily`/`joinByCode` now take
  `displayName` and write the caller's own entry (dotted field path on join so it can't
  clobber others). Member rows show real names ("Asha (You)", "Owner" badge).
- **Entry point**: an **Inventory** icon in the home app bar.

Security rules (`firestore.rules`) — additive; users/reminders/family-doc rules unchanged:
- `users/{uid}/items/{itemId}` — private to the owner (personal inventory).
- `families/{familyId}/items/{itemId}` — read/write for members only; membership read
  from the parent family doc via `get(...).data.memberUids` (the single source of truth,
  never a client value). Owner/member parity for item data per §10 (all members equal for
  product edits; only disband/remove-member stay owner-only).

Verified (toolchain): `flutter analyze` → no issues; `flutter test` → **45/45**
(`test/inventory_test.dart`: wire codec, create payload, copyWith, dedupe key, scope
equality; `test/family_test.dart`: display-name resolution + id fallback). Firestore-
backed repo paths follow the existing repo convention (exercised on device, not unit-
tested).

**Not yet done (developer / on-device):**
- **Deploy the updated rules**: `firebase deploy --only firestore:rules` (required before
  the items subcollections are writable against live Firestore).
- **Two-device test**: shared add/move/Bought syncing live between two family members;
  personal vs family isolation.
- **Voice-based inventory updates** (group 1) — deferred: it needs the mic/composer wired
  to inventory intents; parked until the Phase 4 voice loop is confirmed on device and
  Phase 7c lands. Everything else in groups 1 & 2 is built.

### Phase 7c/7d — Store-entry alerts + dynamic store detection (IMPLEMENTED 2026-11-05)
**Status:** Implemented; `flutter analyze` clean, **55 tests pass** (was 45; +10 store
matcher). Reuses the existing geofence + `/v1/nearby` machinery (§3/§9) — no fork, no
LLM in the geofence/notification path. Live firing is a device task. Covers the user's
feature group **3 (Smart Location-Based Shopping)**.

Built (Dart, `app/lib`):
- **`services/store_matcher.dart`** — pure category heuristics (CLAUDE.md §10 #6:
  store-*likelihood*, NOT real stock). Tiny keyword dictionaries map an item →
  `StoreCategory` (grocery/pharmacy/hardware/electronics/stationery; unknown → grocery).
  `resolveTarget(item)` → the store to geofence: the item's explicit where-to-buy hint
  (how local stores like "Sai Market" are supported, #4) else the category query.
  `targetsFor` / `needsForTarget` / `labelFor` round out matching + display.
- **`providers/providers.dart`** — refactored inventory providers so the screen and
  background geofencing share listeners: `personalInventoryItemsProvider` +
  `familyInventoryItemsProvider` are the sources; `inventoryItemsProvider` now picks one
  by the UI toggle. New `storeMatcherProvider` and `geofenceNeedsProvider` (all currently
  needed items across personal + family, each tagged with its `InventoryScope`) — the
  latter drives store geofencing independent of the UI mode.
- **`services/geofence_coordinator.dart`** — `syncActiveReminders` now also builds store
  geofences (`_buildStoreSpecs`): one `/v1/nearby` query per distinct target, one
  geofence per branch, id `store::<targetKey>::<index>`. Reminders keep OS-budget
  priority; stores fill the remainder nearest-first. On a `store::` ENTER,
  `_handleStoreEnter` recomputes the matching needed items live, and — only when
  non-empty and not alerted for this store within a 30-min window (dedupe) — fires the
  alert. `_handleAction` wires the notification "Bought" button to flip every matching
  needed item → present in its own scope (one-tap clear).
- **`services/notification_service.dart`** — new `showStoreNeeds(...)` on a dedicated
  `surya_store_needs` channel: lists needed items ("need: rice, milk") plus an "Already
  home: …" line (the anti-duplicate goal), with a **Bought** action button. Added
  `setActionHandler` + `onDidReceiveNotificationResponse` routing.
- **`screens/home_screen.dart`** — re-syncs geofences when `geofenceNeedsProvider`
  changes (a new needed item starts monitoring matching stores immediately).

How the group-3 checklist maps:
- Detect grocery-store visit ✓ (store geofence) · Show Present + Need in the notification
  ✓ · Dynamic reminders with no store name ✓ (category default) · Recognise local stores
  e.g. Sai Market ✓ (explicit hint → text search) · Match items to stores ✓ (matcher) ·
  Avoid repeat notifications ✓ (30-min per-store dedupe) · Only the member who enters is
  alerted ✓ (fires on their device) · One-tap Bought from the notification ✓.

Verified (toolchain): `flutter analyze` → no issues; `flutter test` → **55/55**
(`test/store_matcher_test.dart`: categorize, hint-vs-category target, distinct targets,
per-store selection, empty→none, labels). The coordinator/notification wiring follows the
existing device-tested convention.

**Not yet done (developer / on-device):**
- **Live store alerts on a device** — needs a Places-enabled backend key + real/simulated
  location (emulator `geo fix` is unreliable, per Phase 2/3 notes). The business logic is
  unit-tested; firing is a device task.
- **"Bought" action in the terminated state** — handled when the app is alive/foreground;
  a background-isolate tap needs a top-level `@pragma('vm:entry-point')` handler +
  `Firebase.initializeApp` in that isolate (device task).
- **Dismiss-without-delete (checklist 3.8)** — swiping the OS notification already leaves
  the Firestore product intact (per-device). *Persistent* per-member dismissal state
  (`users/{uid}/dismissedAlerts`) is **Phase 7e**.
- **Voice → inventory** ("remind me to buy rice" routing to a needed item) — still the
  deferred voice-integration item from 7b; the manual Add-to-Need-to-Buy path already
  drives store geofencing today.

### Remaining Phase 7 sub-phases (sequence)
- **7e** Per-member notification dismissal (`users/{uid}/dismissedAlerts`; trash icon
  dismisses a member's OWN alert without deleting the shared product).

### Beyond Phase 7 (new phases for the remaining feature groups — design before build)
- **Phase 9** Multilingual Hanu (group 5) — Telugu/Hindi + mixed STT, language setting,
  TTS, multilingual notifications, UI i18n. **Only remaining group.**

---

## Phase 8 — Time & recurring reminders (IMPLEMENTED 2026-11-05)

**Status:** Implemented; `flutter analyze` clean, **74 tests pass** (was 55; +19), and the
**Android debug APK builds** (new `flutter_timezone` plugin + scheduled-notification
receivers merge). Live firing on a device is the remaining check. Covers the user's
feature group **4 (Time & Recurring Reminders)**.

This activates the first **time-triggered** path. Until now `remindAt` was recognised but
"location is the only trigger" (§9). Phase 8 makes **time a real trigger** alongside
location — a reminder can be location-based, time-based, or both.

### New dependencies (companions of the already-approved `flutter_local_notifications`)
- `timezone` (was transitive → now direct) and `flutter_timezone` — required by
  `zonedSchedule`/`TZDateTime`. Added via `flutter pub add` (resolved timezone 0.10.1).

### Built (Dart, `app/lib`)
- **`models/recurrence.dart`** — `Recurrence {none,daily,weekly,monthly,yearly}` + wire
  codec + pure `nextOccurrence(scheduled, {after})` (advances to the next future fire;
  clamps Jan-31→Feb-28 monthly, Feb-29→Feb-28 yearly; past one-shot → null).
- **`models/reminder.dart`** — added `recurrence` (default none, backward compatible) +
  getters `isTimeScheduled` and `hasLocationTrigger` (a birthday has no location trigger).
  `fromFirestore`/`toMap`/`copyWith` updated.
- **`parsing/date_grammar.dart`** — pure recogniser (complement to TimeGrammar) for
  absolute dates ("November 7", "7th of December", "12/25") and recurrence ("daily",
  "weekly", "every Monday", "every year", "every November 7" → yearly), stripping them
  from the text.
- **`parsing/intent_parser.dart`** — runs DateGrammar after TimeGrammar, combines
  date+time, and the **structural gate now treats time as a trigger**: RESOLVED on
  task + (location OR time). A recurrence with no time → CLARIFY asking for the time
  ("ask for missing date/time"). `ParsedIntent` + `ReminderComposer` carry `recurrence`.
- **`services/reminder_scheduler.dart`** — `ReminderScheduler` interface +
  `LocalReminderScheduler` (zonedSchedule + timezone). `sync()` schedules each active
  time reminder at its next occurrence, cancels ones removed, and maps recurrence →
  `DateTimeComponents` so the OS auto-repeats (yearly = `dateAndTime`). Ids in a high
  range so they never collide with geofence notification ids.
- **Wiring**: `reminderSchedulerProvider`; home bootstraps `init()` and re-`sync()`s on
  reminder changes (+ `cancelAll()` on sign-out); the geofence coordinator now **skips
  time-only reminders** (`!hasLocationTrigger`) so they don't try to geofence an empty
  place. `screens/add_reminder_screen.dart` gained a **When** section (date + time picker,
  clearable) and a **Repeat** dropdown, made the location optional, and validates "a place,
  a time, or both" + "pick a time for a repeat". Home tiles show time/recurrence.

### Native
- `AndroidManifest.xml`: added `ScheduledNotificationReceiver` +
  `ScheduledNotificationBootReceiver` (BOOT_COMPLETED / MY_PACKAGE_REPLACED) so scheduled
  and recurring reminders survive app-kill/reboot. `RECEIVE_BOOT_COMPLETED` was already
  present (Phase 2).

### How the group-4 checklist maps
- Date-based reminders (e.g. Nov 7 birthday) ✓ · Recurring annual birthday ✓ (yearly) ·
  Daily/weekly/monthly recurring ✓ · Ask for missing date/time ✓ (parser CLARIFY +
  save-time validation) · Verify scheduled notifications on real devices — **device task**.

### Verified (toolchain)
`flutter analyze` → no issues; `flutter test` → **74/74** (new: `recurrence_test.dart`,
`date_grammar_test.dart`; updated `intent_parser_test.dart` for the time-as-trigger rule +
birthday/recurrence cases). `flutter build apk --debug` → success.

### Not yet done (developer / on-device)
- **On-device firing** of scheduled + recurring notifications (incl. after reboot) — the
  scheduling logic is unit-tested; actual delivery is a device task.
- **Exact timing**: uses `inexactAllowWhileIdle` (no `SCHEDULE_EXACT_ALARM` needed, Play-
  friendly) so fires land within an OS batching window. Switch to exact alarms if minute-
  precise birthdays are required (adds a permission + Play justification).
- **iOS**: scheduled local notifications work via the same API; confirm on a device.
- **Voice path**: "remind me … November 7 every year" now parses locally to a yearly time
  reminder end-to-end through the composer; confirm with real speech on-device.

---

## Phase 10 — My Ideas (IMPLEMENTED 2026-11-05)

**Status:** Implemented; `flutter analyze` clean, **81 tests pass** (was 74; +7).
Self-contained + additive — no change to reminders/inventory/family. Covers the user's
feature group **6 (My Ideas)**. Not yet deployed to live Firestore.

### Built (Dart, `app/lib`)
- **`models/idea.dart`** — `Idea {id, title, description?, createdAt, updatedAt}` + a pure
  `matches(query)` (case-insensitive over title + body; blank query matches all) powering
  search, and `toCreateMap`.
- **`services/idea_repository.dart`** — `IdeaRepository` interface +
  `FirestoreIdeaRepository` over `users/{uid}/ideas` (watch newest-first, add, update,
  delete).
- **`providers/providers.dart`** — `ideaRepositoryProvider`, `ideasProvider` (live),
  `ideaSearchProvider` (query state), `filteredIdeasProvider` (derived via `Idea.matches`).
- **`screens/ideas_screen.dart`** — search bar, live list (title + snippet + created date),
  add/edit bottom sheet, delete-with-confirm, empty/no-results states. A reusable
  `_DictationField` adds a mic button to the title and details fields that dictates via the
  existing Phase 4 `SpeechService` ("save ideas using voice commands").
- **Entry point**: a **lightbulb** icon in the home app bar.

### Security rules (`firestore.rules`)
- `users/{uid}/ideas/{ideaId}` — private to the owner (additive; other rules unchanged).

### How the group-6 checklist maps
- Save ideas by voice ✓ (mic dictation on both fields) · Dedicated My Ideas section ✓ ·
  Title + description + creation date ✓ · Edit + delete ✓ · Search ✓.

### Verified (toolchain)
`flutter analyze` → no issues; `flutter test` → **81/81** (`test/idea_test.dart`: search
matching + create payload). Firestore repo exercised on device (project convention).

### Not yet done (developer / on-device)
- **Deploy rules**: `firebase deploy --only firestore:rules` (for the `ideas` subcollection).
- **Voice dictation on a device** (emulator has no usable mic — same caveat as Phase 4).

---

## Feature-group status (user's six)
1. Smart Inventory — **Phase 7b ✓** · 2. Personal & Family Sharing — **7b ✓** ·
3. Smart Location-Based Shopping — **7c/7d ✓** · 4. Time & Recurring — **Phase 8 ✓** ·
5. Multilingual Hanu — **Phase 9 (pending)** · 6. My Ideas — **Phase 10 ✓**.

Cross-cutting developer tasks still outstanding: deploy updated `firestore.rules`; the
on-device verification each phase notes (geofence/alerts/scheduled notifications/voice);
live Gemini/Places key + Cloud Run deploy (open since Phase 3). 81/81 tests green.

---

## Phase 9 — Multilingual Hanu (Telugu/Hindi) (IMPLEMENTED 2026-11-05)

**Status:** Implemented; `flutter analyze` clean, **87 tests pass** (was 81; +6), and the
**Android debug APK builds** (new `flutter_tts` plugin merges). Covers the user's feature
group **5 (Multilingual Hanu)**. Additive + backward compatible (absent language = English).

### Design honesty (free-tier / on-device, no cloud translation)
- **No machine translation.** UI chrome + spoken/notification scaffolding are **hand-
  written** per language; **user content (task text, item names) is never translated** —
  it's interpolated verbatim and echoed back as entered.
- **STT/TTS quality is device-dependent.** We set the recognition/voice locale; actual
  Telugu/Hindi + mixed-language support comes from the device's installed language packs.

### New dependency
- `flutter_tts` (on-device, free) — for Hanu speaking back. Added via `flutter pub add`.

### Built (Dart, `app/lib`)
- **`l10n/app_language.dart`** — `AppLanguage {english, hindi, telugu}` with `code`
  (en/hi/te wire), `displayName` (in-script), and `localeId` (`en-US`/`hi-IN`/`te-IN`) for
  both STT and TTS. `fromCode` defaults to English.
- **`l10n/app_strings.dart`** — `AppStrings` interface + En/Hi/Te implementations for the
  high-visibility surface (settings, home, voice capture, confirmations, reminder
  notification). Confirmations/notifications are methods taking `{task}`/`{place}` so user
  content passes through untranslated.
- **`models/user_profile.dart` + `user_repository.dart`** — `preferredLanguage`
  (backward compatible) + `setPreferredLanguage`.
- **`services/tts_service.dart`** — `TtsService` interface + `FlutterTtsService`
  (best-effort: sets the locale if a voice exists, else speaks default; never throws).
- **`services/speech_service.dart`** — `listen()` gained a `localeId` (via
  `SpeechListenOptions`) so recognition runs in the chosen language.
- **`providers/providers.dart`** — `appLanguageProvider` (from profile), `stringsProvider`
  (live `AppStrings`), `ttsServiceProvider`.

### Wiring
- **Settings**: a **Language** picker (English / हिन्दी / తెలుగు) writing immediately to the
  profile — the whole app re-renders live via `stringsProvider`. Settings labels localized.
- **Voice capture**: passes the preferred `localeId` to STT; title/prompt/listening/
  continue localized.
- **Add reminder**: the confirmation is built from localized strings **and spoken aloud**
  via TTS in the chosen language (replaces the old English-only backend confirm here).
- **Geofence notification**: `showReminderTriggered` now takes `AppStrings` and renders the
  title/body in the user's language.
- **Home**: the "Speak" FAB + empty state localized; TTS warmed up in bootstrap.

### How the group-5 checklist maps
- Telugu voice recognition ✓ · Hindi voice recognition ✓ · Telugu-English / Hindi-English
  mixed speech ✓ (device-engine dependent, locale set) · Language selection in Settings ✓ ·
  Hanu speaking back in Telugu/Hindi ✓ (TTS) · Multilingual notifications ✓ (reminder
  trigger) · Translate UI labels ✓ **for the core surface** (incremental for the rest).

### Verified (toolchain)
`flutter analyze` → no issues; `flutter test` → **87/87** (`test/multilingual_test.dart`:
locale codec + mapping, every language supplies every non-blank string, user content
interpolated verbatim, languages genuinely differ). `flutter build apk --debug` → success.

### Not yet done (developer / on-device)
- **On-device STT/TTS in Telugu/Hindi** — needs the device's language packs installed;
  verify real recognition (incl. code-switching) + spoken output on a device.
- **Full UI translation** — the core chrome is localized; inventory/ideas/paywall/family
  screens + the store-needs alert remain English. Extending is mechanical: add keys to
  `AppStrings` (the completeness test enforces all three languages) and swap literals.
- **Backend `/v1/confirm`** stays English; the app now speaks its own localized
  confirmation, so this is only relevant if we later want server-side localized copy.

---

### Feature-group status — ALL SIX DELIVERED (toolchain-verified)
1. Smart Inventory — **7b ✓** · 2. Personal & Family Sharing — **7b ✓** ·
3. Smart Location-Based Shopping — **7c/7d ✓** · 4. Time & Recurring — **8 ✓** ·
5. Multilingual Hanu — **9 ✓** · 6. My Ideas — **10 ✓**. **87/87 tests green.**

Cross-cutting developer tasks still outstanding (unchanged, device/account-gated):
deploy updated `firestore.rules`; on-device verification of geofence/store-alerts/
scheduled-notifications/voice/STT/TTS; live Gemini/Places key + Cloud Run deploy.
