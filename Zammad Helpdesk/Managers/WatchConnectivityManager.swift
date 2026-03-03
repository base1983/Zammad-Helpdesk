//
//  WatchConnectivityManager.swift
//  Zammad Helpdesk
//
//  Manages communication between iOS and watchOS apps
//

import Foundation
import WatchConnectivity

class WatchConnectivityManager: NSObject, ObservableObject {
    static let shared = WatchConnectivityManager()
    
    @Published var reachable = false
    
    private override init() {
        super.init()
        
        if WCSession.isSupported() {
            WCSession.default.delegate = self
            WCSession.default.activate()
        }
    }
    
    // MARK: - Send Data to Watch
    
    func sendTicketsToWatch(_ tickets: [Ticket]) {
        guard WCSession.default.isReachable else { return }
        
        do {
            let data = try JSONEncoder().encode(tickets)
            let message = ["tickets": data]
            
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("Error sending tickets to watch: \(error)")
            }
        } catch {
            print("Error encoding tickets: \(error)")
        }
    }
    
    func sendMetadataToWatch(
        states: [TicketState],
        priorities: [TicketPriority],
        users: [User],
        roles: [Role]
    ) {
        guard WCSession.default.isReachable else { return }
        
        do {
            let encoder = JSONEncoder()
            let message: [String: Data] = [
                "states": try encoder.encode(states),
                "priorities": try encoder.encode(priorities),
                "users": try encoder.encode(users),
                "roles": try encoder.encode(roles)
            ]
            
            WCSession.default.sendMessage(message, replyHandler: nil) { error in
                print("Error sending metadata to watch: \(error)")
            }
        } catch {
            print("Error encoding metadata: \(error)")
        }
    }
    
    // MARK: - Transfer User Info (Background Transfer)
    
    func transferTicketsToWatch(_ tickets: [Ticket]) {
        do {
            let data = try JSONEncoder().encode(tickets)
            let userInfo = ["tickets": data]
            WCSession.default.transferUserInfo(userInfo)
        } catch {
            print("Error transferring tickets: \(error)")
        }
    }
    
    func transferMetadataToWatch(
        states: [TicketState],
        priorities: [TicketPriority],
        users: [User],
        roles: [Role]
    ) {
        do {
            let encoder = JSONEncoder()
            let userInfo: [String: Data] = [
                "states": try encoder.encode(states),
                "priorities": try encoder.encode(priorities),
                "users": try encoder.encode(users),
                "roles": try encoder.encode(roles)
            ]
            WCSession.default.transferUserInfo(userInfo)
        } catch {
            print("Error transferring metadata: \(error)")
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivityManager: WCSessionDelegate {
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async {
            self.reachable = session.isReachable
        }
    }
    
    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.reachable = session.isReachable
        }
    }
    
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {
        print("WCSession became inactive")
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        print("WCSession deactivated")
        WCSession.default.activate()
    }
    #endif
    
    func session(_ session: WCSession, didReceiveMessage message: [String : Any]) {
        print("Received message from counterpart: \(message.keys)")
        
        // Handle messages from the other device
        if let action = message["action"] as? String {
            switch action {
            case "refreshTickets":
                // iOS app can handle refresh request from watch
                NotificationCenter.default.post(name: .refreshTicketsFromWatch, object: nil)
            case "ticketUpdated":
                if let ticketID = message["ticketID"] as? Int {
                    NotificationCenter.default.post(
                        name: .ticketUpdatedFromWatch,
                        object: nil,
                        userInfo: ["ticketID": ticketID]
                    )
                }
            default:
                break
            }
        }
    }
    
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        print("Received user info from counterpart")
        // Handle background transfers
    }
}

// MARK: - Notification Names

extension Notification.Name {
    static let refreshTicketsFromWatch = Notification.Name("refreshTicketsFromWatch")
    static let ticketUpdatedFromWatch = Notification.Name("ticketUpdatedFromWatch")
}
