import SwiftUI
import StoreKit

struct SettingsView: View {
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    
    // --- App Settings (via AppStorage voor automatische persistentie) ---
    @AppStorage("is_biometric_lock_enabled", store: Self.groupDefaults) private var isLockEnabled: Bool = false
    @AppStorage("are_ads_removed", store: Self.groupDefaults) private var areAdsRemoved: Bool = false
    @AppStorage("color_scheme_option", store: Self.groupDefaults) private var colorSchemeOption: String = "system"
    @AppStorage("background_light_option", store: Self.groupDefaults) private var lightBackgroundOption: String = BackgroundOption.flowers.rawValue
    @AppStorage("background_dark_option", store: Self.groupDefaults) private var darkBackgroundOption: String = BackgroundOption.pebbles.rawValue
    @AppStorage("chat_theme_light", store: Self.groupDefaults) private var lightChatTheme: String = ChatTheme.defaultLight.rawValue
    @AppStorage("chat_theme_dark", store: Self.groupDefaults) private var darkChatTheme: String = ChatTheme.defaultDark.rawValue
    @AppStorage(ChatHistoryStore.retentionKey, store: Self.groupDefaults) private var chatRetentionDays: Int = ChatHistoryStore.defaultRetentionDays
    
    // --- Server Config ---
    @AppStorage("zammad_server_url", store: Self.groupDefaults) private var serverURL: String = ""
    // Token lives in the Keychain (via SettingsManager), not in UserDefaults.
    @State private var apiToken: String = SettingsManager.shared.loadToken() ?? ""
    
    // --- Lokale State ---
    @State private var testStatus: String?
    @State private var isTesting = false
    @State private var isShowingWebhookGuide = false
    @State private var isShowingLoginSheet = false
    @State private var isShowingSSOSheet = false

