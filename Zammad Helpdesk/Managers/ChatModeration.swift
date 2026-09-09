import Foundation
import SwiftUI
import UIKit

// Moderation for the colleague chat — App Store Guideline 1.2 asks every app
// with user-generated content for a way to block abusive users and to report
// objectionable content. Blocking is purely client-side: the proxy never
// learns about it, which is fine because the point is what *this* user sees.

/// A colleague this user has blocked. Name and e-mail are kept so the list in
/// Settings stays readable after the directory no longer returns the user.
struct BlockedChatUser: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let email: String?
    let blockedAt: Date
}

/// Persistent block list, shared with the app group so the watch app and
/// widgets read the same state as the phone.
@MainActor
final class ChatBlockList: ObservableObject {
    static let shared = ChatBlockList()

    private static let key = "chat_blocked_users"
    private let defaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk") ?? .standard

    @Published private(set) var blocked: [BlockedChatUser] = []

    private init() {
        if let data = defaults.data(forKey: Self.key),
           let list = try? JSONDecoder().decode([BlockedChatUser].self, from: data) {
            blocked = list
        }
    }

    var blockedIDs: Set<Int> { Set(blocked.map(\.id)) }

    func isBlocked(_ id: Int) -> Bool { blockedIDs.contains(id) }

    func block(_ user: ChatUser) {
        block(id: user.id, name: user.name, email: user.email)
    }

    func block(id: Int, name: String, email: String?) {
        guard !isBlocked(id) else { return }
        blocked.append(BlockedChatUser(id: id, name: name, email: email, blockedAt: Date()))
        persist()
    }

    func unblock(id: Int) {
        blocked.removeAll { $0.id == id }
        persist()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(blocked) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

/// Builds the report e-mail. Reports go by mail on purpose: the relay only
/// holds ciphertext, so the reporter — who has the plaintext — is the only
/// party that can forward what was actually said.
enum ChatReporter {
    static let address = "b.jonkers@world-ict.nl"

    /// A mailto: URL for reporting a message, or nil if it cannot be built.
    static func reportURL(for message: ChatMessage, in target: ChatTarget, reporterName: String?) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: message.createdAt)
        let sender = message.fromUserName ?? String(message.fromUserId)
        let context: String
        switch target {
        case .direct(let partner): context = "Direct conversation with \(partner.name) (chat user \(partner.id))"
        case .group(let group): context = "Group \"\(group.name)\" (group \(group.id))"
        }
        var lines = [
            "I want to report the following chat message.",
            "",
            "Server:        \(SettingsManager.shared.loadServerURL())",
            "Reported by:   \(reporterName ?? "unknown")",
            "Sender:        \(sender) (chat user \(message.fromUserId))",
            "Where:         \(context)",
            "Message id:    \(message.id)",
            "Sent at:       \(stamp)",
        ]
        if message.attachmentId != nil {
            lines.append("Attachment:    \(message.attachmentName ?? "yes") (\(message.attachmentMime ?? "unknown type"))")
        }
        lines += [
            "",
            "Message text:",
            message.body,
            "",
            "Why I am reporting it:",
            "",
        ]
        return mailto(subject: "chat_report_subject".localized(), body: lines.joined(separator: "\n"))
    }

    /// A mailto: URL for reporting a colleague as such (from the contact list).
    static func reportURL(for user: ChatUser, reporterName: String?) -> URL? {
        let lines = [
            "I want to report a colleague in the chat.",
            "",
            "Server:        \(SettingsManager.shared.loadServerURL())",
            "Reported by:   \(reporterName ?? "unknown")",
            "Colleague:     \(user.name) (chat user \(user.id), \(user.email ?? "no e-mail"))",
            "",
            "Why I am reporting them:",
            "",
        ]
        return mailto(subject: "chat_report_subject".localized(), body: lines.joined(separator: "\n"))
    }

    private static func mailto(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = address
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    /// Opens the mail composer. Returns false when the device has no mail
    /// account, so the caller can show the address instead.
    @MainActor
    static func open(_ url: URL?) -> Bool {
        guard let url, UIApplication.shared.canOpenURL(url) else { return false }
        UIApplication.shared.open(url)
        return true
    }
}

// MARK: - Settings screen

/// Settings → Chat → Blocked colleagues. Swipe to unblock.
struct BlockedUsersView: View {
    @ObservedObject private var blockList = ChatBlockList.shared

    var body: some View {
        List {
            if blockList.blocked.isEmpty {
                Text("chat_blocked_none".localized())
                    .foregroundColor(.secondary)
            } else {
                ForEach(blockList.blocked) { user in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(user.name)
                        if let email = user.email {
                            Text(email).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .swipeActions {
                        Button {
                            blockList.unblock(id: user.id)
                        } label: {
                            Label("chat_unblock".localized(), systemImage: "hand.raised.slash")
                        }
                        .tint(.green)
                    }
                }
            }
            Section {
                Text(String(format: "chat_blocked_footer".localized(), ChatReporter.address))
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("chat_blocked_users".localized())
    }
}
