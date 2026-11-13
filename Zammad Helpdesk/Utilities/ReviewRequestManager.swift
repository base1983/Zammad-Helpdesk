import Foundation

/// Decides *when* the app may ask for an App Store rating. StoreKit decides
/// whether the sheet actually appears (three times a year per device at
/// most, never twice for one version), so the job here is only to pick a
/// good moment: when the user leaves the tenth ticket they have opened, once
/// per app version, and never right at launch or straight after an ad.
///
/// Call `recordTicketOpened()` once per ticket the user opens. Call
/// `consumeRequestIfEarned()` when they leave a ticket, from the screen that
/// is still on screen then; it returns true once per version when the count
/// is reached and resets it.
@MainActor
final class ReviewRequestManager {
    static let shared = ReviewRequestManager()

    /// Tickets to open before the first request in a version.
    private static let ticketsRequired = 10

    private let defaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk") ?? .standard
    private let openedCountKey = "review_tickets_opened_count"
    private let lastPromptedVersionKey = "review_last_prompted_version"

    private init() {}

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Notes one more ticket the user has opened.
    func recordTicketOpened() {
        let count = defaults.integer(forKey: openedCountKey) + 1
        defaults.set(count, forKey: openedCountKey)
        print("DEBUG: [Review] Tickets geopend: \(count)/\(Self.ticketsRequired)")
    }

    /// True when the user has opened enough tickets in this version to be
    /// asked, and has not been asked for this version yet. Consumes the
    /// opportunity so the next ticket does not ask again.
    ///
    /// Debug builds skip the once-per-version rule: StoreKit always shows
    /// the sheet in development, and the rule would otherwise block every
    /// test after the first.
    func consumeRequestIfEarned() -> Bool {
        guard defaults.integer(forKey: openedCountKey) >= Self.ticketsRequired else { return false }
        #if !DEBUG
        guard defaults.string(forKey: lastPromptedVersionKey) != currentVersion else { return false }
        #endif
        defaults.set(currentVersion, forKey: lastPromptedVersionKey)
        defaults.set(0, forKey: openedCountKey)
        print("DEBUG: [Review] Beoordeling aanvragen voor versie \(currentVersion)")
        return true
    }
}
