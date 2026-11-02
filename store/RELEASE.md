# Release & testing guide (Phase 6)

Manual, account-gated steps to get Surya onto TestFlight and Play internal
testing. Code is ready; these are the console/signing tasks a developer runs.

Build-time `--dart-define`s used across the app:
- `API_BASE_URL` — deployed Cloud Run URL (default is the dev `10.0.2.2:8011`).
- `RC_API_KEY_IOS`, `RC_API_KEY_ANDROID` — RevenueCat public SDK keys. If omitted,
  the app runs Free-only (billing gracefully disabled).

Example release build:
```
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://<cloud-run-url> \
  --dart-define=RC_API_KEY_ANDROID=goog_xxx

flutter build ipa --release \
  --dart-define=API_BASE_URL=https://<cloud-run-url> \
  --dart-define=RC_API_KEY_IOS=appl_xxx
```

---

## RevenueCat (billing)

1. Create a RevenueCat account and a project; add the iOS and Android apps.
2. Create an entitlement with identifier **`pro`** (matches
   `AppConfig.proEntitlementId`).
3. Create subscription products in App Store Connect and Play Console, then
   attach them to a RevenueCat **Offering** (the app reads the current offering's
   packages on the paywall).
4. Copy the **public SDK keys** and pass them as the `RC_API_KEY_*` dart-defines.
5. Verify: a Free account is capped at 5 active reminders; purchasing Pro removes
   the cap (the `pro` entitlement flips `isProProvider`).

---

## Privacy policy (Firebase Hosting)

Already configured in the root `firebase.json` (`public/` with a `/privacy`
rewrite). Deploy:
```
firebase deploy --only hosting
```
Live at `https://surya-assistance.web.app/privacy` — use that URL in both store
listings.

---

## iOS → TestFlight

1. In Xcode, open `app/ios/Runner.xcworkspace`. Set the team + signing for the
   `Runner` target (bundle id `com.suryaapp.surya`).
2. Enable capabilities on the Runner target:
   - **Push Notifications** (re-asserts `Runner/Runner.entitlements`).
   - **Background Modes** → Location updates + Remote notifications.
3. Upload an **APNs auth key** to the Firebase project (Cloud Messaging settings)
   so FCM can deliver to iOS.
4. Confirm the Siri App Intent: `SuryaIntents.swift` is in the Runner target
   (already wired in `project.pbxproj`). Test "Hey Siri, add a reminder in Surya".
5. Archive (Product → Archive) and upload to App Store Connect, or:
   `flutter build ipa --release --dart-define=...` then upload the IPA via
   Transporter / `xcrun altool`.
6. Add the build to a TestFlight internal group and invite testers.

## Android → Play internal testing

1. Create the app in Play Console (package `com.suryaapp.surya`).
2. Replace the debug signing in `app/android/app/build.gradle` with an upload
   keystore (create one with `keytool`; reference it via a `key.properties`).
3. `flutter build appbundle --release --dart-define=...` → upload the
   `.aab` to the **Internal testing** track.
4. Complete the **Data safety** form (see `store/listings.md`) and declare the
   use of background location (with a short justification + demo video — Google
   requires this for `ACCESS_BACKGROUND_LOCATION`).
5. Add testers by email to the internal testing track.

---

## Pre-submission checklist

- [ ] Cloud Run backend deployed; `API_BASE_URL` points at it.
- [ ] Gemini + Places API keys live in Secret Manager (backend).
- [ ] APNs key uploaded to Firebase (iOS push).
- [ ] RevenueCat `pro` entitlement + offering configured; keys injected.
- [ ] Privacy policy deployed and linked in both listings.
- [ ] On-device §8 loop verified (voice → geofence fires once → complete).
- [ ] Background-location justification prepared for Play review.
