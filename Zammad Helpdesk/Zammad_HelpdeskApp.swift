import SwiftUI
import GoogleMobileAds
import BackgroundTasks
import UserNotifications

// Globale Notificatie Naam voor de deep link.
extension Notification.Name {
    static let handleDeepLink = Notification.Name("handleDeepLink")
}

// AppDelegate voor het afhandelen van notificaties.
class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        // --- 1. ASK FOR PERMISSION ON LAUNCH (THIS WAS MISSING) ---
        requestNotificationAuthorization(application: application)
        return true
    }
    
    func requestNotificationAuthorization(application: UIApplication) {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        // Request authorization to display alerts, play sounds, and update the badge
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            if let error = error {
                print("Error requesting notification authorization: \(error)")
                return
            }
            
            guard granted else {
                print("Notification permission not granted.")
                return
            }
            
            print("Notification permission granted. Registering for remote notifications...")
            DispatchQueue.main.async {
                // After permission is granted, register for remote notifications
                application.registerForRemoteNotifications()
            }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        print("Device Token: \(token)")
        SettingsManager.shared.save(deviceToken: token)
        
        // If the user has real-time notifications enabled, send the token to your server
        if SettingsManager.shared.areRealtimeNotificationsEnabled() {
            Task {
                await NotificationProxyService.shared.updateRegistration(isSubscribing: true)
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // Handle notification taps
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        if let ticketID = userInfo["ticketID"] as? Int {
            print("Deep link to ticket ID: \(ticketID)")
            NotificationCenter.default.post(name: .handleDeepLink, object: nil, userInfo: ["ticketID": ticketID])
        }
        
        completionHandler()
    }
    
    // Handle notifications that arrive while the app is in the foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
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
                UIApplication.shared.applicationIconBadgeNumber = 0
            }
        }
    }
}
