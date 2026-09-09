# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

An iOS + watchOS client for Zammad (open-source helpdesk), **plus the two
servers it depends on**, all in one repo:

| Path | What | Runs where |
| --- | --- | --- |
| `Zammad Helpdesk/` | SwiftUI iOS app (`com.World-ICT.Zammad-Helpdesk`) | the phone |
| `Zammad Helpdesk Watch App/` | watchOS companion; compiles `Managers/Managers.swift` from the iOS target | the watch |
| `proxy/` | Node/Express relay for push notifications and the colleague chat | `zammadproxy.world-ict.nl` on web05 (Plesk, MariaDB) |
| `demo-server/` | Scripts that stand up and seed the App Review demo Zammad | `zammaddemo.world-ict.nl` on the same host |
| `docs/` | Support page + privacy policy, served by GitHub Pages from `main` | `https://base1983.github.io/Zammad-Helpdesk/` |

`PROXY_CHAT_API.md` is the **contract** between `ChatService.swift` and
`proxy/chat.js` — change one, change the other. `APP_STORE_LISTING.md` holds
store copy, review notes and the submit checklist. There are no tests and no
linter.

## Build

```bash
# iOS app, simulator (Xcode 26.6 ships no "iPhone 16" simulator; use iPhone 17)
xcodebuild -project "Zammad Helpdesk.xcodeproj" -scheme "Zammad Helpdesk" \
  -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build CODE_SIGNING_ALLOWED=NO

# Release archive (what ships); the watch app is embedded automatically
xcodebuild -project "Zammad Helpdesk.xcodeproj" -scheme "Zammad Helpdesk" \
  -destination 'generic/platform=iOS' -configuration Release archive -archivePath /tmp/ZH.xcarchive
```

Debug and Release differ on purpose: Debug uses Google's **test ad unit**,
Release the live one (`TicketListView`). Test purchases in the sandbox — there
is no debug shortcut for Premium.

**Before claiming a commit "builds clean", build the commit, not the working
tree**: `git worktree add --detach <scratch> HEAD` and build there. Several
features are usually in flight in this working tree at once, and partial
commits have shipped code that referenced symbols still sitting unstaged.

### Release mechanics that have bitten

- The embedded watch app must carry the **same `MARKETING_VERSION` and
  `CURRENT_PROJECT_VERSION`** as the iOS app — Xcode bumps only the target you
  edit. Both are in `project.pbxproj`; grep for both before archiving.
- Anything archived on a **beta macOS** is rejected by App Store Connect
  (ITMS-90111) regardless of the Xcode used — `BuildMachineOSBuild` is stamped
  into the bundle. Xcode Cloud (`xcshareddata/xcodecloud/`) builds on Apple's
  release macOS and overrides the build number with its own counter; match
  builds to commits by hash, not by number.
- `SKAdNetworkItems` must be dicts keyed `SKAdNetworkIdentifier`; the list is
  Google's full set, in `Zammad-Helpdesk-Info.plist`.

## Architecture

MVVM. `TicketViewModel` (`@MainActor` `ObservableObject`) owns ticket state and
filters; `ZammadAPIService.shared` is the only thing that talks to the user's
Zammad server (`/api/v1/`, `Authorization: Token token=…`, async/await,
`APIError`). `Models.swift` holds the Zammad entities. Views are in `Views/`;
`ContentView` switches between `SetupWizardView` and the app.

Everything user-facing goes through `.localized()` (`Utilities/Extensions.swift`);
strings live in `Zammad Helpdesk/{en,nl,de,fr}.lproj/Localizable.strings` and
must be added to **all four**. Shared state uses the app group
`group.com.World-ICT.Zammad-Helpdesk` (UserDefaults, snake_case keys) and the
Keychain service `com.World-ICT.Zammad-Helpdesk` (`KeychainHelper` in
`Managers/Managers.swift`).

### Push notifications

Zammad cannot talk to APNs, so: the app registers its device token with the
relay (`NotificationProxyService`), the user adds a **webhook trigger in
Zammad** pointing at a per-device relay URL (`WebhookGuideView` shows it), the
relay turns webhook calls into pushes (`proxy/server.js`). The relay tries the
production APNs host and falls back to sandbox on `BadDeviceToken`, so one
code path serves TestFlight and Xcode builds. `DeepLinkManager` reads the
structured payload keys (`ticketID`, `chat_from_user_id`, `chat_group_id`)
*before* its regex fallback — the fallback would misread a chat payload as a
ticket id. Notifications and the icon badge are **Premium** features.

### Colleague chat (end-to-end encrypted)

`ChatService` ↔ `proxy/chat.js`, contract in `PROXY_CHAT_API.md`. The relay
authenticates every call by replaying the caller's Zammad token against the
`X-Zammad-Url` instance, and scopes the directory per instance. Bodies,
attachments and group keys are sealed on the device (`ChatCrypto`: Curve25519
+ HKDF + ChaChaPoly); the relay stores ciphertext only.

Keys are **per device** (v4): a direct message gets a random content key
wrapped for every device of the recipient and every other device of the
sender; group keys are wrapped per device too. Consequences that look like
bugs but are not: a message sent before a device existed cannot be read on it,
and a demo/reviewer account must not have chat history from before their
install. Deletion tombstones a message (`deleted`, `deleted_at`), and polling
with `deleted_after` picks up tombstones and delivery/read ticks for messages
already on screen. Blocking is client-side (`ChatModeration.swift`); reporting
is a pre-filled e-mail, because only the reporter holds plaintext.

### Ads and Premium

`AdConsentManager` gates the Google Mobile Ads SDK behind UMP consent
(required in the EEA); the banner is mounted but zero-height until an ad has
actually loaded. `StoreManager` derives Premium from a lifetime purchase or an
active subscription and **from nothing else** — an automatic grant for
non-production builds was removed because App Review runs in the sandbox and
would never see the paywall. Product ids: `com.baseonline.zammadmobile.premium.{lifetime,month,yearly}`.

## Servers

- **Proxy deploy** is a file copy: `scp proxy/{chat.js,server.js,retention.js}`
  to `/var/www/vhosts/world-ict.nl/zammadproxy.world-ict.nl/` (ssh alias
  `world-ict-proxy`), back the old files up first, then `touch tmp/restart.txt`
  (Passenger). `initSchema()` in `chat.js` migrates the MariaDB schema at
  startup; if it fails the process exits, so a serving app proves migrations
  ran. Verify what is live with `sha256sum` against `git show <rev>:proxy/…`.
  `config.json` and the APNs `.p8` exist only on the server.
- **Proxy tests**: no test suite in the repo; the router has been exercised
  with an in-memory Express + `node:sqlite` harness that shims the MariaDB
  pool — rebuild that in the scratchpad when changing `chat.js`.
- **Demo Zammad** (`demo-server/README.md`): install script needs root on
  web05 (not available from the ssh alias), seeding runs from anywhere via the
  REST API. Wipe the demo chat before a review (README has the curl).

## Documents worth reading first

- `PROXY_CHAT_API.md` for any chat change (versions v1–v4 + v3.1–3.3 deletion
  and ticks).
- `APP_STORE_LISTING.md` §8/§8b/§11 before touching anything submission-related.
- `demo-server/README.md` for who does what on the demo host.
