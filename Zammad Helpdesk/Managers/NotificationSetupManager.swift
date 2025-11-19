//
//  NotificationSetupManager.swift
//  Zammad Helpdesk
//
//  Created by Bas Jonkers on 18/11/2025.
//


import SwiftUI
import Combine
import UserNotifications

class NotificationSetupManager: ObservableObject {
    static let shared = NotificationSetupManager()
    
    // Status variabelen voor de UI (het tandwieltje of vinkje)
    @Published var isLoading = false
    @Published var isRegistered = false
    @Published var errorMessage: String?
    
    private init() {}
    
    // 1. Wordt aangeroepen door de Toggle in je instellingen-scherm
    func enableNotifications() {
        DispatchQueue.main.async {
            self.isLoading = true
            self.errorMessage = nil
        }
        
        // Vraag toestemming aan iOS
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if granted {
                print("DEBUG: Toestemming gekregen. Nu registreren bij APNS...")
                DispatchQueue.main.async {
                    UIApplication.shared.registerForRemoteNotifications()
                }
            } else {
                print("DEBUG: Geen toestemming voor notificaties.")
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Geen toestemming voor meldingen. Check je iOS instellingen."
                }
            }
        }
    }
    
    // 2. Wordt aangeroepen door AppDelegate zodra de token binnen is
        func handleDeviceToken(_ tokenData: Data) {
            let tokenParts = tokenData.map { data in String(format: "%02.2hhx", data) }
            let token = tokenParts.joined()
            
            print("DEBUG: APNS Token ontvangen: \(token)")
            
            // STAP A: Sla de token op
            SettingsManager.shared.save(deviceToken: token)
            
            // STAP B: Roep de proxy aan (gebruik Task.detached voor zekerheid)
            Task.detached {
                print("DEBUG: [Manager] Start taak voor proxy registratie...")
                
                // Wacht heel even om zeker te zijn dat UserDefaults klaar is met schrijven
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 sec
                
                await NotificationProxyService.shared.updateRegistration(isSubscribing: true)
                
                // STAP C: Update UI
                await MainActor.run {
                    NotificationSetupManager.shared.isLoading = false
                    NotificationSetupManager.shared.isRegistered = true
                    print("DEBUG: [Manager] Registratieproces voltooid.")
                }
            }
        }
    
    // 3. Wordt aangeroepen door AppDelegate als registratie bij Apple mislukt
    func handleRegistrationError(_ error: Error) {
        print("DEBUG: Fout bij APNS registratie: \(error)")
        DispatchQueue.main.async {
            self.isLoading = false
            self.errorMessage = "Fout bij Apple registratie: \(error.localizedDescription)"
        }
    }
}
