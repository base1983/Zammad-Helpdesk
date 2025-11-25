import Foundation

struct Ticket: Identifiable, Codable, Hashable {
    var id: Int
    var group_id: Int
    var priority_id: Int
    var state_id: Int
    var organization_id: Int?
    var number: String
    var title: String
    var owner_id: Int
    var customer_id: Int
    var note: String?
    var first_response_at: Date?
    var first_response_escalation_at: Date?
    var first_response_in_min: Int?
    var first_response_diff_in_min: Int?
    var close_at: Date?
    var close_escalation_at: Date?
    var close_in_min: Int?
    var close_diff_in_min: Int?
    var update_escalation_at: Date?
    var update_in_min: Int?
    var update_diff_in_min: Int?
    var last_contact_at: Date?
    var last_contact_agent_at: Date?
    var last_contact_customer_at: Date?
    var last_owner_update_at: Date?
    var create_article_type_id: Int
    var create_article_sender_id: Int
    var article_count: Int
    var escalation_at: Date?
    var pending_time: Date?
    var type: String?
    var time_unit: String?
    var preferences: Preferences
    var updated_by_id: Int
    var created_by_id: Int
    var created_at: Date
    var updated_at: Date

    struct Preferences: Codable, Hashable {
        var channel_id: Int?
    }
}

struct TicketState: Identifiable, Codable, Hashable {
    let id: Int
    let state_type_id: Int
    let name: String
    let next_state_id: Int?
    let ignore_escalation: Bool
    let default_create: Bool
    let default_follow_up: Bool
    let note: String?
    let active: Bool
    let updated_by_id: Int
    let created_by_id: Int
    let created_at: Date
    let updated_at: Date
}

struct TicketPriority: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let note: String?
    let default_create: Bool
    let ui_icon: String?
    let ui_color: String?
    let active: Bool
    let updated_by_id: Int
    let created_by_id: Int
    let created_at: Date
    let updated_at: Date
}

struct TicketArticle: Identifiable, Codable, Hashable {
    let id: Int
    let ticket_id: Int
    let type_id: Int
    let sender_id: Int
    let from: String
    let to: String?
    let cc: String?
    let subject: String?
    let reply_to: String?
    let message_id: String?
    let message_id_md5: String?
    let in_reply_to: String?
    let content_type: String
    let references: String?
    let body: String
    let internal_note: Bool?
    let created_by_id: Int
    let created_at: Date
    let updated_at: Date
    let updated_by_id: Int
}

struct User: Identifiable, Codable, Hashable {
    let id: Int
    let organization_id: Int?
    let login: String
    let firstname: String
    let lastname: String
    let email: String
    let web: String?
    let phone: String?
    let fax: String?
    let mobile: String?
    let department: String?
    let street: String?
    let zip: String?
    let city: String?
    let country: String?
    let address: String?
    let vip: Bool
    let verified: Bool
    let active: Bool
    let note: String?
    let last_login: Date?
    let source: String?
    let login_failed: Int
    let out_of_office: Bool
    let out_of_office_start_at: Date?
    let out_of_office_end_at: Date?
    let out_of_office_replacement_id: Int?
    let preferences: UserPreferences
    let role_ids: [Int]?
    let organization_ids: [Int]?
    let authorization_ids: [Int]?
    let group_ids: [Int: [String]]?
    let updated_by_id: Int
    let created_by_id: Int
    let created_at: Date
    let updated_at: Date
    
    var fullname: String {
        return "\(firstname) \(lastname)"
    }
}

struct UserPreferences: Codable, Hashable {
    // Define user preferences properties here
}

struct Role: Identifiable, Codable, Hashable {
    let id: Int
    let name: String
    let default_at_signup: Bool
    let active: Bool
}

struct TicketUpdatePayload: Codable {
    var owner_id: Int
    var state_id: Int
    var priority_id: Int
    var pending_time: String?
}

struct ArticleCreationPayload: Codable {
    var ticket_id: Int
    var body: String
    var internal_note: Bool
    var to: String
    var subject: String
}

