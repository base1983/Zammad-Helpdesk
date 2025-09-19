import SwiftUI
import GoogleMobileAds
import BackgroundTasks
import UserNotifications

// AppDelegate for handling notifications.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        NotificationManager.shared.requestAuthorization()
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        SettingsManager.shared.save(deviceToken: token)
        
        if SettingsManager.shared.areRealtimeNotificationsEnabled() {
            Task {
                await NotificationProxyService.shared.updateRegistration(isSubscribing: true)
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let ticketID = userInfo["ticketID"] as? Int {
            print("Deep link to ticket ID: \(ticketID) captured. Storing in DeepLinkManager.")
            // Set the pending ID on the shared manager.
            DeepLinkManager.shared.pendingTicketID = ticketID
        }
        
        completionHandler()
    }
}

@main
struct ZammadHelpdeskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @Environment(\.scenePhase) var scenePhase
    
    init() {
        MobileAds.shared.start(completionHandler: { _ in })
        BackgroundTaskManager.shared.registerBackgroundTask()
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                BackgroundTaskManager.shared.scheduleAppRefresh()
            }
            if newPhase == .active {
                // The modern, recommended way to clear the badge count.
                UNUserNotificationCenter.current().setBadgeCount(0) { error in
                    if let error = error {
                        // Optionally handle or log the error
                        print("Error clearing app icon badge: \(error.localizedDescription)")
                    }
                }
            }
        }
    }
}

