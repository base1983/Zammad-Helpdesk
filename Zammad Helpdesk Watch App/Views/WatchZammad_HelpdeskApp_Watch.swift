//
//  Zammad_HelpdeskApp_Watch.swift
//  Zammad Helpdesk Watch App
//

import SwiftUI
import WatchConnectivity
import Combine

// MARK: - Watch Session Manager

class WatchSessionManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = WatchSessionManager()
    
    @Published var credentialsReceived = false
    
    private override init() {
        super.init()
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    func requestCredentials() {
        guard WCSession.default.isReachable else {
            print("iPhone not reachable, checking applicationContext")
            let context = WCSession.default.receivedApplicationContext
            if !context.isEmpty {
                storeCredentials(from: context)
            }
            return
        }
        
        WCSession.default.sendMessage(["request": "credentials"], replyHandler: { [weak self] reply in
            self?.storeCredentials(from: reply)
        }, errorHandler: { error in
            print("Failed to request credentials from iPhone: \(error)")
        })
    }
    
    private func storeCredentials(from data: [String: Any]) {
        guard let token = data["zammad_api_token"] as? String, !token.isEmpty,
              let serverURL = data["zammad_server_url"] as? String, !serverURL.isEmpty else {
            print("No valid credentials in received data")
            return
        }
        
        SettingsManager.shared.save(token: token)
        SettingsManager.shared.save(serverURL: serverURL)
        
        DispatchQueue.main.async {
            self.credentialsReceived = true
        }
        print("Stored credentials from iPhone — token: \(token.prefix(4))..., url: \(serverURL)")
    }
    
    // MARK: - WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated {
            print("WCSession activated on Watch")
            let context = session.receivedApplicationContext
            if !context.isEmpty {
                storeCredentials(from: context)
            } else {
                requestCredentials()
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("Watch received applicationContext from iPhone")
        storeCredentials(from: applicationContext)
    }
}

// MARK: - Watch App

@main
struct Zammad_HelpdeskApp_Watch: App {
    @StateObject private var sessionManager = WatchSessionManager.shared
    
    var body: some Scene {
        WindowGroup {
            WatchTicketListView()
                .environmentObject(sessionManager)
        }
    }
}
