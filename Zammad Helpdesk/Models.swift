import Foundation

struct Ticket: Codable, Identifiable, Hashable {
    let id: Int
    let number: String
    let title: String
    let state_id: Int
    let priority_id: Int
    let owner_id: Int
    let customer_id: Int
    let created_at: String
    let updated_at: String
    
    var formattedCreationDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: created_at) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return "Onbekende datum"
    }
}

struct User: Codable, Identifiable, Hashable {
    let id: Int
    let firstname: String
    let lastname: String
    let email: String
    let role_ids: [Int]?
    var fullname: String { "\(firstname) \(lastname)" }
}

struct Role: Codable, Identifiable {
    let id: Int
    let name: String
}

struct TicketState: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TicketPriority: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
}

struct TicketArticle: Codable, Identifiable {
    let id: Int
    let body: String
    let from: String
    let created_at: String
    
    var formattedCreationDate: String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: created_at) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return "Onbekende datum"
    }
}

struct ZammadView: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let active: Bool
    let conditions: [String: Condition]?

    struct Condition: Codable, Hashable {
        let operator_key: String?
        let value: String?
    }
}

struct ViewExecuteResponse: Codable {
    struct Assets: Codable {
        let Ticket: [String: Ticket]
        let User: [String: User]
    }
    let assets: Assets
    let tickets: [Int]
}

struct TicketUpdatePayload: Codable {
    var state_id: Int?
    var priority_id: Int?
    var owner_id: Int?
}

struct ArticleCreationPayload: Codable {
    let ticket_id: Int
    let subject: String?
    let body: String
    let to: String?
    
    private let type: String = "email"
    private let `internal`: Bool = false
    
    enum CodingKeys: String, CodingKey {
        case ticket_id, subject, body, to, type, `internal`
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(ticket_id, forKey: .ticket_id)
        try container.encodeIfPresent(subject, forKey: .subject)
        try container.encode(body, forKey: .body)
        try container.encodeIfPresent(to, forKey: .to)
        try container.encode(type, forKey: .type)
        try container.encode(`internal`, forKey: .internal)
    }
}

