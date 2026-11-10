# Surya (Hanu) — Feature Walkthrough

A voice-driven, location-triggered AI assistant for iOS and Android. You pick the
assistant's name during onboarding (the developer's is **Hanu**); it's used in the UI,
confirmations, and notifications. This document lists **everything the app does today**,
grouped by capability, with concrete examples.

> Conventions used below
> - **"Say"** = spoken via the mic, or typed into the command box (same pipeline).
> - **Dynamic** reminder = any branch of a chain/category (default). **Specific** = one
>   named place.
> - Geofence evaluation and notifications happen **on the device** — no server, no LLM.

---

## 1. Accounts & onboarding

| Feature | What it does | Example |
|---|---|---|
| Google Sign-In | Sign in with your Google account | Tap **Sign in with Google** on the login screen |
| Apple Sign-In | Stubbed ("coming soon") until the iOS/Mac build | — |
| Assistant naming | Choose your assistant's name; used everywhere | Enter **"Hanu"** at onboarding → app bar, confirmations, and notifications say "Hanu" |
| Secure per-user data | Each user reads/writes only their own data (Firestore rules) | Your reminders/ideas are private; family data is shared only with members |

---

## 2. Location reminders (the core loop)

Say a reminder → it's parsed → saved → a geofence is registered → when you arrive, a
notification fires **once** → you mark it done.

### 2a. Dynamic reminders (any branch) — the default
Fires at **any nearby branch** of a chain or category.

- Say: **"Hey Hanu, remind me to buy rice when I'm at Costco."**
  → task `buy rice`, matches **any** Costco nearby.
- Say: **"Remind me to pick up a prescription at a pharmacy."**
  → matches any pharmacy.
- Categories understood out of the box: grocery store, pharmacy, gas station, etc.

### 2b. Specific reminders (one named place)
Fires only at the one place you named.

- Say: **"Remind me to buy rice at Costco in Cumming."**
  → resolves the exact branch via Google Places; if several match, you pick from a list.
- On the add screen, turn **"Match any branch"** OFF to force a specific place.

### 2c. The arrival notification
- Drive/walk into the radius → **"Hanu reminder — You're near Costco — buy rice."**
- Tap the reminder's menu → **Mark complete** (it never fires again), **Cancel**, or **Delete**.
- Default radius is 500 m; change it per-reminder or set a new default in Settings.

### 2d. Dynamic branch discovery & refresh
- For "any Costco", the app finds the **nearest branches** around you and watches them.
- As you travel (coarse location, **not** continuous GPS), it refreshes to the branches
  near your new area — respecting OS geofence limits (iOS ≤ 20, Android ~90).

---

## 3. Hybrid voice parsing (local-first, LLM fallback)

Most commands are understood **on the device** with no network or AI call; the Gemini
backend is a fallback only for the hard cases.

| Outcome | Meaning | Example |
|---|---|---|
| **Resolved locally** | Understood on-device, no LLM | "remind me to buy milk at Walmart" |
| **Clarify** | One slot missing — asks a quick question, no LLM | "remind me when I reach home" → *"What should I remind you to do at Home?"* |
| **LLM fallback** | Unusual phrasing → Gemini `/v1/parse` | "grab coffee at the little place near the office then text Sam" |

- **Always confirms before saving** — you see an editable review screen every time.
- **Time is never mistaken for a place**: "call Mom at 5 PM" → 5 PM is a *time*, not a place.
- **Works offline** for local parsing, dynamic reminders, saved places, and notifications.
- Repeated identical phrasings are cached (relative times like "tomorrow" are never cached).

---

## 4. Time & recurring reminders

Reminders can fire on a **time**, a **place**, or both.

| Feature | Example |
|---|---|
| Date reminder | "Remind me to call the bank on December 1 at 10 am" |
| Birthday (annual) | "Remind me to wish Mom happy birthday on November 7 every year" |
| Daily | "Remind me to take my pills every day at 8 am" |
| Weekly | "Remind me about the team sync every Monday" |
| Monthly / yearly | "Remind me to pay rent monthly" · "Taxes annually" |
| Ask for missing time | "Remind me to take my pills daily" → *"What time should I remind you?"* |
| Manual picker | On the add screen: **When** (date + time) and **Repeat** (Daily/Weekly/Monthly/Yearly) |

- Recurring reminders re-fire automatically and survive an app restart/reboot (Android
  boot receiver).
- A pure time reminder (e.g. a birthday) has no location, so it simply fires at the time.

---

## 5. Smart inventory (personal & family)

A shared list of what you have and what you need — two states of one product.

| Feature | What it does |
|---|---|
| **Present Items** | What you already have at home |
| **Need to Buy** | What you still need to purchase |
| Add / edit / delete | Full control of each item (name, quantity, where-to-buy hint) |
| **One-tap "Bought"** | Moves a needed item → present for **everyone** instantly |
| **"Need"** | Moves a present item back to the shopping list |
| Duplicate guard | Warns if you add something already at home |
| Last Updated / Updated By | Each item shows "updated 5m ago by Asha" |
| **Personal ⇄ Family toggle** | Switch the same screens between your private list and the shared family list |

