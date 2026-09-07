import Foundation
import Combine

class DeepLinkManager: ObservableObject {
    static let shared = DeepLinkManager()
    
    @Published var pendingTicketID: Int?
    @Published var pendingChatPartnerID: Int?
    @Published var pendingChatGroupID: Int?
    
    private init() {}
    
    func handleUrl(_ url: URL) {
        findIdInString(url.absoluteString)
    }
    
    func handleNotification(_ userInfo: [AnyHashable: Any]) {
        // Structured keys first. Chat payloads must not reach the regex
        // fallback below: it would misread "chat_from_user_id" as a ticket id.
        if let ticketID = intValue(userInfo["ticketID"]) {
            print("DEBUG: 🎯 Ticket ID uit payload key: \(ticketID)")
            DispatchQueue.main.async { self.pendingTicketID = ticketID }
            return
        }
        if let groupID = intValue(userInfo["chat_group_id"]) {
            print("DEBUG: 🎯 Chat groep ID uit payload: \(groupID)")
            DispatchQueue.main.async { self.pendingChatGroupID = groupID }
            return
        }
        if let partnerID = intValue(userInfo["chat_from_user_id"]) {
            print("DEBUG: 🎯 Chat partner ID uit payload: \(partnerID)")
            DispatchQueue.main.async { self.pendingChatPartnerID = partnerID }
            return
        }
        
        let payloadString = "\(userInfo)"
        print("DEBUG: Payload string: \(payloadString)")
        findIdInString(payloadString)
    }
    
    private func intValue(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }
    
    private func findIdInString(_ text: String) {
        // Pattern 1: "Ticket #14478" (case-insensitive)
        let titlePattern = #"(?i)Ticket\s*#\s*(\d+)"#
        if let id = matchRegex(pattern: titlePattern, in: text) {
            print("DEBUG: 🎯 Ticket ID gevonden via titel: \(id)")
            DispatchQueue.main.async { self.pendingTicketID = id }
            return
        }
        
        // Pattern 2: "ticket_id": 14478 (JSON fields)
        let jsonPattern = #"(?:ticket_id|id)["\s:]+(\d+)"#
        if let id = matchRegex(pattern: jsonPattern, in: text) {
            print("DEBUG: 🎯 Ticket ID gevonden via JSON: \(id)")
            DispatchQueue.main.async { self.pendingTicketID = id }
            return
        }

        // Pattern 3: "zoom/14478" (URL structure)
        let zoomPattern = #"zoom[\\\/]+(\d+)"#
        if let id = matchRegex(pattern: zoomPattern, in: text) {
            print("DEBUG: 🎯 Ticket ID gevonden via zoom link: \(id)")
            DispatchQueue.main.async { self.pendingTicketID = id }
            return
        }
        
        print("DEBUG: ❌ Geen geldig ID gevonden.")
    }
    
    private func matchRegex(pattern: String, in text: String) -> Int? {
        do {
            let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
            let range = NSRange(location: 0, length: text.utf16.count)
            
            if let match = regex.firstMatch(in: text, options: [], range: range),
               let numberRange = Range(match.range(at: 1), in: text),
               let id = Int(String(text[numberRange])) {
                return id
            }
        } catch { return nil }
        return nil
    }
}