    var body: some View {
        NavigationStack {
            Form {
                // 1. Server Configuratie
                serverConfigSection
                
                // 2. Beveiliging
                securitySection
                
                // 3. Uiterlijk
                appearanceSection
                
                // 3b. Chat
                chatSection
                
                // 4. Notificaties (De nieuwe logica)
                notificationsSection
                
                // 5. Abonnementen
                InAppPurchaseView()
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear)
            .navigationTitle("settings".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { saveAndDismiss() }) {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .sheet(isPresented: $isShowingWebhookGuide) {
                // Zorg dat je WebhookGuideView bestand bestaat, anders deze regel weghalen
                WebhookGuideView()
            }
        }
    }
    
    // MARK: - 1. Server Config Section
    private var serverConfigSection: some View {
        Section(header: Text("server_configuration".localized())) {
            TextField("zammad_instance_url".localized(), text: $serverURL)
                .keyboardType(.URL)
                .autocapitalization(.none)
                .textContentType(.URL)

            SecureField("paste_api_token".localized(), text: $apiToken)

            Button {
                isShowingSSOSheet = true
            } label: {
                Label("login_with_sso".localized(), systemImage: "globe")
            }
            .font(.subheadline)
            .disabled(serverURL.isEmpty)

            Button {
                isShowingLoginSheet = true
            } label: {
                Label("login_with_password".localized(), systemImage: "person.badge.key")
            }
            .font(.subheadline)

            HStack {
                Button("test_connection".localized()) { testConnection() }
                    .disabled(isTesting)

                if isTesting {
                    ProgressView().padding(.leading, 5)
                }

                Spacer()

                if let status = testStatus {
                    Text(status)
                        .font(.caption)
                        .foregroundColor(status == "connection_successful".localized() ? .green : .red)
                }
            }
        }
        .sheet(isPresented: $isShowingLoginSheet) {
            PasswordLoginSheet(serverURL: serverURL) { newToken in
                apiToken = newToken
                // Persist immediately so a freshly minted token survives
                // even if the settings sheet is swiped away without saving.
                SettingsManager.shared.save(token: newToken)
                testStatus = "connection_successful".localized()
            }
        }
        .sheet(isPresented: $isShowingSSOSheet) {
            SSOLoginView(serverURL: serverURL) { newToken in
                apiToken = newToken
                SettingsManager.shared.save(token: newToken)
                testStatus = "connection_successful".localized()
            }
        }
    }
    
    // MARK: - 2. Security Section
    private var securitySection: some View {
        Section(header: Text("security".localized())) {
            Toggle("enable_biometric_lock".localized(), isOn: $isLockEnabled)
        }
    }
    
    // MARK: - 3. Appearance Section
    private var appearanceSection: some View {
        Section(header: Text("appearance".localized())) {
            Picker("theme".localized(), selection: $colorSchemeOption) {
                ForEach(ColorSchemeOption.allCases) { option in
                    Text(option.localizedString).tag(option.rawValue)
                }
            }
            .pickerStyle(.segmented)

            backgroundPicker(
                title: "background_light_mode".localized(),
                systemImage: "sun.max",
                wallpapers: BackgroundOption.lightWallpapers,
                colors: BackgroundOption.lightColors,
                selection: $lightBackgroundOption
            )
            backgroundPicker(
                title: "background_dark_mode".localized(),
                systemImage: "moon",
                wallpapers: BackgroundOption.darkWallpapers,
                colors: BackgroundOption.darkColors,
                selection: $darkBackgroundOption
            )

            chatThemePicker(title: "chat_theme_light_mode".localized(), systemImage: "bubble.left", themes: ChatTheme.lightThemes, selection: $lightChatTheme)
            chatThemePicker(title: "chat_theme_dark_mode".localized(), systemImage: "bubble.left.fill", themes: ChatTheme.darkThemes, selection: $darkChatTheme)
        }
    }

    // MARK: - 3b. Chat Section
    private var chatSection: some View {
        Section(
            header: Text("chat".localized()),
            footer: Text("chat_history_retention_footer".localized())
        ) {
            Picker(selection: $chatRetentionDays) {
                Text("chat_retention_30".localized()).tag(30)
                Text("chat_retention_90".localized()).tag(90)
                Text("chat_retention_180".localized()).tag(180)
                Text("chat_retention_365".localized()).tag(365)
                Text("chat_retention_forever".localized()).tag(0)
            } label: {
                Label("chat_history_retention".localized(), systemImage: "clock.arrow.circlepath")
            }
            .onChange(of: chatRetentionDays) { _, _ in
                Task.detached(priority: .utility) { ChatHistoryStore.shared.pruneAll() }
            }
        }
    }

    private func chatThemePicker(title: String, systemImage: String, themes: [ChatTheme], selection: Binding<String>) -> some View {
        NavigationLink {
            ChatThemePickerView(title: title, themes: themes, selection: selection)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                ChatThemePreview(theme: ChatTheme(rawValue: selection.wrappedValue) ?? themes[0])
                    .frame(width: 30, height: 40)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
                    }
            }
        }
    }

    private func backgroundPicker(title: String, systemImage: String, wallpapers: [BackgroundOption], colors: [BackgroundOption], selection: Binding<String>) -> some View {
        NavigationLink {
            BackgroundPickerView(title: title, wallpapers: wallpapers, colors: colors, selection: selection)
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                Spacer()
                backgroundPreviewSwatch(for: BackgroundOption(rawValue: selection.wrappedValue) ?? wallpapers[0])
            }
        }
    }

    /// Miniature preview of the currently selected background.
    private func backgroundPreviewSwatch(for option: BackgroundOption) -> some View {
        Group {
            switch option.previewStyle {
            case .image(let name):
                Image(name)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            case .color(let color):
                color
            }
        }
        .frame(width: 24, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        }
    }
    
    // MARK: - 4. Notifications Section (Wrapper)
    private var notificationsSection: some View {
        Section(header: Text("notifications".localized())) {
            if apiToken.isEmpty {
                Text("configure_server_for_notifications".localized())
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else if !areAdsRemoved {
                // Real-time notifications and the icon badge are premium.
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "crown.fill")
                        .foregroundColor(.yellow)
                    Text("notifications_premium_required".localized())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                // Hier roepen we de slimme sectie aan
                NotificationSettingsSection()
                
                // Knop naar handleiding
                Button("setup_guide".localized()) {
                    isShowingWebhookGuide = true
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: - Actions
    private func saveAndDismiss() {
        // Sla waarden expliciet op in SettingsManager voor de zekerheid
        SettingsManager.shared.save(serverURL: serverURL)
        SettingsManager.shared.save(token: apiToken)
        SettingsManager.shared.save(isLockEnabled: isLockEnabled)
        
        // Send updated credentials to Apple Watch
        WatchConnectivityManager.shared.sendCredentialsToWatch()
        
        onSave()
        dismiss()
    }
    
    private func testConnection() {
        isTesting = true
        testStatus = "testing_connection".localized()
        Task {
            let success = await ZammadAPIService.shared.testConnection(url: serverURL, token: apiToken)
            await MainActor.run {
                testStatus = success ? "connection_successful".localized() : "connection_failed".localized()
                isTesting = false
            }
        }
    }
}

// MARK: - Component: Password Login Sheet
struct PasswordLoginSheet: View {
    let serverURL: String
    let onTokenReceived: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var password = ""
    @State private var isLoggingIn = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("credentials".localized())) {
                    TextField("username_placeholder".localized(), text: $username)
                        .autocapitalization(.none)
                        .textContentType(.username)
                    SecureField("password_placeholder".localized(), text: $password)
                        .textContentType(.password)
                }

                Section {
                    Button(action: login) {
                        HStack {
                            if isLoggingIn { ProgressView().padding(.trailing, 4) }
                            Text("login".localized())
                        }
                    }
                    .disabled(isLoggingIn || username.isEmpty || password.isEmpty || serverURL.isEmpty)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Text("password_login_explainer".localized())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("login_with_password".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) { dismiss() }
                }
            }
        }
    }

    private func login() {
        isLoggingIn = true
        errorMessage = nil
        Task {
            do {
                let tokenName = "iOS Helpdesk – \(UIDevice.current.name)"
                let token = try await ZammadAPIService.shared.createAccessToken(
                    url: serverURL,
                    username: username,
                    password: password,
                    tokenName: tokenName
                )
                await MainActor.run {
                    onTokenReceived(token)
                    isLoggingIn = false
                    dismiss()
                }
            } catch APIError.authenticationFailed {
                await MainActor.run {
                    errorMessage = "login_failed".localized()
                    isLoggingIn = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isLoggingIn = false
                }
            }
        }
    }
}

