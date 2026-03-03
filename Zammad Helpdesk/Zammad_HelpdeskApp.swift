import SwiftUI
import UserNotifications
import BackgroundTasks
import GoogleMobileAds
import WatchConnectivity

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    let backgroundTaskID = "com.worldict.helpdesk.refresh"
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        migrateUserDefaultsToAppGroupIfNeeded()
        MobileAds.shared.start(completionHandler: { _ in })
        BackgroundTaskManager.shared.registerBackgroundTask()
        
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
        
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        // Initialize Watch Connectivity and send credentials
        _ = WatchConnectivityManager.shared
        
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
    
    // MARK: - Background Task Handling
    
    func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        
        Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            task.setTaskCompleted(success: true)
        }
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Kon achtergrondtaak niet inplannen: \(error)")
        }
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
                appDelegate.scheduleAppRefresh()
            }
        }
    }
}
