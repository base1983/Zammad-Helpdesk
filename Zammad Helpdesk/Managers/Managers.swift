import Foundation
import SwiftUI
import Combine
import UserNotifications
import LocalAuthentication

enum ColorSchemeOption: String, CaseIterable, Identifiable {
    case system = "Systeem", light = "Licht", dark = "Donker"
    var id: Self { self }
}

class SettingsManager {
    static let shared = SettingsManager()
    private let tokenKey = "zammad_api_token"
    private let lockKey = "is_biometric_lock_enabled"
    private let themeKey = "color_scheme_option"
    private let serverURLKey = "zammad_server_url"
    private let adsRemovedKey = "are_ads_removed"
    
    private let notificationsEnabledKey = "notifications_enabled"
    private let newTicketNotificationsKey = "new_ticket_notifications_enabled"
    private let assignmentNotificationsKey = "assignment_notifications_enabled"
    private let replyNotificationsKey = "reply_notifications_enabled"
    private let realtimeNotificationsEnabledKey = "realtime_notifications_enabled"
    private let proxyUserIDKey = "proxy_user_id_key"
    private let deviceTokenKey = "apns_device_token"
    
    private init() {}
    
    func save(token: String) { UserDefaults.standard.set(token, forKey: tokenKey) }
    func loadToken() -> String? { UserDefaults.standard.string(forKey: tokenKey) }
    func save(serverURL: String) {
        var urlToSave = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if !urlToSave.hasSuffix("/") { urlToSave += "/" }
        UserDefaults.standard.set(urlToSave, forKey: serverURLKey)
    }
    func loadServerURL() -> String { UserDefaults.standard.string(forKey: serverURLKey) ?? "" }
    
    func save(isLockEnabled: Bool) { UserDefaults.standard.set(isLockEnabled, forKey: lockKey) }
    func isLockEnabled() -> Bool { UserDefaults.standard.bool(forKey: lockKey) }
    func save(theme: ColorSchemeOption) { UserDefaults.standard.set(theme.rawValue, forKey: themeKey) }
    func loadTheme() -> ColorSchemeOption {
        return ColorSchemeOption(rawValue: UserDefaults.standard.string(forKey: themeKey) ?? "") ?? .system
    }
    
    func save(areAdsRemoved: Bool) { UserDefaults.standard.set(areAdsRemoved, forKey: adsRemovedKey) }
    func areAdsRemoved() -> Bool { UserDefaults.standard.bool(forKey: adsRemovedKey) }
    
    func save(notificationsEnabled: Bool) { UserDefaults.standard.set(notificationsEnabled, forKey: notificationsEnabledKey) }
    func areNotificationsEnabled() -> Bool { UserDefaults.standard.bool(forKey: notificationsEnabledKey) }
    func save(newTicketNotificationsEnabled: Bool) { UserDefaults.standard.set(newTicketNotificationsEnabled, forKey: newTicketNotificationsKey) }
    func areNewTicketNotificationsEnabled() -> Bool { UserDefaults.standard.bool(forKey: newTicketNotificationsKey) }
    func save(assignmentNotificationsEnabled: Bool) { UserDefaults.standard.set(assignmentNotificationsEnabled, forKey: assignmentNotificationsKey) }
    func areAssignmentNotificationsEnabled() -> Bool { UserDefaults.standard.bool(forKey: assignmentNotificationsKey) }
    func save(replyNotificationsEnabled: Bool) { UserDefaults.standard.set(replyNotificationsEnabled, forKey: replyNotificationsKey) }
    func areReplyNotificationsEnabled() -> Bool { UserDefaults.standard.bool(forKey: replyNotificationsKey) }
    
    func save(realtimeNotificationsEnabled: Bool) { UserDefaults.standard.set(realtimeNotificationsEnabled, forKey: realtimeNotificationsEnabledKey) }
    func areRealtimeNotificationsEnabled() -> Bool { UserDefaults.standard.bool(forKey: realtimeNotificationsEnabledKey) }
    func getProxyUserID() -> String {
        if let userID = UserDefaults.standard.string(forKey: proxyUserIDKey) {
            return userID
        } else {
            let newUserID = UUID().uuidString
            UserDefaults.standard.set(newUserID, forKey: proxyUserIDKey)
            return newUserID
        }
    }
    func save(deviceToken: String) { UserDefaults.standard.set(deviceToken, forKey: deviceTokenKey) }
    func loadDeviceToken() -> String? { UserDefaults.standard.string(forKey: deviceTokenKey) }
}

class NotificationManager {
    static let shared = NotificationManager()
    private init() {}

    func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if granted {
                DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
            } else if let error = error { print("Notification permission error: \(error.localizedDescription)") }
        }
    }
    
    func sendLocalNotification(title: String, body: String, userInfo: [AnyHashable: Any]? = nil, badge: Int? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        if let userInfo = userInfo {
            content.userInfo = userInfo
        }
        if let badge = badge {
            content.badge = NSNumber(value: badge)
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

@MainActor
class AuthenticationManager: ObservableObject {
    @Published var isUnlocked = false
    
    func authenticate() {
        guard SettingsManager.shared.isLockEnabled() else { isUnlocked = true; return }
        
        let context = LAContext()
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) {
            context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "unlock_reason".localized()) { success, _ in
                DispatchQueue.main.async { self.isUnlocked = success }
            }
        } else {
            isUnlocked = true
        }
    }
    
    func lock() {
        if SettingsManager.shared.isLockEnabled() { isUnlocked = false }
    }
}

