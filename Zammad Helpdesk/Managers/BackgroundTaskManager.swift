import Foundation
import BackgroundTasks
import UserNotifications

// A simplified, standalone NotificationManager for background tasks.
class BackgroundNotificationManager {
    func sendLocalNotification(title: String, body: String, userInfo: [AnyHashable: Any]? = nil, badge: Int? = nil) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        if let userInfo = userInfo {
            content.userInfo = userInfo
        }
        
        if let badgeNumber = badge {
            content.badge = NSNumber(value: badgeNumber)
        }
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error sending local notification: \(error.localizedDescription)")
            } else {
                print("Successfully sent local notification.")
            }
        }
    }
}


class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    private let backgroundTaskIdentifier = "com.zammad.apprefresh"
    private let notificationManager = BackgroundNotificationManager()

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundTaskIdentifier, using: nil) { task in
            if let refreshTask = task as? BGAppRefreshTask {
                self.handleAppRefresh(task: refreshTask)
            }
        }
        print("Background task registered.")
    }

    func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // Fetch no more than every 15 minutes.
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("App refresh scheduled.")
        } catch {
            print("Could not schedule app refresh: \(error)")
        }
    }

    private func handleAppRefresh(task: BGAppRefreshTask) {
        scheduleAppRefresh()

        let operationQueue = OperationQueue()
        operationQueue.maxConcurrentOperationCount = 1

        let operation = BlockOperation {
            Task {
                await self.performBackgroundFetch(task: task)
            }
        }
        
        task.expirationHandler = {
            operation.cancel()
            print("Background task expired.")
        }

        operationQueue.addOperation(operation)
    }

    private func performBackgroundFetch(task: BGAppRefreshTask) async {
        let lastFetchDate = SettingsManager.shared.loadLastFetchDate()
        print("Background task: Last fetch date was \(lastFetchDate.ISO8601Format())")

        do {
            // Fetch all open tickets to check for updates.
            let openStateIDs = try await ZammadAPIService.shared.fetchTicketStates()
                .filter { !["closed", "gesloten"].contains($0.name.lowercased()) }
                .map { String($0.id) }

            guard !openStateIDs.isEmpty else {
                task.setTaskCompleted(success: true)
                return
            }

            let openStatesQuery = "state_id:(\(openStateIDs.joined(separator: " OR ")))"
            let tickets = try await ZammadAPIService.shared.searchTickets(query: openStatesQuery)

            let newTickets = tickets.filter { ticket in
                return ticket.created_at.compare(lastFetchDate) == .orderedDescending
            }

            print("Background task: Found \(newTickets.count) new tickets.")

            if !newTickets.isEmpty {
                let title = String(format: "new_tickets_notification_title".localized(), newTickets.count)
                let body = newTickets.map { $0.title }.joined(separator: "\n")
                
                let firstTicketID = newTickets.sorted(by: { $0.created_at < $1.created_at }).first?.id ?? 0

                notificationManager.sendLocalNotification(
                    title: title,
                    body: body,
                    userInfo: ["ticketID": firstTicketID],
                    badge: newTickets.count
                )
                
                if let latestDate = newTickets.map({ $0.created_at }).max() {
                    SettingsManager.shared.save(lastFetchDate: latestDate)
                    print("Background task: Updated last fetch date to \(latestDate.ISO8601Format())")
                }
            }

            task.setTaskCompleted(success: true)
            print("Background task finished successfully.")

        } catch {
            print("Background task failed: \(error.localizedDescription)")
            task.setTaskCompleted(success: false)
        }
    }
}

