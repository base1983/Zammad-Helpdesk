# Zammad Helpdesk - iOS Project Overview

This is a native iOS application built with SwiftUI that serves as a mobile client for the Zammad Helpdesk system. It allows agents to manage tickets, view articles, send replies, and track time directly from their iPhones.

## Architecture & Core Technologies

- **Framework:** SwiftUI (Declarative UI)
- **Pattern:** MVVM (Model-View-ViewModel)
- **Concurrency:** Swift Concurrency (Async/Await)
- **Persistence:** `UserDefaults` (via `SettingsManager`) and `AppStorage`.
- **Networking:** REST API interaction with Zammad via `ZammadAPIService`.
- **Notifications:** Push notifications managed through a custom proxy (`zammadproxy.world-ict.nl`) handled by `NotificationProxyService` and `NotificationSetupManager`.
- **Security:** Optional biometric lock (FaceID/TouchID) managed by `AuthenticationManager`.
- **Background Tasks:** Background refresh support using `BGTaskScheduler` and `BackgroundTaskManager`.
- **Monetization:** Google Mobile Ads (AdMob) integration.
- **Localization:** Supports Dutch (`nl`), English (`en`), French (`fr`), and German (`de`).

## Project Structure

- `Zammad Helpdesk/`
    - `Zammad_HelpdeskApp.swift`: App entry point and `AppDelegate` for lifecycle management.
    - `ZammadAPIService.swift`: Centralized network layer for all Zammad API calls.
    - `Models.swift`: Swift representations of Zammad API entities (Ticket, User, Article, etc.).
    - `TicketViewModel.swift`: Main business logic for fetching, filtering, and searching tickets.
    - `Managers/`: Singletons for specific system-level features:
        - `SettingsManager`: Handles app configuration (Server URL, Token, Theme).
        - `NotificationSetupManager` & `NotificationProxyService`: Push notification registration and proxy interaction.
        - `DeepLinkManager`: Logic for routing to specific tickets from URLs or notifications.
        - `AuthenticationManager`: Biometric security logic.
        - `ReadStatusManager`: Tracks which tickets have been read locally.
    - `Views/`: SwiftUI views organized by feature (TicketList, TicketDetail, TicketReply, Settings, etc.).
    - `Utilities/`: Extensions and UI helpers (e.g., `AdBannerView`, `StyledSection`).

## Key Workflows

### 1. Setup and Authentication
- The app uses a `SetupWizardView` for first-time configuration.
- Requires a Zammad Server URL and a Personal Access Token.
- Biometric lock can be enabled in settings.

### 2. Ticket Management
- Tickets are filtered by "My Tickets", "Unassigned", or "All Open".
- Search functionality is integrated via `ZammadAPIService.searchTickets`.
- `TicketDetailView` shows the conversation history (Articles).
- Users can update ticket metadata (Owner, State, Priority) and add internal notes or public replies.

### 3. Notifications & Deep Linking
- Push notifications are sent via a proxy server to bypass Zammad's limitation with direct APNS.
- Tapping a notification triggers `DeepLinkManager`, which resolves the Ticket ID and instructs `ContentView` to display the specific ticket.

### 4. Time Accounting
- If enabled on the Zammad instance, agents can log time units when updating tickets or adding articles.

## Building and Running

### Prerequisites
- **Xcode:** 15.0 or later.
- **Swift:** 5.9 or later.
- **CocoaPods/SwiftPM:** The project appears to use Swift Package Manager for dependencies like Google Mobile Ads and Lottie.

### Commands (Inferred)
- **Build:** `xcodebuild -project "Zammad Helpdesk.xcodeproj" -scheme "Zammad Helpdesk" build`
- **Run:** Use Xcode to run on a simulator or physical device.
- **Testing:** No explicit test files were found in the initial scan; verification is primarily manual via the app UI.

## Development Conventions

- **Localization:** Use `.localized()` extension (found in `Extensions.swift`) for all user-facing strings.
- **API Calls:** Always use `ZammadAPIService.shared`. Ensure proper error handling using `APIError`.
- **UI Consistency:** Use `StyledSection` and the established color patterns in `TicketViewModel` for status and priority colors.
- **Asynchronous Code:** Prefer `Task` and `await` over completion handlers. UI updates must happen on the `@MainActor`.
