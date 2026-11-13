# Helpdesk for Zammad — Android

Android (phone/tablet) and Wear OS port of the iOS app in `../Zammad Helpdesk/`.
Kotlin, Jetpack Compose (Material 3), single activity, MVVM with the same layout
as iOS. Application id `com.baseonline.zammadmobile`.

| Path | What |
| --- | --- |
| `app/` | Phone/tablet app |
| `wear/` | Wear OS companion (ticket list and detail; gets its credentials from the phone) |
| `tools/sync_ios_resources.py` | Regenerates `strings.xml` and the wallpapers from the iOS sources |

How the pieces map to iOS:

| iOS | Android (`app/src/main/java/com/baseonline/zammadmobile/`) |
| --- | --- |
| `ZammadAPIService`, `Models` | `data/ZammadApi.kt`, `data/Models.kt` |
| `SettingsManager`, `KeychainHelper` | `data/SettingsManager.kt`, `data/SecureStore.kt` (AES-GCM key in the Android Keystore) |
| `TicketViewModel` | `TicketViewModel.kt` |
| `ChatService`, `ChatCrypto` | `chat/` — protocol v4, see `../PROXY_CHAT_API.md` |
| `StoreManager` (StoreKit) | `managers/StoreManager.kt` (Play Billing) |
| `AdConsentManager`, ad managers | `managers/Ads.kt` (AdMob + UMP) |
| `NotificationProxyService`, APNs | `managers/PushManager.kt`, `push/HelpdeskMessagingService.kt` (FCM) |
| `BackgroundTaskManager` | `managers/BackgroundRefresh.kt` (WorkManager) |
| `WatchConnectivityManager` | `managers/AuthAndWear.kt` (`WearSync`, Wearable Data Layer) |
| `Views/` | `ui/screens/`, shell in `ui/AppRoot.kt` |

## Build

Needs Android Studio (its bundled JDK is enough) and the Android SDK (platform 37).

```bash
cd android
export JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home"
./gradlew assembleDebug            # app/build/outputs/apk/debug/app-debug.apk
./gradlew :app:testDebugUnitTest   # includes the iOS crypto interop test
./gradlew bundleRelease            # app/build/outputs/bundle/release/app-release.aab
./gradlew :wear:bundleRelease      # wear/build/outputs/bundle/release/wear-release.aab
```

To try the app without a real server: `python3 tools/mock_zammad.py`, then
`adb reverse tcp:8089 tcp:8089` and use server `http://127.0.0.1:8089` with any
token in the wizard (tickets work; the chat needs a real Zammad, because the
relay validates the token). Any other `http://` server URL is refused: the app
only talks HTTPS.

Debug builds use Google's **test** AdMob ids. Release builds use the ids in
`local.properties` and fall back to the test ids when they are missing, so a
release build without them works but earns nothing.

### Files that are not in git (the repo is public)

| File | Content | Needed for |
| --- | --- | --- |
| `android/local.properties` | `sdk.dir=…` plus the AdMob ids below | building; real ads |
| `android/keystore.properties` | `storeFile`, `storePassword`, `keyAlias`, `keyPassword` | a signed release |
| `android/app/google-services.json` | Firebase config | push notifications |
| `*.jks` / `*.keystore` | the upload key | a signed release |

```properties
# local.properties
admob.appId=ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY
admob.banner=ca-app-pub-XXXXXXXXXXXXXXXX/…
admob.interstitial=ca-app-pub-XXXXXXXXXXXXXXXX/…
admob.appOpen=ca-app-pub-XXXXXXXXXXXXXXXX/…
```

