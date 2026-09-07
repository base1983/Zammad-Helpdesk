import SwiftUI
import UserNotifications
import BackgroundTasks
import GoogleMobileAds
import WatchConnectivity

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Lives for the whole app session: checks premium entitlements at launch
    // (including the automatic TestFlight grant) and keeps the StoreKit
    // transaction listener running.
    @MainActor private(set) lazy var storeManager = StoreManager()
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        migrateUserDefaultsToAppGroupIfNeeded()
        MobileAds.shared.start(completionHandler: { _ in })
        BackgroundTaskManager.shared.registerBackgroundTask()
        Task { @MainActor in _ = self.storeManager } // kick off the launch entitlement check
        Task.detached(priority: .utility) {
            // Prune on-device chat history to the configured retention window.
            ChatHistoryStore.shared.pruneAll()
        }
        
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("Fout bij aanvragen notificatierechten: \(error)")
            }
        }
        
        application.registerForRemoteNotifications()
        
        Task { @MainActor in
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first?.backgroundColor = .clear
        }
        
        // Initialize Watch Connectivity and send credentials
        _ = WatchConnectivityManager.shared
        
        // Real-time notifications became a premium feature: unsubscribe users
        // who registered while it was free and no longer have premium.
        if !SettingsManager.shared.isPremium() && SettingsManager.shared.areRealtimeNotificationsEnabled() {
            SettingsManager.shared.save(areRealtimeNotificationsEnabled: false)
            Task {
                await NotificationProxyService.shared.updateRegistration(isSubscribing: false)
            }
        }
        
        return true
    }
    
    // MARK: - DeepLink & Notification Handling
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        print("DEBUG: Notificatie aangeklikt. Payload: \(userInfo)")
        DeepLinkManager.shared.handleNotification(userInfo)
        completionHandler()
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Keep the chat unread badge current when a chat push arrives in the foreground.
        let userInfo = notification.request.content.userInfo
        if userInfo["chat_from_user_id"] != nil || userInfo["chat_group_id"] != nil {
            Task { @MainActor in await ChatService.shared.refreshUnreadCount() }
        }
        completionHandler([.banner, .sound])
    }
    
    // MARK: - APNS Device Token
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("DEBUG: APNS Device Token ontvangen: \(token)")
        NotificationSetupManager.shared.handleDeviceToken(deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("DEBUG: Mislukt om te registreren: \(error)")
        NotificationSetupManager.shared.handleRegistrationError(error)
    }
    
    // MARK: - App Group Migration
    
    private func migrateUserDefaultsToAppGroupIfNeeded() {
        let migrationKey = "app_group_migration_v1_done"
        guard let group = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk") else { return }
        guard !group.bool(forKey: migrationKey) else { return }
        
        let standard = UserDefaults.standard
        let keysToMigrate = [
            "zammad_api_token",
            "zammad_server_url",
            "is_biometric_lock_enabled",
            "color_scheme_option",
            "are_ads_removed",
            "realtime_notifications_enabled",
            "proxy_user_id_key",
            "apn_device_token",
            "background_last_fetch_date",
            "is_setup_complete"
        ]
        
        for key in keysToMigrate {
            if let value = standard.object(forKey: key), group.object(forKey: key) == nil {
                group.set(value, forKey: key)
            }
        }
        
        group.set(true, forKey: migrationKey)
        print("Migrated UserDefaults to App Group suite")
    }
}

@main
struct Zammad_HelpdeskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var deepLinkManager = DeepLinkManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    DeepLinkManager.shared.handleUrl(url)
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundTaskManager.shared.scheduleAppRefresh()
            }
        }
    }
}
