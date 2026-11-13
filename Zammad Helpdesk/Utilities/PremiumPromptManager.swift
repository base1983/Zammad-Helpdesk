import Foundation

/// Decides when a non-Premium user gets the "Go Premium" sheet: after every
/// fifteen tickets they have read, and never more than once a week, so the
/// suggestion stays a suggestion and not a nag. Premium users never see it;
/// the caller checks that.
@MainActor
final class PremiumPromptManager {
    static let shared = PremiumPromptManager()

    /// Tickets left between two prompts.
    private static let ticketsBetweenPrompts = 15
    /// Minimum time between two prompts.
    private static let minimumInterval: TimeInterval = 7 * 24 * 60 * 60

    private let defaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk") ?? .standard
    private let ticketsLeftKey = "premium_prompt_tickets_left"
    private let lastShownKey = "premium_prompt_last_shown"

    private init() {}

    /// Call when the user leaves a ticket. Returns true when the sheet should
    /// be shown now; the counter and the timestamp are reset in that case.
    func consumePromptIfDue() -> Bool {
        let ticketsLeft = defaults.integer(forKey: ticketsLeftKey) + 1
        defaults.set(ticketsLeft, forKey: ticketsLeftKey)
        guard ticketsLeft >= Self.ticketsBetweenPrompts else { return false }

        if let lastShown = defaults.object(forKey: lastShownKey) as? Date,
           Date().timeIntervalSince(lastShown) < Self.minimumInterval {
            return false
        }

        defaults.set(0, forKey: ticketsLeftKey)
        defaults.set(Date(), forKey: lastShownKey)
        print("DEBUG: [Premium] Premium-suggestie tonen")
        return true
    }
}
