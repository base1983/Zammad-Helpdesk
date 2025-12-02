import Foundation

class ReadStatusManager: ObservableObject {
    static let shared = ReadStatusManager()
    @Published var lastReadTicketID: Int? = nil
    private let readTimestampsKey = "read_ticket_timestamps"
    
    private init() {}
    
    private var readTimestamps: [Int: Date] {
        get {
            guard let data = UserDefaults.standard.data(forKey: readTimestampsKey) else { return [:] }
            return (try? JSONDecoder().decode([Int: Date].self, from: data)) ?? [:]
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: readTimestampsKey)
            }
        }
    }
    
    func isUnread(ticket: Ticket, currentUser: User?) -> Bool {
        guard let lastReadDate = readTimestamps[ticket.id] else {
            // If we've never read this ticket, it's unread if it's not a new ticket created by the user.
            return ticket.created_by_id != currentUser?.id
        }
        return ticket.updated_at > lastReadDate
    }
    
    func markAsRead(ticket: Ticket) {
        var newTimestamps = readTimestamps
        newTimestamps[ticket.id] = Date() // Mark as read now
        readTimestamps = newTimestamps
        
        DispatchQueue.main.async {
            self.lastReadTicketID = ticket.id
        }
    }
    
    // NEW: Function to force a ticket to be unread
    func markAsUnread(ticket: Ticket) {
        var newTimestamps = readTimestamps
        // Setting the date to the distant past ensures the ticket's 'updated_at' is always newer than this timestamp.
        newTimestamps[ticket.id] = Date.distantPast
        readTimestamps = newTimestamps
        
        DispatchQueue.main.async {
            self.lastReadTicketID = ticket.id
        }
    }
}
