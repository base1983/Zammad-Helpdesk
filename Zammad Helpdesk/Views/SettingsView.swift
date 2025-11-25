import SwiftUI
import StoreKit

struct SettingsView: View {
    let onSave: () -> Void
    @Environment(\.dismiss) var dismiss
    
    // --- App Settings (via AppStorage voor automatische persistentie) ---
    @AppStorage("is_biometric_lock_enabled") private var isLockEnabled: Bool = false
    @AppStorage("color_scheme_option") private var colorSchemeOption: String = "system"
    
    // --- Server Config ---
    @AppStorage("zammad_server_url") private var serverURL: String = ""
    @AppStorage("zammad_api_token") private var apiToken: String = ""
    
    // --- Lokale State ---
    @State private var testStatus: String?
    @State private var isTesting = false
    @State private var isShowingWebhookGuide = false

    var body: some View {
        NavigationStack {
            Form {
                // 1. Server Configuratie
                serverConfigSection
                
                // 2. Beveiliging
                securitySection
                
                // 3. Uiterlijk
                appearanceSection
                
                // 4. Notificaties (De nieuwe logica)
                notificationsSection
                
                // 5. Abonnementen
                InAppPurchaseView()
            }
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
        }
    }
    
    // MARK: - 4. Notifications Section (Wrapper)
    private var notificationsSection: some View {
        Section(header: Text("notifications".localized())) {
            if apiToken.isEmpty {
                Text("configure_server_for_notifications".localized())
                    .font(.caption)
                    .foregroundColor(.secondary)
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
    @AppStorage("are_ads_removed") private var areAdsRemoved: Bool = false
    
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
            }
            
            if !areAdsRemoved && !storeManager.isLoadingProducts {
                Button("restore_purchases".localized()) {
                    Task { await storeManager.restorePurchases() }
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
