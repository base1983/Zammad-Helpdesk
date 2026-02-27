# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Native iOS app (SwiftUI) serving as a mobile client for Zammad Helpdesk. Agents can manage tickets, view conversations, reply, and track time from their iPhones/iPads.

- **Language:** Swift 5.0
- **UI:** SwiftUI with MVVM pattern
- **Deployment Target:** iOS 26.0+
- **Bundle ID:** com.World-ICT.Zammad-Helpdesk

## Build Commands

```bash
# Build the project
xcodebuild -project "Zammad Helpdesk.xcodeproj" -scheme "Zammad Helpdesk" build

# Build for simulator
xcodebuild -project "Zammad Helpdesk.xcodeproj" -scheme "Zammad Helpdesk" -destination 'platform=iOS Simulator,name=iPhone 16' build

# Clean build
xcodebuild -project "Zammad Helpdesk.xcodeproj" -scheme "Zammad Helpdesk" clean build
```

No automated tests or linting tools are configured in this project.

## Architecture

### MVVM Layers

**Models** (`Models.swift`): All Zammad API entities — `Ticket`, `TicketState`, `TicketPriority`, `TicketArticle`, `User`, `Role`, `TicketGroup`, `Organization`, `TimeAccounting`, `TimeAccountingType`.

**ViewModel** (`TicketViewModel.swift`): Central `@MainActor` `ObservableObject` managing all ticket state. Holds `@Published` properties for tickets, metadata, filters, loading state, and errors. Uses `FilterType` enum: `.myTickets`, `.unassigned`, `.allOpen`, `.byStatus`.

**Views** (`Views/`): SwiftUI views. `ContentView` is the root — conditionally shows `SetupWizardView` or the main app. `TicketListView` is the primary screen.

### Networking

`ZammadAPIService.swift` is a singleton (`ZammadAPIService.shared`) handling all REST calls to `/api/v1/`. Uses token-based auth (`Authorization: Token token=...`). All methods are async/await. Has custom `APIError` enum. Gracefully handles 404 for optional features like time accounting.

### Manager Singletons (in `Managers/`)

- **SettingsManager** — persists config to UserDefaults (server URL, API token, theme, biometric lock, device token, proxy user ID)
- **AuthenticationManager** — FaceID/TouchID via `LAContext`
- **NotificationSetupManager** / **NotificationProxyService** — push notifications via custom proxy at `zammadproxy.world-ict.nl` (Zammad doesn't support direct APNS)
- **DeepLinkManager** — extracts ticket IDs from notification payloads and URLs using regex patterns
- **BackgroundTaskManager** — `BGTaskScheduler` for background ticket refresh every ~15 min
- **ReadStatusManager** — tracks locally which tickets have been viewed
- **StoreManager** — StoreKit 2 in-app purchase for ad removal

### App Entry Point

`Zammad_HelpdeskApp.swift` contains both the `@main` App struct and `AppDelegate`. The AppDelegate handles Google Mobile Ads init, background task registration, APNS token forwarding, and notification tap handling.

## Dependencies (Swift Package Manager)

- **Google Mobile Ads** (12.11.0) — AdMob banner ads
- **Lottie** (4.5.2) — splash/loading animations

## Key Conventions

- **Localization:** Use `.localized()` extension (from `Extensions.swift`) for all user-facing strings. Four languages: English, Dutch, German, French. String files in `Localization/[lang].lproj/Localizable.strings`.
- **API calls:** Always go through `ZammadAPIService.shared`. Handle errors with `APIError`.
- **Concurrency:** Use `Task {}` and `await`. UI updates must be on `@MainActor`. Avoid completion handlers.
- **UserDefaults keys:** Use snake_case (e.g., `zammad_api_token`, `is_biometric_lock_enabled`).
- **UI styling:** Use `StyledSection` for consistent section styling. Status/priority colors are defined in `TicketViewModel`.

## Notification Flow

Push notifications go through a proxy server because Zammad doesn't support APNS directly:
1. App registers with APNS, gets device token
2. Token + Zammad credentials sent to proxy (`NotificationProxyService`)
3. Proxy polls Zammad and forwards new ticket events via APNS
4. `DeepLinkManager` extracts ticket ID from notification and navigates to it

## Background Task IDs

- `com.baseonline.zammadhelpdesk.refresh`
- `com.worldict.helpdesk.refresh`
- `com.zammad.apprefresh` (BGTaskScheduler)