// MARK: - Component: Notification Settings Section (Slimme Logica)
struct NotificationSettingsSection: View {
    @StateObject private var notifManager = NotificationSetupManager.shared
    // We lezen de status direct uit de SettingsManager
    @State private var isToggleOn: Bool = SettingsManager.shared.areRealtimeNotificationsEnabled()
    @State private var showCopiedMessage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            
            // A. De Schakelaar
            Toggle(isOn: $isToggleOn) {
                VStack(alignment: .leading) {
                    Text("realtime_notifications".localized())
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    Text("realtime_notifications_subtitle".localized())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .onChange(of: isToggleOn) { _, newValue in
                print("DEBUG: Notificatie Toggle gewijzigd naar: \(newValue)")
                SettingsManager.shared.save(areRealtimeNotificationsEnabled: newValue)
                
                if newValue {
                    notifManager.enableNotifications()
                } else {
                    Task {
                        await NotificationProxyService.shared.updateRegistration(isSubscribing: false)
                        await MainActor.run { notifManager.isRegistered = false }
                    }
                }
            }
            
            // B. Status Feedback
            if notifManager.isLoading {
                HStack {
                    ProgressView().scaleEffect(0.8).padding(.trailing, 5)
                    Text("linking_to_zammad".localized())
                        .font(.caption).foregroundColor(.orange)
                }
            } else if let error = notifManager.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                    Text(error).font(.caption).foregroundColor(.red)
                }
            }
            
