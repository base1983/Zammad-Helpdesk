import Foundation
import SwiftUI
import Combine
import UserNotifications
import LocalAuthentication
import Security

/// Minimal Keychain wrapper for storing small secrets like the Zammad API token.
/// Items use `kSecAttrAccessibleAfterFirstUnlock` so background refresh can
/// still read them while the device is locked.
enum KeychainHelper {
    private static let service = "com.World-ICT.Zammad-Helpdesk"

    static func save(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let addQuery = query.merging(attributes) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    static func load(forKey key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

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

enum BackgroundOption: String, CaseIterable, Identifiable {
    // Wallpapers — light
    case flowers, desert, meadow, abstract, lagoon
    // Wallpapers — dark
    case pebbles, waves, nightLake, concrete, city, gold, ember, ice
    // Wallpapers — shared
    case classic
    // Solid colors — light (pastel)
    case pastelBlue, pastelPink, pastelGreen, pastelSand
    // Solid colors — dark
    case midnight, charcoal, forest, plum

    var id: Self { self }

    enum Style {
        case image(String)
        case color(Color)
    }

    /// What to render: an asset catalog image or a solid color.
    var style: Style {
        switch self {
        case .flowers: .image("WallpaperFlowers")
        case .desert: .image("WallpaperDesert")
        case .meadow: .image("WallpaperMeadow")
        case .abstract: .image("WallpaperAbstract")
        case .lagoon: .image("WallpaperLagoon")
        case .pebbles: .image("WallpaperPebbles")
        case .waves: .image("WallpaperWaves")
        case .nightLake: .image("WallpaperNightLake")
        case .concrete: .image("WallpaperConcrete")
        case .city: .image("WallpaperCity")
        case .gold: .image("WallpaperGold")
        case .ember: .image("WallpaperEmber")
        case .ice: .image("WallpaperIce")
        case .classic: .image("AppBackground")
        case .pastelBlue: .color(Color(red: 0.85, green: 0.90, blue: 0.96))
        case .pastelPink: .color(Color(red: 0.97, green: 0.87, blue: 0.90))
        case .pastelGreen: .color(Color(red: 0.87, green: 0.94, blue: 0.87))
        case .pastelSand: .color(Color(red: 0.96, green: 0.93, blue: 0.86))
        case .midnight: .color(Color(red: 0.08, green: 0.10, blue: 0.16))
        case .charcoal: .color(Color(red: 0.11, green: 0.11, blue: 0.12))
        case .forest: .color(Color(red: 0.06, green: 0.13, blue: 0.11))
        case .plum: .color(Color(red: 0.13, green: 0.09, blue: 0.16))
        }
    }

    /// Small preview used by the background picker grid. Image options have a
    /// pre-generated 480px "<name>Thumb" asset to avoid decoding full wallpapers.
    var previewStyle: Style {
        switch style {
        case .image(let name): .image(name + "Thumb")
        case .color: style
        }
    }

    var localizedString: String {
        switch self {
        case .flowers: "wallpaper_flowers".localized()
        case .desert: "wallpaper_desert".localized()
        case .meadow: "wallpaper_meadow".localized()
        case .abstract: "wallpaper_abstract".localized()
        case .lagoon: "wallpaper_lagoon".localized()
        case .pebbles: "wallpaper_pebbles".localized()
        case .waves: "wallpaper_waves".localized()
        case .nightLake: "wallpaper_night_lake".localized()
        case .concrete: "wallpaper_concrete".localized()
        case .city: "wallpaper_city".localized()
        case .gold: "wallpaper_gold".localized()
        case .ember: "wallpaper_ember".localized()
        case .ice: "wallpaper_ice".localized()
        case .classic: "wallpaper_classic".localized()
        case .pastelBlue: "color_pastel_blue".localized()
        case .pastelPink: "color_pastel_pink".localized()
        case .pastelGreen: "color_pastel_green".localized()
        case .pastelSand: "color_pastel_sand".localized()
        case .midnight: "color_midnight".localized()
        case .charcoal: "color_charcoal".localized()
        case .forest: "color_forest".localized()
        case .plum: "color_plum".localized()
        }
    }

    // Options offered per appearance mode in Settings.
    static let lightWallpapers: [BackgroundOption] = [.flowers, .desert, .meadow, .abstract, .lagoon, .classic]
    static let darkWallpapers: [BackgroundOption] = [.pebbles, .waves, .nightLake, .concrete, .city, .gold, .ember, .ice, .classic]
    static let lightColors: [BackgroundOption] = [.pastelBlue, .pastelPink, .pastelGreen, .pastelSand]
    static let darkColors: [BackgroundOption] = [.midnight, .charcoal, .forest, .plum]
}

class SettingsManager {
    static let shared = SettingsManager()
    
    private var defaults: UserDefaults {
        UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk") ?? .standard
    }
    
    // Keys voor UserDefaults
    private let tokenKey = "zammad_api_token"
    private let lockKey = "is_biometric_lock_enabled"
    private let themeKey = "color_scheme_option"
    private let lightBackgroundKey = "background_light_option"
    private let darkBackgroundKey = "background_dark_option"
    private let serverURLKey = "zammad_server_url"
    private let adsRemovedKey = "are_ads_removed"
    
    private let realtimeNotificationsEnabledKey = "realtime_notifications_enabled"
    private let proxyUserIDKey = "proxy_user_id_key"
    private let deviceTokenKey = "apn_device_token"
    private let lastFetchDateKey = "background_last_fetch_date"

    // MARK: - API & Server Settings
    // The API token lives in the Keychain. Plaintext copies written by older
    // versions to UserDefaults are migrated and scrubbed on first read.
    func save(token: String) {
        if token.isEmpty {
            KeychainHelper.delete(forKey: tokenKey)
        } else {
            KeychainHelper.save(token, forKey: tokenKey)
        }
    }

    func loadToken() -> String? {
        if let token = KeychainHelper.load(forKey: tokenKey), !token.isEmpty {
            return token
        }
        // One-time migration from pre-Keychain versions.
        if let legacy = defaults.string(forKey: tokenKey), !legacy.isEmpty {
            KeychainHelper.save(legacy, forKey: tokenKey)
            defaults.removeObject(forKey: tokenKey)
            UserDefaults.standard.removeObject(forKey: tokenKey)
            return legacy
        }
        return nil
    }
    
    func save(serverURL: String) { defaults.set(serverURL, forKey: serverURLKey) }
    func loadServerURL() -> String { defaults.string(forKey: serverURLKey) ?? "" }
    
    // MARK: - Security & Appearance
    func save(isLockEnabled: Bool) { defaults.set(isLockEnabled, forKey: lockKey) }
    func isLockEnabled() -> Bool { defaults.bool(forKey: lockKey) }
    
    func save(theme: ColorSchemeOption) { defaults.set(theme.rawValue, forKey: themeKey) }
    func loadTheme() -> ColorSchemeOption {
        let savedValue = defaults.string(forKey: themeKey) ?? ""
        return ColorSchemeOption(rawValue: savedValue) ?? .system
    }

    func save(lightBackground: BackgroundOption) { defaults.set(lightBackground.rawValue, forKey: lightBackgroundKey) }
    func loadLightBackground() -> BackgroundOption {
        BackgroundOption(rawValue: defaults.string(forKey: lightBackgroundKey) ?? "") ?? .flowers
    }

    func save(darkBackground: BackgroundOption) { defaults.set(darkBackground.rawValue, forKey: darkBackgroundKey) }
    func loadDarkBackground() -> BackgroundOption {
        BackgroundOption(rawValue: defaults.string(forKey: darkBackgroundKey) ?? "") ?? .pebbles
    }

    // MARK: - In-App Purchases
    func save(areAdsRemoved: Bool) { defaults.set(areAdsRemoved, forKey: adsRemovedKey) }
    func areAdsRemoved() -> Bool { defaults.bool(forKey: adsRemovedKey) }

    /// Premium covers ad removal, real-time notifications and the app icon
    /// badge. Backed by the legacy ads-removed flag so existing subscribers
    /// keep their entitlement.
    func isPremium() -> Bool { areAdsRemoved() }
    
    // MARK: - Notification Settings
    // AANGEPAST: Deze functie slaat nu ALLEEN de voorkeur op.
    // De logica voor aan/afmelden zit in je NotificationSetupManager en de UI Toggle.
    func save(areRealtimeNotificationsEnabled: Bool) {
        defaults.set(areRealtimeNotificationsEnabled, forKey: realtimeNotificationsEnabledKey)
    }
    func areRealtimeNotificationsEnabled() -> Bool { defaults.bool(forKey: realtimeNotificationsEnabledKey) }
    
    // Proxy & Token Management (Nodig voor NotificationProxyService)
    func save(proxyUserID: String) { defaults.set(proxyUserID, forKey: proxyUserIDKey) }
    func getProxyUserID() -> String? { defaults.string(forKey: proxyUserIDKey) }
    
    func save(deviceToken: String) { defaults.set(deviceToken, forKey: deviceTokenKey) }
    func loadDeviceToken() -> String? { defaults.string(forKey: deviceTokenKey) }

    // Hulpfunctie voor debugging
    func getWebhookURL() -> String? {
        guard let userID = getProxyUserID() else { return nil }
        return "https://zammadproxy.world-ict.nl/webhook/\(userID)"
    }
    
    // MARK: - Background Task Management
    func save(lastFetchDate: Date) { defaults.set(lastFetchDate, forKey: lastFetchDateKey) }
    func loadLastFetchDate() -> Date { defaults.object(forKey: lastFetchDateKey) as? Date ?? .distantPast }
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
