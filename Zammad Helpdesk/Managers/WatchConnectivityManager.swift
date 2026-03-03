//
//  WatchConnectivityManager.swift
//  Zammad Helpdesk
//
//  Sends credentials from iPhone to Apple Watch via WCSession.
//  iOS target only.
//

import Foundation
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchConnectivityManager()
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - Send Credentials to Watch
    
    func sendCredentialsToWatch() {
        guard WCSession.default.activationState == .activated else {
            print("WCSession not activated, can't send credentials")
            return
        }
        
        let token = SettingsManager.shared.loadToken() ?? ""
        let serverURL = SettingsManager.shared.loadServerURL()
        
        guard !token.isEmpty, !serverURL.isEmpty else {
            print("No credentials to send to Watch")
            return
        }
        
        let context: [String: Any] = [
            "zammad_api_token": token,
            "zammad_server_url": serverURL
        ]
        
        // Use updateApplicationContext — it always delivers the latest data,
        // even if the Watch app isn't running. The system stores the latest
        // context and delivers it when the Watch app wakes up.
        do {
            try WCSession.default.updateApplicationContext(context)
            print("Sent credentials to Watch via applicationContext")
        } catch {
            print("Failed to send credentials to Watch: \(error)")
        }
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            print("WCSession activated on iOS")
            // Send credentials when session activates (e.g., on app launch)
            DispatchQueue.main.async {
                self.sendCredentialsToWatch()
            }
        }
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {}
    
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after deactivation (required for switching watches)
        WCSession.default.activate()
    }
    
    // Handle credential requests from the Watch
    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        if message["request"] as? String == "credentials" {
            let token = SettingsManager.shared.loadToken() ?? ""
            let serverURL = SettingsManager.shared.loadServerURL()
            replyHandler([
                "zammad_api_token": token,
                "zammad_server_url": serverURL
            ])
            print("Replied to Watch credential request")
        }
    }
}
