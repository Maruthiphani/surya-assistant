# Surya Assistance — Project Instructions for Claude Code

Read this file fully before doing anything. Work ONE phase at a time. Do not start a later phase until the current phase is confirmed working on a real iPhone.

---

## 1. What we are building

A voice-driven, location-triggered AI reminder app for iOS and Android.

User says: "Hey <assistant name>, remind me to buy rice when I'm at Costco."
The app → speech-to-text → **on-device intent parser** extracts `{task, location, locationType, time}` → (Gemini fallback only if it can't) → geocodes/discovers the place → saves reminder → registers a geofence → when the user enters the radius, a notification fires → user marks it done.

Key product decisions:
- Mobile only (Flutter). No web/PWA.
- Users choose their own assistant name during onboarding (default "Surya"). Use it in UI, confirmations and notifications. Strip "Hey <name>" from the transcript before sending to the LLM.
- No in-app wake-word listening. Voice is started by a mic button (Siri Shortcut / App Actions later).
- Geofence evaluation happens ON THE DEVICE, not on the backend. Backend only does AI parsing (fallback), geocoding, place discovery and sync.
- **Hybrid AI: local-first, LLM fallback.** A deterministic on-device parser handles common commands with no network/LLM call. Gemini is a *fallback* only for input the local parser can't safely handle. Accuracy wins over avoiding an LLM call — never silently create an incorrect reminder. Geofence notifications never involve an LLM. (Full design: §9.)
- **Reminders are specific or dynamic.** A *specific* reminder targets one named place ("Costco in Cumming") → one fixed lat/lng. A *dynamic* reminder targets a chain or category ("Costco", "a pharmacy", "grocery store") → we store the query, NOT a single branch, and fire when the user approaches ANY matching branch nearby. Dynamic is the default for bare chains/categories; only treat a reminder as specific when the user names a particular location.
- Everything must run on free tiers during development.
- Free tier: 5 active location reminders. Pro tier: unlimited (RevenueCat, Phase 6 only).
- **Family inventory & shared lists (major extension — full design §10).** Beyond
  personal reminders, Surya becomes a *shared family assistant*: an owner invites
  members into a family; everyone shares one inventory split into **Present Items**
  (already at home) and **Need to Buy**. Location alerts surface the shared "Need to
  Buy" list to *whichever member* enters a store likely to carry a needed item — the
  goal is to avoid duplicate purchases and keep the family in sync. Personal reminders
  still exist for solo users; the family layer sits on top and reuses the existing
  dynamic-location machinery. This is Phase 7 — do NOT start it until the Phase 4 demo
  loop works.

Demo priority: get the full loop working on the developer's own iPhone first (Phases 0–4). Android and stores come later (Phase 5–6).

---

## 2. Tech stack (do not substitute without asking)

| Layer | Choice |
|---|---|
| Mobile | Flutter (stable), Dart, Riverpod for state |
| Speech | `speech_to_text` (on-device) |
| Location/geofence | `geolocator`, `geofence_service`, `flutter_local_notifications` |
| Auth / DB / Push | Firebase: `firebase_auth` (Google + Apple sign-in), `cloud_firestore`, `firebase_messaging` |
| Backend | Python 3.12, FastAPI, Pydantic v2, deployed to Google Cloud Run (Docker) |
| Intent parsing | **On-device, deterministic (Dart)** — rule/template + time-grammar. Primary path. |
| AI (fallback) | Gemini Flash via `google-genai` SDK (LangGraph, structured JSON) — only when the local parser can't safely parse |
| Geocoding | Google Places API (Text Search), called from backend only |
| Tracing | Langfuse (free tier) |
| Secrets | `.env` locally, Google Secret Manager on Cloud Run. NEVER commit keys. |
| Repo | Monorepo: `/app` (Flutter), `/backend` (FastAPI) |

---

## 3. Architecture

```
iPhone / Android (Flutter)
 ├─ Mic button → speech_to_text → text
 ├─ IntentParser (ON DEVICE, deterministic) → ParsedIntent + outcome:
 │     RESOLVED      → use local result (no LLM)
 │     CLARIFY       → ask ONE on-device question, re-parse (no LLM)
 │     UNPARSEABLE   → POST /v1/parse (Gemini fallback, below)
 │
 ├─ [fallback only] POST /v1/parse (Firebase ID token)
 │     └─ FastAPI on Cloud Run
 │           ├─ LangGraph: Gemini extracts {task, location, locationType} → Pydantic validates
 │           │     locationType = "specific" (named place) | "query" (chain/category)
 │           ├─ specific → Places Text Search → 1–3 candidates {name, address, lat, lng}
 │           └─ query    → return the search query/category (no single branch)
 ├─ Always show a confirmation screen before saving (local OR fallback result)
 ├─ specific: resolve coords via /v1/nearby (Places, NOT LLM); picker only if >1 → write
 ├─ query: write reminder with locationQuery, no fixed lat/lng (NO picker)
 ├─ Firestore listener keeps list in sync
 ├─ Device geofence sync (on device):
 │     ├─ specific → one OS geofence at the reminder's lat/lng
 │     └─ query    → call backend /v1/nearby for the N nearest matching branches
 │                   around the user, register one OS geofence per branch
 ├─ Travel refresh: on OS significant-location-change / coarse location update
 │     (NOT continuous GPS), if moved beyond a threshold, re-query /v1/nearby and
 │     re-sync the geofence set to the new nearest branches (respect OS limits)
 └─ Geofence ENTER (any matching branch) → local notification → status = triggered (once)
```

---

## 4. Data model

Firestore: `users/{uid}`
```
assistantName: string        // user-chosen, default "Surya"
createdAt: timestamp
```

Firestore: `users/{uid}/reminders/{reminderId}`
```
task: string                 // "buy rice"
locationName: string         // display label, e.g. "Costco" or "Costco, Cumming"
locationType: "specific" | "query"   // default "query" for bare chains/categories
locationQuery: string?       // for "query" type: the search term, e.g. "Costco" / "pharmacy"
address: string?             // specific only
lat: number?                 // specific only (null for "query" — branches are discovered at runtime)
lng: number?                 // specific only
radiusMeters: number         // default 500
remindAt: timestamp?         // parsed time, if any (see §9). RECOGNISED now to avoid
                             // mis-parsing "5 PM" as a place; time-based *scheduling*
                             // is a later phase — location is still the trigger today.
status: "active" | "triggered" | "completed" | "cancelled"
createdAt: timestamp
triggeredAt: timestamp?
completedAt: timestamp?
```
Backward compatibility: an existing reminder with lat/lng and no `locationType` is
treated as `specific`. Never require lat/lng for `query` reminders. `remindAt` is
optional and ignored by the geofence path.

Backend request/response:
```
POST /v1/parse
  body: { "text": "remind me to buy rice when I'm at Costco", "lat": 33.7, "lng": -84.3 }
  // Gemini classifies the location as "specific" (named place) or "query" (chain/category).
  resp (dynamic/query): {
    "task": "buy rice",
    "locationType": "query",
    "locationQuery": "Costco",
    "locationName": "Costco",
    "candidates": []          // empty — branches are discovered at runtime via /v1/nearby
  }
  resp (specific):        {
    "task": "buy rice",
    "locationType": "specific",
    "locationName": "Costco, Cumming",
    "candidates": [ {name, address, lat, lng} ]   // picker only if >1
  }

POST /v1/nearby             // device calls this to discover/refresh matching branches
  body: { "query": "Costco", "lat": 34.2, "lng": -84.1, "radiusMeters": 30000, "limit": 20 }
  resp: { "places": [ {name, address, lat, lng} ] }   // nearest matches, capped to `limit`

POST /v1/confirm
  body: { "task": "...", "locationName": "...", "assistantName": "Priya" }
  resp: { "message": "Got it — I'll remind you to buy rice when you reach Costco." }
```

---

## 5. Engineering rules

- **Local-first parsing (see §9).** Try the on-device parser before any LLM call. Call
  Gemini (`/v1/parse`) only on the UNPARSEABLE outcome. The decision to fall back is a
  **deterministic structural gate**, NOT an arbitrary confidence float. Simple
  missing-slot cases get a local CLARIFY question, not an LLM call.
- **Always confirm before saving** a reminder (local or fallback result). Never silently
  create an incorrect reminder; validate time vs location (e.g. "5 PM" is a time).
- No LLM call is ever involved in geofence evaluation or firing a notification.
- Validate every LLM output with a Pydantic schema. If invalid, retry once, then return 422. Never save unvalidated LLM output.
- Location picker rules:
  - **Dynamic (chain/category) reminders: NO picker.** Store the query and match any
    nearby branch. Bare chains ("Costco", "Walmart", "Target") and categories
    ("pharmacy", "grocery store", "gas station") are dynamic by default.
  - **Specific reminders** (user named a place, e.g. "Costco in Cumming"): auto-pick
    if Places returns one candidate; show a picker only if it returns more than one.
  - Never silently pick one specific branch for a dynamic/generic request.
- Dynamic discovery & refresh (on device):
  - For a `query` reminder, discover branches via `POST /v1/nearby` around the user's
    current area and register one OS geofence per branch.
  - Cap registered geofences to the nearest N and respect OS region limits
    (iOS ≤ 20 monitored regions app-wide; Android ~100). Budget across all active
    reminders; log when results are truncated.
  - Refresh branches only on OS-efficient triggers — significant-location-change
    (iOS) / coarse location updates (Android) — and only re-query after the user has
    moved beyond a threshold. NEVER poll GPS in a loop or run continuous foreground
    location just to refresh.
- Idempotent triggers: a reminder with status != active must never fire again, and a
  dynamic reminder fires once on entering ANY matching branch (not once per branch).
- Prefer OS geofencing over continuous GPS polling. Never poll GPS in a loop.
- iOS: request "When In Use" location first; request "Always" only after an explanation screen. Add proper `NSLocation*UsageDescription` strings and Background Modes → Location updates.
- All backend endpoints verify the Firebase ID token. No anonymous endpoints except `/health`.
- Keep services behind interfaces (`AiService`, `LocationService`, `ReminderRepository`, `NotificationService`) so providers can be swapped.
- Small, incremental commits. Do not rewrite files wholesale; edit what exists.
- Ask before adding any paid service or any dependency not listed above.
- After each phase, update `PROGRESS.md` with what works, what was tested on device, and known issues.   
        
---

## 6. Repo layout

```
surya/
├── CLAUDE.md
├── PROGRESS.md
├── app/                      # Flutter
│   └── lib/
│       ├── main.dart
│       ├── models/{reminder,user_profile}.dart
│       ├── parsing/{intent_parser,time_grammar,place_dictionaries}.dart   # §9 local-first
│       ├── services/{intent_parser,reminder_composer,ai_service,location_service,
│       │             geofence_coordinator,reminder_repository,user_repository,
│       │             notification_service}.dart
│       ├── providers/
│       └── screens/{onboarding,login,home,add_reminder,pick_location,settings}_screen.dart
└── backend/                  # FastAPI
    ├── app/
    │   ├── main.py
    │   ├── auth.py           # Firebase token verification
    │   ├── schemas.py        # Pydantic models
    │   ├── graph.py          # LangGraph parse flow
    │   ├── gemini.py
    │   └── places.py
    ├── tests/
    ├── Dockerfile
    ├── requirements.txt
    └── .env.example
```

---

## 7. Phases and the prompt to run for each

### Phase 0 — Environment (manual, by the developer)
Developer does by hand: install Xcode + Flutter, `flutter doctor` green, create Firebase project (enable Auth: Google + Apple, Firestore, Cloud Messaging), create Google Cloud project in the same account (enable Gemini API key, Places API, Cloud Run), create GitHub repo.
Prompt for Claude Code:
> "Phase 0: scaffold the monorepo layout from section 6. Create the Flutter app in /app with Riverpod, and a FastAPI skeleton in /backend with a /health endpoint, Dockerfile, requirements.txt and .env.example. Add .gitignore for both. Do not add Firebase yet. Make `flutter run` work on my connected iPhone."

### Phase 1 — Auth + Firestore CRUD (no AI yet)
> "Phase 1: add Firebase (firebase_core, firebase_auth with Google and Apple sign-in, cloud_firestore). Build onboarding screen that asks for the assistant name and saves it to users/{uid}. Build login, home (reminder list with Firestore live listener) and add-reminder screen where I type task and location name manually with hardcoded lat/lng for now. Implement ReminderRepository against the data model in section 4. Test on iPhone."

### Phase 2 — Geofencing + local notifications (hardest phase)
> "Phase 2: add geolocator, geofence_service and flutter_local_notifications. Implement LocationService that registers one geofence per active reminder and NotificationService that fires a local notification on ENTER and sets status=triggered. Build the permission flow: When-In-Use first, then an explanation screen, then Always. Configure Info.plist and Background Modes. Add a debug screen that lets me simulate entering a geofence. Document how to test with Xcode simulated location in PROGRESS.md."

### Phase 3 — Backend AI + dynamic location discovery + deploy
> "Phase 3: in /backend implement /v1/parse, /v1/nearby and /v1/confirm per section 4. Use LangGraph with Gemini Flash structured output to extract {task, location, locationType} and classify the location as `specific` (named place) or `query` (chain/category); Pydantic validation with one retry. For `specific`, use Places Text Search for candidates; for `query`, return the search term. Implement /v1/nearby (Places Nearby/Text Search) that returns the nearest matching branches around a lat/lng, capped to `limit`. Firebase ID token verification on all endpoints, Langfuse tracing. Write pytest tests with mocked Gemini/Places. Add a Cloud Run deploy script using Secret Manager. Deploy and give me the URL.
>
> Then extend the app for dynamic reminders (this completes the Phase 2 LocationService): update the Reminder model + ReminderRepository for `locationType`/`locationQuery` (backward compatible — existing reminders are `specific`); drop the picker for `query` reminders. In LocationService, for a `query` reminder call /v1/nearby and register one geofence per nearby branch (geofence id encodes reminderId+branchId so ENTER still maps to the reminder); cap to the nearest N within OS region limits; refresh the branch set on significant-location-change / coarse location updates once the user moves beyond a threshold — no continuous GPS. A dynamic reminder fires once on entering ANY matching branch. Verify with the debug simulator and on device."

### Phase 3.5 — Hybrid local-first parsing (see §9)
> "Phase 3.5: add an on-device `IntentParser` (Dart) with a time-grammar and small chain/category dictionaries, plus a `ReminderComposer` that orchestrates local parse → RESOLVED / CLARIFY / UNPARSEABLE and only calls `AiService.parse` (Gemini) on UNPARSEABLE. Decision to fall back is a deterministic structural gate, not a float. Add an LLM-result cache (normalized, time-stripped key) and a Places-nearby cache (query + geo-bucket + TTL). Add minimal observability counters (local-success / fallback / clarify / error) and backend token+latency logging. Recognise time ('5 PM', 'tomorrow morning') into `remindAt` to avoid mis-parsing it as a place, but do NOT schedule on time yet (location stays the trigger). Golden-corpus unit tests for the parser. Keep rules simple/maintainable. Don't change existing geofencing/notification behavior."

### Phase 4 — Voice + wiring (full demo loop)
> "Phase 4: add speech_to_text. Mic button on home screen → transcript → strip 'hey <assistantName>' prefix → `ReminderComposer` (local-first; §9) → on RESOLVED build the reminder, on CLARIFY ask locally, on UNPARSEABLE call /v1/parse → if multiple candidates show pick_location screen → always show a confirmation screen → save reminder → call /v1/confirm → show confirmation using the assistant name. Register geofence on save. Works offline for simple reminders. End-to-end on my iPhone."

### Phase 5 — Push, sync, polish
> "Phase 5: add firebase_messaging, offline cache with sync-on-reconnect, settings screen (rename assistant, radius default), complete/cancel actions, and Siri Shortcut (App Intents) 'tell <name> to remind me…' that opens the app with the text prefilled."

### Phase 6 — Android + stores
> "Phase 6: make it run on Android (background location + POST_NOTIFICATIONS permissions, Android geofence limits). Add RevenueCat with Free (5 reminders) and Pro tiers. Prepare App Store and Play Store assets, privacy policy page on Firebase Hosting, and TestFlight / Play internal testing builds."

### Phase 7 — Family inventory & shared lists (see §10)
Big feature; sequence it in sub-phases (7a → 7e) and confirm each on device before the next.
> "Phase 7a (family + sharing foundation): add a `families/{familyId}` model with an owner and members, an invite flow (invite code or email), membership-based Firestore security rules, and a `FamilyRepository`. A user may belong to one family; solo users keep working unchanged. Test invite/join/leave on two devices."
>
> "Phase 7b (shared inventory): add `families/{familyId}/items/{itemId}` with `state` = `present` | `needed`, `lastUpdatedAt`, `updatedBy`. Build Present Items and Need-to-Buy screens (shared, live Firestore listeners) where any member can add/update/move/remove items. Implement the one-tap 'bought it' action that moves an item needed → present for EVERYONE (the anti-duplicate loop)."
>
> "Phase 7c (location alerts from the shared list): when a member enters a store likely to carry a needed item, fire a local notification summarising the relevant Need-to-Buy items (reuse the §9/§3 geofence + /v1/nearby machinery; store-likelihood is category heuristics, NOT real stock — see §10). Only alert the member who is physically there, only when the list is non-empty, and dedupe repeat entries."
>
> "Phase 7d (dynamic store detection for family needs): 'remind me to buy rice' with no store → treat rice as a needed item + a dynamic query reminder; discover nearby relevant stores (incl. local/regional chains where Places data allows) and geofence them per §3. Fire once on entering ANY matching store."
>
> "Phase 7e (per-member notifications): add per-user notification/alert state so a member can delete/dismiss their OWN notification via a trash icon WITHOUT deleting the shared product or reminder. Dismissal is personal; the inventory stays intact for everyone."

---

## 8. Definition of done for the demo (end of Phase 4)
On a real iPhone: say a reminder → correct task and place extracted (locally when possible) → reminder appears in list → lock phone → walk/drive into the radius → notification fires once → tap complete → never fires again.

---

## 9. Hybrid AI parsing (local-first + LLM fallback)

Goal: behave like an intelligent assistant without an LLM call for every simple
command. Principles: local-first, LLM only when necessary, **accuracy over cost**,
minimal calls, low latency, privacy, maintainable/testable, never an LLM in the
geofence/notification path.

### Pipeline (on device)
1. **Normalize** — lowercase, strip fillers ("hey <name>", "please").
2. **Match a template** — a small set, e.g.
   `remind me to <task> at/when <place>`, `... at/by <time>`,
   `... at <place> <time>`, `remind me when I reach <place>`, `remind me <time> to <task>`.
3. **Time grammar FIRST** — a dedicated recognizer (clock `5 pm`/`17:30`, relative
   `tomorrow`/`tonight`/`in 2 hours`/`next monday`, parts-of-day `morning`). What
   matches the time grammar is the TIME slot; the remainder after `at/when` is the
   LOCATION. (This is why "call Mom at 5 PM" → time, not place.)
4. **Location typing** — small, data-driven dictionaries (keep tiny; LLM covers the
   tail): disambiguator ("in <city>", "on <street>", "the X near Y") → `specific`;
   bare known chain / category keyword → `query`; "home"/"work"/saved place →
   `specific` from saved coords.
5. **Outcome** via the structural gate below.

### Fallback decision = deterministic structural gate (NOT a float)
`ParsedIntent.outcome`:
- **RESOLVED** iff ALL: exactly one template matched; all required slots filled
  (task + at least one trigger: location or time); input fully consumed except an
  allowlisted filler set; no ambiguity flags (the `at X` disambiguation resolved to
  exactly one of time/place; no multi-clause connectors like "and also"/"then").
- **CLARIFY** — a template almost matched but exactly one slot is missing/ambiguous in
  a known way → ask ONE on-device question, then re-parse. No LLM.
- **UNPARSEABLE** — no template, multiple clauses, unknown connectors, context-
  dependent pronouns, or unresolved disambiguation → call Gemini `/v1/parse`.
A derived `confidence` enum may be logged, but routing keys off these checks only.

### Caching
- **LLM-result cache**: LRU keyed on the normalized transcript with relative-time
  tokens STRIPPED (so "tomorrow" is never cached). Relative times are resolved at
  creation, not from cache.
- **Places-nearby cache**: keyed on (query, geo-bucket ~1km, radius) with a short TTL.
- Never cache user-specific context or resolved relative dates.

### Offline
- Fully offline: local parsing, dynamic (chain/category) reminder creation, saved-place
  reminders, Firestore local write (syncs later), geofence registration, notifications.
- Degrades gracefully: specific-place geocoding and chain branch discovery need Places →
  create + store now, populate branches/geofences on reconnect or next location refresh.
  If offline and the input is UNPARSEABLE, CLARIFY locally rather than fail.

### Observability (minimal — no new infra)
- Client counters: local-success rate, fallback rate, clarify frequency, parse errors.
- Backend: Gemini latency, token usage, estimated cost (from response usage metadata);
  Langfuse optional.
- Use these to replace the assumptions in PROGRESS.md with measured numbers.

### Scope notes
- Time is RECOGNISED now (into `remindAt`) to protect parsing accuracy, but time-based
  *scheduling/notifications* are a later phase — location remains the only trigger today.
- Local parser is English/template-bound by design; the long tail is the LLM's job.

---

## 10. Family inventory & shared lists (Phase 7)

Turns Surya from a personal reminder app into a **shared family assistant**. Do NOT
start this until the Phase 4 demo loop works. It *reuses* the existing dynamic-location
machinery (§3, §9) rather than replacing it — the center of gravity simply widens from
"a reminder" to "a family's shared inventory, surfaced at the right place."

### Concept
- An **owner** creates a family and invites **members**. All roles are equal for data:
  **any member** can add/update/move/remove products. (Only lifecycle actions —
  disband, remove a member — are owner-only.)
- The family shares one **inventory** of products in two states:
  - **Present Items** — already at home; carries `lastUpdatedAt` so the family can see
    freshness.
  - **Need to Buy** — products the family still needs to purchase.
- **Location alerts** surface the shared Need-to-Buy list to *whichever member* enters a
  store likely to carry a needed item — not a specific person.
- **Dynamic store detection**: "remind me to buy rice" with no store named → rice becomes
  a needed item, and Surya discovers nearby relevant stores (incl. local/regional ones
  like a neighbourhood market, where Places data allows) and fires when a member reaches
  ANY of them — exactly the existing `query`/`/v1/nearby` flow.
- **Main goal:** avoid duplicate purchases, keep members in sync, and remind whoever is
  in the right place — even without specifying a store.

### Product scope — be honest about availability (#6)
- **Store likelihood, NOT real-time stock.** Deciding whether a store "carries rice" uses
  **category heuristics** (a grocery store / supermarket likely has rice; a gas station
  does not) from Places category data — NOT retailer inventory. Label it as "likely to
  have" in the UI. True SKU-level stock needs retailer inventory APIs (closed/paid) and is
  explicitly OUT OF SCOPE until a retail partnership exists. Never claim exact stock.

### Data model (additions — does not change §4 for solo users)
Firestore: `families/{familyId}`
```
name: string
ownerUid: string
memberUids: [string]            // membership gate for security rules
createdAt: timestamp
```
Firestore: `families/{familyId}/invites/{inviteId}`  (or a short join code)
```
code: string                    // short invite/join code
invitedEmail: string?
status: "pending" | "accepted" | "revoked"
createdAt: timestamp
```
Firestore: `families/{familyId}/items/{itemId}`
```
name: string                    // "rice"
state: "present" | "needed"     // the two lists are two states of one product
locationQuery: string?          // optional category/chain hint for store matching, e.g. "grocery store"
quantity: string?               // free text, optional
lastUpdatedAt: timestamp
updatedBy: string               // uid of the member who last changed it
createdBy: string
createdAt: timestamp
```
Firestore: `users/{uid}` (add)
```
familyId: string?               // the family this user belongs to (one family per user)
```
Per-member notification dismissal (personal, NOT shared):
```
users/{uid}/dismissedAlerts/{alertId}     // { itemId/reminderId, storeId?, dismissedAt }
```
`users/{uid}` and `users/{uid}/reminders/{reminderId}` from §4 are unchanged; the family
layer is additive and solo users never touch `families/*`.

### Behaviour rules
- **Membership-gated access.** Firestore security rules allow read/write to
  `families/{familyId}/**` only if `request.auth.uid in memberUids`. One family per user
  (enforce via `users/{uid}.familyId`). Keep rules the single source of truth — never
  rely on client checks alone.
- **Anti-duplicate loop (the product's core).** When a member buys a needed item, a
  one-tap "bought it" action (ideally from the notification) flips `state` needed →
  present and stamps `lastUpdatedAt`/`updatedBy`. Because the list is shared and live,
  everyone sees it immediately — that's what prevents double purchases. Keep this loop
  one tap and fast; if it's slow or manual, duplicates still happen.
- **Alert relevance (avoid notification fatigue).** Only alert the member physically at
  the store; only when Need-to-Buy is non-empty AND an item matches the store's category;
  dedupe repeat entries to the same store within a short window. A store with no matching
  needed item produces NO notification.
- **Per-member dismissal ≠ delete.** The trash icon on a notification records a dismissal
  in `users/{uid}/dismissedAlerts` for THAT member only. It never deletes the shared
  product or reminder; other members are unaffected. Deleting a product is a separate,
  explicit action on the inventory itself.
- **Reuse, don't fork, the location path.** Needed items with a store hint drive the same
  `query` reminder + per-branch geofence + `/v1/nearby` refresh described in §3/§5/§9. No
  LLM is ever in the geofence/notification path (unchanged). A family dynamic reminder
  fires once on entering ANY matching store (idempotent, per §5).
- **Offline.** Shared inventory edits use Firestore local writes and sync on reconnect
  (per §9 offline rules). Conflicting edits resolve last-write-wins via `lastUpdatedAt`;
  surface stale state with the `lastUpdatedAt` label rather than hiding it.

### Backend (additions)
- Reuse `/v1/parse` and `/v1/nearby` as-is for store discovery. If needed, a thin
  `/v1/stores` wrapper may add category-likelihood filtering, but prefer client-side
  category heuristics first to stay on free tiers. Ask before adding new paid APIs.
- All family endpoints verify the Firebase ID token and re-check family membership
  server-side; never trust a client-supplied `familyId` without checking `memberUids`.
