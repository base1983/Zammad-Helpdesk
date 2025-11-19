import Foundation
import SwiftUI
import Combine
import UserNotifications
import LocalAuthentication

/// Een gedeelde manager voor algemene instellingen en status.

enum ColorSchemeOption: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: Self { self }

    var localizedString: String {
        switch self {
        case .system: "theme_system".localized()
        case .light: "theme_light".localized()
        case .dark: "theme_dark".localized()
        }
    }
}

class SettingsManager {
    static let shared = SettingsManager()
    
    // Keys voor UserDefaults
    private let tokenKey = "zammad_api_token"
    private let lockKey = "is_biometric_lock_enabled"
    private let themeKey = "color_scheme_option"
    private let serverURLKey = "zammad_server_url"
    private let adsRemovedKey = "are_ads_removed"
    
    private let realtimeNotificationsEnabledKey = "realtime_notifications_enabled"
    private let proxyUserIDKey = "proxy_user_id_key"
    private let deviceTokenKey = "apn_device_token"
    private let lastFetchDateKey = "background_last_fetch_date"

    // MARK: - API & Server Settings
    func save(token: String) { UserDefaults.standard.set(token, forKey: tokenKey) }
    func loadToken() -> String? { UserDefaults.standard.string(forKey: tokenKey) }
    
    func save(serverURL: String) { UserDefaults.standard.set(serverURL, forKey: serverURLKey) }
    func loadServerURL() -> String { UserDefaults.standard.string(forKey: serverURLKey) ?? "" }
    
    // MARK: - Security & Appearance
    func save(isLockEnabled: Bool) { UserDefaults.standard.set(isLockEnabled, forKey: lockKey) }
    func isLockEnabled() -> Bool { UserDefaults.standard.bool(forKey: lockKey) }
    
    func save(theme: ColorSchemeOption) { UserDefaults.standard.set(theme.rawValue, forKey: themeKey) }
    func loadTheme() -> ColorSchemeOption {
        let savedValue = UserDefaults.standard.string(forKey: themeKey) ?? ""
        return ColorSchemeOption(rawValue: savedValue) ?? .system
    }

    // MARK: - In-App Purchases
    func save(areAdsRemoved: Bool) { UserDefaults.standard.set(areAdsRemoved, forKey: adsRemovedKey) }
    func areAdsRemoved() -> Bool { UserDefaults.standard.bool(forKey: adsRemovedKey) }
    
    // MARK: - Notification Settings
    // AANGEPAST: Deze functie slaat nu ALLEEN de voorkeur op.
    // De logica voor aan/afmelden zit in je NotificationSetupManager en de UI Toggle.
    func save(areRealtimeNotificationsEnabled: Bool) {
        UserDefaults.standard.set(areRealtimeNotificationsEnabled, forKey: realtimeNotificationsEnabledKey)
    }
    func areRealtimeNotificationsEnabled() -> Bool { UserDefaults.standard.bool(forKey: realtimeNotificationsEnabledKey) }
    
    // Proxy & Token Management (Nodig voor NotificationProxyService)
    func save(proxyUserID: String) { UserDefaults.standard.set(proxyUserID, forKey: proxyUserIDKey) }
    func getProxyUserID() -> String? { UserDefaults.standard.string(forKey: proxyUserIDKey) }
    
    func save(deviceToken: String) { UserDefaults.standard.set(deviceToken, forKey: deviceTokenKey) }
    func loadDeviceToken() -> String? { UserDefaults.standard.string(forKey: deviceTokenKey) }

    // Hulpfunctie voor debugging
    func getWebhookURL() -> String? {
        guard let userID = getProxyUserID() else { return nil }
        return "https://zammadproxy.world-ict.nl/webhook/\(userID)"
    }
    
    // MARK: - Background Task Management
    func save(lastFetchDate: Date) { UserDefaults.standard.set(lastFetchDate, forKey: lastFetchDateKey) }
    func loadLastFetchDate() -> Date { UserDefaults.standard.object(forKey: lastFetchDateKey) as? Date ?? .distantPast }
}

// LET OP: Ik heb de 'NotificationManager' class hier verwijderd.
// Je gebruikt nu 'NotificationSetupManager.swift' (uit het vorige antwoord) voor die logica.

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isUnlocked = false
    
    func authenticate() {
        // Als slot uit staat, is hij altijd unlocked
        guard SettingsManager.shared.isLockEnabled() else {
            isUnlocked = true
            return
        }
        
        let context = LAContext()
        var error: NSError?
        
        // Check of FaceID/TouchID mogelijk is
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock_reason".localized()) { success, authenticationError in
                DispatchQueue.main.async {
                    if success {
                        self.isUnlocked = true
                    } else {
                        // Mislukt (bijv. geannuleerd door gebruiker)
                        self.isUnlocked = false
                        print("Authenticatie mislukt: \(String(describing: authenticationError))")
                    }
                }
            }
        } else {
            // Als het apparaat geen FaceID heeft of geen pincode, laten we de gebruiker erdoor
            // Anders sluit je mensen buiten met oudere telefoons
            print("Biometrie niet beschikbaar: \(String(describing: error))")
            isUnlocked = true
        }
    }
    
    func lock() {
        if SettingsManager.shared.isLockEnabled() { isUnlocked = false }
    }
}
