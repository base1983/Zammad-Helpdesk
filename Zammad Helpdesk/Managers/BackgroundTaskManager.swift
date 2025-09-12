import Foundation
import BackgroundTasks

class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private let taskIdentifier = "com.baseonline.zammadhelpdesk.refresh"
    
    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            self.handleAppRefresh(task: task as! BGAppRefreshTask)
        }
    }
    
    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("Background refresh scheduled.")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }
    
    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()
        
        guard !SettingsManager.shared.areRealtimeNotificationsEnabled() else {
            print("Real-time push notifications are enabled. Skipping background refresh.")
            task.setTaskCompleted(success: true)
            return
        }

        guard SettingsManager.shared.areNotificationsEnabled() else {
            print("Notifications are disabled by the user. Skipping background refresh.")
            task.setTaskCompleted(success: true)
            return
        }
        
        Task {
            do {
                let oldTicketData = loadPreviousTicketState()
                
                async let tickets = ZammadAPIService.shared.searchTickets(query: "*")
                async let currentUser = ZammadAPIService.shared.fetchCurrentUser()
                
                let (newTickets, user) = try await (tickets, currentUser)
                
                var notificationEvents: [(title: String, body: String, userInfo: [AnyHashable: Any]?)] = []
                
                if SettingsManager.shared.areNewTicketNotificationsEnabled() {
                    notificationEvents.append(contentsOf: checkForNewTickets(oldData: oldTicketData, newData: newTickets))
                }
                if SettingsManager.shared.areAssignmentNotificationsEnabled() {
                    notificationEvents.append(contentsOf: checkForNewAssignments(oldData: oldTicketData, newData: newTickets, userId: user.id))
                }
                if SettingsManager.shared.areReplyNotificationsEnabled() {
                    notificationEvents.append(contentsOf: checkForCustomerReplies(oldData: oldTicketData, newData: newTickets, userId: user.id))
                }
                
                sendNotifications(for: notificationEvents)
                saveCurrentTicketState(tickets: newTickets)
                task.setTaskCompleted(success: true)
                
            } catch {
                print("Background refresh failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
        
        task.expirationHandler = {
            task.setTaskCompleted(success: false)
        }
    }
    
    private let ticketsKey = "lastKnownTickets"
    
    private func saveCurrentTicketState(tickets: [Ticket]) {
        let ticketData = tickets.map { ["id": $0.id, "owner_id": $0.owner_id, "updated_at": $0.updated_at] }
        UserDefaults.standard.set(ticketData, forKey: ticketsKey)
    }
    
    private func loadPreviousTicketState() -> [[String: Any]] {
        UserDefaults.standard.array(forKey: ticketsKey) as? [[String: Any]] ?? []
    }
    
    private func checkForNewTickets(oldData: [[String: Any]], newData: [Ticket]) -> [(String, String, [AnyHashable: Any]?)] {
        let oldTicketIDs = Set(oldData.compactMap { $0["id"] as? Int })
        return newData.filter { !oldTicketIDs.contains($0.id) }.map { ticket in
            let body = String(format: "new_ticket_body".localized(), ticket.number)
            return (title: "new_ticket_singular".localized(), body: body, userInfo: ["ticketID": ticket.id])
        }
    }
    
    private func checkForNewAssignments(oldData: [[String: Any]], newData: [Ticket], userId: Int) -> [(String, String, [AnyHashable: Any]?)] {
        let oldOwnerMap: [Int: Int] = oldData.reduce(into: [:]) { dict, item in
            if let id = item["id"] as? Int, let owner = item["owner_id"] as? Int { dict[id] = owner }
        }
        return newData.filter { $0.owner_id == userId && oldOwnerMap[$0.id] != userId }.map { newTicket in
            let body = String(format: "new_assignment_body".localized(), newTicket.number)
            return (title: "new_assignment_title".localized(), body: body, userInfo: ["ticketID": newTicket.id])
        }
    }
    
    private func checkForCustomerReplies(oldData: [[String: Any]], newData: [Ticket], userId: Int) -> [(String, String, [AnyHashable: Any]?)] {
        let oldTimestampMap: [Int: String] = oldData.reduce(into: [:]) { dict, item in
            if let id = item["id"] as? Int, let timestamp = item["updated_at"] as? String { dict[id] = timestamp }
        }
        return newData.filter { ticket in
            guard ticket.owner_id == userId, let oldTimestamp = oldTimestampMap[ticket.id] else { return false }
            return ticket.updated_at > oldTimestamp
        }.map { newTicket in
            let body = String(format: "new_reply_body".localized(), newTicket.number)
            return (title: "new_reply_title".localized(), body: body, userInfo: ["ticketID": newTicket.id])
        }
    }

    private func sendNotifications(for events: [(title: String, body: String, userInfo: [AnyHashable: Any]?)]) {
        guard !events.isEmpty else { return }
        let badgeCount = events.count
        if let event = events.first, events.count == 1 {
            NotificationManager.shared.sendLocalNotification(title: event.title, body: event.body, userInfo: event.userInfo, badge: badgeCount)
        } else {
            let title = "new_tickets_title".localized()
            let body = String(format: "new_tickets_plural".localized(), events.count)
            NotificationManager.shared.sendLocalNotification(title: title, body: body, badge: badgeCount)
        }
    }
}