```properties
# keystore.properties (storeFile is relative to android/)
storeFile=upload-keystore.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

Without `keystore.properties` `bundleRelease` still succeeds but the bundle is
unsigned; Play Console rejects that. Without `google-services.json` the app
builds and runs with push switched off (Settings says so).

## Things that must stay in step with iOS

- **Chat crypto.** `chat/ChatCryptoCore.kt` must stay bit-compatible with
  `ChatCrypto` in `ChatService.swift`: X25519, HKDF-SHA256 with salt
  `zammad-helpdesk-chat-v1` and empty info, ChaCha20-Poly1305 in CryptoKit's
  "combined" layout (nonce ‖ ciphertext ‖ tag), bodies prefixed `enc1:`.
  `ChatCryptoInteropTest` opens vectors produced by CryptoKit; change one side
  and that test tells you.
- **Chat protocol.** `chat/ChatService.kt` ↔ `proxy/chat.js`, contract in
  `../PROXY_CHAT_API.md`.
- **Strings.** `app/src/main/res/values*/strings.xml` are generated from the
  iOS `Localizable.strings` (key = resource name; iOS key `on` becomes `s_on`).
  After changing iOS strings run `python3 android/tools/sync_ios_resources.py`
  (add `--images` to regenerate the wallpapers too; macOS only). Android-only
  strings live in `strings_android.xml`, in all four languages.
- **Version.** `versionName`/`versionCode` are in `app/build.gradle.kts` and
  `wear/build.gradle.kts`; Play requires a higher `versionCode` for every upload.

## Push notifications (FCM)

Same design as iOS: the app registers a device token with the relay, the user
adds a webhook trigger in Zammad pointing at their per-device relay URL, the
relay turns webhook calls into pushes. Differences:

- The app sends `platform: "android"` to `POST /api/register`; the relay stores
  the token as `fcm:<token>` in the existing `registrations.deviceToken` column
  and sends through `proxy/fcm.js` (FCM HTTP v1, no npm dependency) instead of
  APNs. `chat.js` is unchanged.
- Pushes are FCM *data* messages; the app builds the notification itself.
- The Android app does not send the Zammad API token to the relay (the relay
  never used it for push).

The relay change is in the repo but **not deployed**. To switch it on:

1. Firebase console → create a project → add an Android app with package
   `com.baseonline.zammadmobile` → download `google-services.json` into
   `android/app/` (not committed).
2. Project settings → Service accounts → generate a private key. Put that JSON
   **on the server only**, next to `config.json`, and add to `config.json`:
   `"fcm": { "serviceAccountPath": "/var/www/vhosts/world-ict.nl/zammadproxy.world-ict.nl/firebase-service-account.json" }`
3. Deploy `proxy/server.js` **and** `proxy/fcm.js` the usual way (back up, copy,
   `touch tmp/restart.txt`). Without the `fcm` block the relay behaves exactly
   as before for iOS and logs that Android pushes are disabled.

## Premium (Play Billing)

`StoreManager` derives Premium from a lifetime purchase or an active
subscription and from nothing else; there is no debug shortcut. Create these in
Play Console with exactly these ids:

| Id | Type |
| --- | --- |
| `com.baseonline.zammadmobile.premium.lifetime` | One-time product |
| `com.baseonline.zammadmobile.premium.month` | Subscription (one monthly base plan) |
| `com.baseonline.zammadmobile.premium.yearly` | Subscription (one yearly base plan) |

Purchases only work in a build installed from Play (internal testing track is
enough) with a licence-tester account; in a sideloaded debug build the paywall
shows "products unavailable".

## Release checklist (what only the account owner can do)

1. **Play Console account** (one-time fee, identity verification) and a new app
   with package `com.baseonline.zammadmobile`. A new personal account must run a
   closed test with 12 testers for 14 days before production access.
2. **Upload key**: `keytool -genkeypair -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload`,
   then `keystore.properties`. Keep both out of git and back them up. Enrol in
   Play App Signing when uploading the first bundle.
3. **Firebase project** and the relay deploy (see above) for push.
4. **AdMob**: add an Android app, create a banner, an interstitial and an
   app-open unit, put the ids in `local.properties`, link the app to its Play
   listing, and add the Android app to `app-ads.txt` (same publisher id, so the
   existing line already covers it). Configure the GDPR message in AdMob →
   Privacy & messaging for the Android app (UMP shows it).
5. **Billing products** (table above), prices, and licence testers.
6. **Store listing**: title, short/full description (reuse `../APP_STORE_LISTING.md`),
   phone and 7"/10" tablet screenshots, 512 px icon, 1024×500 feature graphic,
   category, contact e-mail, privacy policy URL
   (`https://base1983.github.io/Zammad-Helpdesk/`).
7. **App content forms**: Data safety (Zammad token stored on device; device
   token and chat ciphertext sent to the relay; advertising id via AdMob),
   Ads = yes, content rating questionnaire, target audience (not children),
   and App access: give reviewers the demo server URL and token, as for Apple.
8. **Wear OS**: upload `wear-release.aab` to the same app under the Wear OS form
   factor (Play Console → Advanced settings → Form factors), with Wear
   screenshots. It goes through its own review.
9. Upload the bundles to internal testing first; verify purchases, ads and push
   there before promoting.