            // C. Webhook URL (Alleen tonen als geregistreerd EN user ID bekend)
            // We checken hier expliciet of we een proxyUserID hebben
            if isToggleOn, let userID = SettingsManager.shared.getProxyUserID(), !userID.isEmpty {
                
                Divider().padding(.vertical, 5)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                        Text("linked_set_url_in_zammad".localized())
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    let webhookURL = "https://zammadproxy.world-ict.nl/api/webhook/\(userID)"
                    
                    HStack {
                        Text(webhookURL)
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .foregroundColor(.primary)
                            .layoutPriority(1)
                        
                        Spacer()
                        
                        Button(action: {
                            UIPasteboard.general.string = webhookURL
                            withAnimation { showCopiedMessage = true }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                withAnimation { showCopiedMessage = false }
                            }
                        }) {
                            Image(systemName: showCopiedMessage ? "checkmark" : "doc.on.doc")
                                .foregroundColor(showCopiedMessage ? .green : .blue)
                                .font(.system(size: 18))
                        }
                    }
                    .padding(10)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                .transition(.opacity)
            }
        }
        .padding(.vertical, 5)
        .onAppear {
            // Check bij laden of we al geregistreerd zijn
            if SettingsManager.shared.loadDeviceToken() != nil && isToggleOn {
                notifManager.isRegistered = true
            }
        }
    }
}

// MARK: - Component: In-App Purchase View
private struct InAppPurchaseView: View {
    @StateObject private var storeManager = StoreManager()
    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    @AppStorage("are_ads_removed", store: Self.groupDefaults) private var areAdsRemoved: Bool = false
    @ObservedObject private var adConsent = AdConsentManager.shared

    var body: some View {
        Section(header: Text("in_app_purchases".localized())) {
            if areAdsRemoved {
                HStack {
                    Image(systemName: "star.fill").foregroundColor(.yellow)
                    Text("premium_user_message".localized())
                        .fontWeight(.medium)
                }
            } else if storeManager.isLoadingProducts {
                HStack {
                    ProgressView().scaleEffect(0.8)
                    Text("loading_products".localized())
                }
            } else {
                if let monthly = storeManager.monthlyProduct {
                    productButton(for: monthly, description: "premium_description_monthly".localized())
                }
                if let yearly = storeManager.yearlyProduct {
                    productButton(for: yearly, description: "premium_description_yearly".localized())
                }
                if let lifetime = storeManager.lifetimeProduct {
                    productButton(for: lifetime, description: "premium_description_lifetime".localized())
                }
            }
            
            if !areAdsRemoved && !storeManager.isLoadingProducts {
                Button("restore_purchases".localized()) {
                    Task { await storeManager.restorePurchases() }
                }
                .font(.footnote)
            }

            // Google's consent policy requires a lasting way to change the ad
            // consent choice. UMP only asks for one where a form applies, so
            // the row appears exactly when it is required — and never for
            // premium users, who see no ads at all.
            if !areAdsRemoved && adConsent.isPrivacyOptionsRequired {
                Button("ad_privacy_options".localized()) {
                    adConsent.presentPrivacyOptions()
                }
                .font(.footnote)
            }
        }
        .disabled(storeManager.isTransactionInProgress)
    }
    
    private func productButton(for product: Product, description: String) -> some View {
        Button(action: {
            Task { await storeManager.purchase(product) }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(product.displayName)
                        .font(.headline)
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(product.displayPrice)
                    .fontWeight(.bold)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
            }
            .foregroundColor(.primary)
            .padding(.vertical, 4)
        }
    }
}
