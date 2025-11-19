import SwiftUI
import UserNotifications
import BackgroundTasks
import GoogleMobileAds

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    
    // Pas dit ID aan naar wat er in je Info.plist staat onder 'Permitted background task scheduler identifiers'
    let backgroundTaskID = "com.worldict.helpdesk.refresh"
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey : Any]? = nil) -> Bool {
        
        // 1. Google Mobile Ads Initialiseren (Veilige methode)
        MobileAds.shared.start(completionHandler: { _ in })
        BackgroundTaskManager.shared.registerBackgroundTask()
        
        // 2. Notificaties instellen
        UNUserNotificationCenter.current().delegate = self
        
        let authOptions: UNAuthorizationOptions = [.alert, .badge, .sound]
        UNUserNotificationCenter.current().requestAuthorization(options: authOptions) { granted, error in
            if let error = error {
                print("Fout bij aanvragen notificatierechten: \(error)")
            }
        }
        
        application.registerForRemoteNotifications()
        
        // 3. Achtergrondtaak registreren
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskID, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
        
        return true
    }

    // --- DeepLink Logica ---
    
    // Deze functie wordt aangeroepen als je op de notificatie tikt
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        
        let userInfo = response.notification.request.content.userInfo
        print("DEBUG: Notificatie aangeklikt. Payload: \(userInfo)")
        
        // Hier sturen we de data naar de DeepLinkManager (die de tekst scant op ticket ID's)
        DeepLinkManager.shared.handleNotification(userInfo)
        
        completionHandler()
    }
    
    // Deze functie zorgt dat meldingen zichtbaar zijn, zelfs als de app open staat
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
    
    // --- Device Token (APNS) ---
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
            // 1. Token omzetten naar leesbare tekst (dit doet hij nu al)
            let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
            let token = tokenParts.joined()
            print("DEBUG: APNS Device Token ontvangen in AppDelegate: \(token)")
            
            // 2. DE ONTBREKENDE REGEL: Geef het door aan de Manager!
            // Zonder deze regel gebeurt er niets met de token.
            NotificationSetupManager.shared.handleDeviceToken(deviceToken)
        }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
            print("DEBUG: AppDelegate Mislukt om te registreren: \(error)")
            // Geef de fout ook door
            NotificationSetupManager.shared.handleRegistrationError(error)
        }
    
    // --- Achtergrondtaak Afhandeling ---
    
    func handleAppRefresh(task: BGAppRefreshTask) {
        // Plan de volgende refresh in
        scheduleAppRefresh()
        
        // Maak een nieuwe Task aan om data te verversen
        Task {
            // Hier roep je de refresh logica aan van je ViewModel of Service
            // Bijvoorbeeld: await TicketViewModel().refreshAllData()
            
            // Als voorbeeld simuleren we nu even kort werk:
            try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            
            task.setTaskCompleted(success: true)
        }
        
        // Zorg dat de taak netjes stopt als het systeem daarom vraagt (bijv. batterij bijna leeg)
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // Probeer elke 15 minuten
        
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Kon achtergrondtaak niet inplannen: \(error)")
        }
    }
}

@main
struct Zammad_HelpdeskApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    
    // Zorg dat de DeepLinkManager leeft zodra de app start
    @StateObject private var deepLinkManager = DeepLinkManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Voor als de app wordt geopend via een link in e-mail
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
