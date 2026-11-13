import SwiftUI

/// SLA state of a ticket, derived from the escalation timestamps Zammad puts
/// on the ticket. Zammad matches the SLA server-side and only exposes the
/// resulting deadlines: `escalation_at` is the nearest open deadline, and
/// the three `*_escalation_at` fields are the individual ones. Verified
/// against a live instance: a ticket without an SLA has all of them nil, a
/// ticket whose first response is overdue has `escalation_at` equal to
/// `first_response_escalation_at` and the other two nil.
enum SLAStatus: Equatable {
    /// Deadline passed; the ticket is escalated.
    case escalated(overdue: TimeInterval)
    /// Deadline within the hour.
    case dueSoon(remaining: TimeInterval)
    /// Deadline further away.
    case onTrack(remaining: TimeInterval)

    static let dueSoonThreshold: TimeInterval = 60 * 60

    init(deadline: Date, now: Date = Date()) {
        let remaining = deadline.timeIntervalSince(now)
        if remaining <= 0 {
            self = .escalated(overdue: -remaining)
        } else if remaining < Self.dueSoonThreshold {
            self = .dueSoon(remaining: remaining)
        } else {
            self = .onTrack(remaining: remaining)
        }
    }

    var color: Color {
        switch self {
        case .escalated: .red
        case .dueSoon: .orange
        case .onTrack: .green
        }
    }

    var symbolName: String {
        switch self {
        case .escalated: "exclamationmark.triangle.fill"
        case .dueSoon, .onTrack: "clock"
        }
    }

    /// "2h 15m left" / "3d 4h overdue", localised.
    var text: String {
        switch self {
        case .escalated(let overdue):
            String(format: "sla_time_overdue".localized(), SLAFormatter.duration(overdue))
        case .dueSoon(let remaining), .onTrack(let remaining):
            String(format: "sla_time_left".localized(), SLAFormatter.duration(remaining))
        }
    }

    /// Just the duration, for the compact badge in the ticket list.
    var shortText: String {
        switch self {
        case .escalated(let overdue): SLAFormatter.duration(overdue)
        case .dueSoon(let remaining), .onTrack(let remaining): SLAFormatter.duration(remaining)
        }
    }
}

/// One SLA target of a ticket, for the detail screen.
struct SLADeadline: Identifiable {
    enum Kind: String, CaseIterable {
        case firstResponse, update, solution

        var titleKey: String {
            switch self {
            case .firstResponse: "sla_first_response"
            case .update: "sla_update"
            case .solution: "sla_solution"
            }
        }
    }

    let kind: Kind
    /// When Zammad expects this target to be met; nil once it no longer applies.
    let deadline: Date?
    /// When the target was met, if it was.
    let completedAt: Date?

    var id: Kind { kind }

    var isMet: Bool { completedAt != nil }

    func status(now: Date = Date()) -> SLAStatus? {
        guard !isMet, let deadline else { return nil }
        return SLAStatus(deadline: deadline, now: now)
    }
}

extension Ticket {
    /// Whether an SLA applies at all; tickets without one have no deadlines.
    var hasSLA: Bool {
        escalation_at != nil || first_response_escalation_at != nil
            || update_escalation_at != nil || close_escalation_at != nil
            || first_response_at != nil && first_response_in_min != nil
    }

    /// Overall SLA state from the nearest open deadline, nil without an SLA.
    func slaStatus(now: Date = Date()) -> SLAStatus? {
        guard let escalation_at else { return nil }
        return SLAStatus(deadline: escalation_at, now: now)
    }

    /// The individual targets that have a deadline or were met, for display.
    var slaDeadlines: [SLADeadline] {
        [
            SLADeadline(kind: .firstResponse, deadline: first_response_escalation_at, completedAt: first_response_at),
            SLADeadline(kind: .update, deadline: update_escalation_at, completedAt: nil),
            SLADeadline(kind: .solution, deadline: close_escalation_at, completedAt: close_at),
        ]
        .filter { $0.deadline != nil || $0.isMet }
    }
}

enum SLAFormatter {
    private static let duration: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.day, .hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        formatter.zeroFormattingBehavior = .dropAll
        return formatter
    }()

    /// "2h 15m", "3d 4h", "45m"; never empty.
    static func duration(_ interval: TimeInterval) -> String {
        let rounded = max(60, (interval / 60).rounded() * 60)
        return duration.string(from: rounded) ?? ""
    }
}