**Examples**
- Add **"rice · 2 bags · grocery store"** to Need to Buy.
- You buy it in the store → tap **Bought** → it flips to Present for the whole family, so
  nobody buys it again.
- Open the **Inventory** icon in the home app bar; use the **Personal / Family** segmented
  switch at the top.

---

## 6. Family sharing

Turn Surya into a shared family assistant.

| Feature | Example |
|---|---|
| Create a family | Settings → Family → **Create family** ("Sharma family") |
| Invite by code | Share the 6-char code (e.g. **7KQ4MP**); ambiguous letters (I/O/0/1) are excluded |
| Join by code | Enter a code → you're in the shared inventory |
| Member list | Shows real display names, an **Owner** badge, and "(You)" |
| Roles | **Any member** can edit items; only the **owner** can disband; members can leave |
| One family per user | Keeps sharing simple; solo users are unaffected |
| Live sync | Everyone sees adds/moves/"Bought" in real time |

---

## 7. Location shopping alerts (shared list → the right store)

When a family member reaches a store likely to carry a needed item, **that member** gets
an alert — so whoever's out shopping is reminded.

| Feature | Example |
|---|---|
| Auto store detection | Walk into a grocery store → alert listing matching needed items |
| What-to-buy summary | *"Hanu — 3 to buy here. Need: rice, milk, eggs. Already home: sugar."* |
| Store matching | Category heuristics: rice/milk → grocery; aspirin → pharmacy; charger → electronics |
| Local stores | Add a hint like **"Sai Market"** → matched via Places text search |
| One-tap **Bought** | From the notification, clears those items for everyone |
| Only the person present | The alert fires on the device of whoever is at the store |
| No spam | Same store won't re-alert within 30 minutes; no alert if the list is empty |

> **Honesty note:** this is store *likelihood* from category data — **not** real-time
> stock. We never claim a store definitely has an item.

---

## 8. Multilingual Hanu (English / हिन्दी / తెలుగు)

| Feature | Example |
|---|---|
| Language setting | Settings → **Language** → English / हिन्दी / తెలుగు (applies live) |
| Voice recognition | Speak in Telugu or Hindi (and mixed Hindi-English / Telugu-English) |
| Hanu speaks back | Confirmations are **spoken aloud** in your language (text-to-speech) |
| Localized notifications | The arrival reminder shows in your language |
| Localized UI | Core screens (settings, home, voice, confirmations) translated |

**Example** — with Telugu selected, after saving a reminder Hanu says and shows:
*"సరే — మీరు Costco చేరుకున్నప్పుడు buy rice గుర్తు చేస్తాను."*

> Your own words (the task, item names) are **never translated** — Hanu repeats them as you
> said them. Telugu/Hindi speech & voice quality depend on your device's language packs.

---

## 9. My Ideas

A private place to jot and find ideas.

| Feature | Example |
|---|---|
| Capture by voice | Tap the mic on the title/details field and dictate |
| Title + details + date | "Weekend hiking app — suggests nearby trails by difficulty" |
| Edit / delete | Tap an idea to edit; trash icon to delete |
| Search | Type "hiking" → filters instantly across title + details |

Open it from the **lightbulb** icon in the home app bar.

---

## 10. Sync, offline, push & subscription

| Feature | What it does |
|---|---|
| Offline-first | Create reminders/ideas/inventory offline; a banner shows "will sync"; syncs on reconnect |
| Live lists | Everything updates in real time via Firestore listeners |
| Push (FCM) | Device registered for push; background handler wired |
| Siri Shortcut (iOS) | "Tell Hanu to remind me…" opens the app with the text prefilled |
| Free tier | Up to **5 active** location reminders |
| Pro tier | Unlimited reminders (RevenueCat) — paywall with purchase/restore; app is Free-only until billing keys are set |

---

## 11. For the demo (end-to-end on a phone)

1. Say: **"Hey Hanu, remind me to buy rice when I'm at Costco."**
2. Review screen shows task **buy rice**, **Match any branch** on → **Save**.
3. Hanu confirms (spoken + on screen) in your chosen language.
4. Lock the phone, drive/walk into a Costco radius.
5. Notification fires **once**: *"Hanu reminder — You're near Costco — buy rice."*
6. Tap **Mark complete** → it never fires again.

---

## Developer notes & current limits

- **Platform:** verified on the toolchain (`flutter analyze` clean, 87 app tests + 9
  backend tests green, Android debug APK builds). On-device verification of geofencing,
  scheduled notifications, voice/STT/TTS, and push is pending (needs a real device; some
  needs a Mac/Xcode for iOS).
- **Backend:** FastAPI (`/v1/parse`, `/v1/nearby`, `/v1/confirm`) with Gemini + Google
  Places is built; a live Places/Gemini key and a Cloud Run deploy are still pending.
- **Honesty built in:** store alerts are category *likelihood*, not real stock; user text
  is never machine-translated; no LLM is ever in the geofence/notification path.
- **Incremental:** full UI translation currently covers the core screens; the inventory,
  ideas, family, and paywall screens are English for now (easy to extend).

See `PROGRESS.md` for the per-phase build log and `CLAUDE.md` for the full design spec.
