import Foundation

extension Notification.Name {
    static let draftsChanged = Notification.Name("draftsChanged")
}

final class DraftManager: ObservableObject {
    static let shared = DraftManager()

    struct ReplyDraft: Codable, Hashable {
        var ticketId: Int
        var body: String
        var isInternalNote: Bool
        var updatedAt: Date
    }

    @Published private(set) var drafts: [Int: ReplyDraft] = [:]

    private let storageURL: URL = {
        let fm = FileManager.default
        let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("zammad_reply_drafts.json")
    }()

    private init() {
        load()
    }

    func draft(for ticketId: Int) -> ReplyDraft? {
        drafts[ticketId]
    }

    func hasDraft(for ticketId: Int) -> Bool {
        drafts[ticketId] != nil
    }

    func save(ticketId: Int, body: String, isInternalNote: Bool) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            delete(for: ticketId)
            return
        }
        let draft = ReplyDraft(ticketId: ticketId, body: body, isInternalNote: isInternalNote, updatedAt: Date())
        drafts[ticketId] = draft
        persist()
    }

    func delete(for ticketId: Int) {
        guard drafts.removeValue(forKey: ticketId) != nil else { return }
        persist()
    }

    private func persist() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(drafts) {
            try? data.write(to: storageURL, options: .atomic)
        }
        NotificationCenter.default.post(name: .draftsChanged, object: nil)
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let saved = try? decoder.decode([Int: ReplyDraft].self, from: data) {
            drafts = saved
        }
    }
}
