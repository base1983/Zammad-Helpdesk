import Foundation
import CryptoKit

// MARK: - Chat Models

/// An engineer registered for chat on the same Zammad instance.
struct ChatUser: Codable, Identifiable, Hashable {
    let id: Int              // Proxy-assigned chat user id
    let zammadUserId: Int    // The user's id on the Zammad instance
    let name: String
    let email: String?
    let publicKey: String?   // Curve25519 public key (base64) for E2E encryption
}

/// A group chat. The group key is end-to-end encrypted: it exists on the proxy
/// only in wrapped form (sealed per member with the creator↔member pairwise key).
struct ChatGroup: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let creatorId: Int
    let creatorPublicKey: String?
    let myWrappedKey: String?
    var members: [ChatUser]?
}

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: Int
    let fromUserId: Int
    let toUserId: Int?
    let groupId: Int?
    let fromUserName: String?  // Sender display name (relevant in groups)
    var body: String
    let ticketId: Int?         // Optional ticket reference for handoffs
    let ticketNumber: String?
    let attachmentId: Int?
    var attachmentName: String?
    let attachmentMime: String?
    let createdAt: Date

    /// Whether this message travelled end-to-end encrypted. Not part of the
    /// wire format — set locally from the `enc1:` prefix on decrypt (received)
    /// or to `true` on send (we only send when we can encrypt).
    var isEncrypted: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, fromUserId, toUserId, groupId, fromUserName, body, ticketId, ticketNumber
        case attachmentId, attachmentName, attachmentMime, createdAt
        case isEncrypted // persisted in the local history cache; stripped for wire payloads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        fromUserId = try container.decode(Int.self, forKey: .fromUserId)
        toUserId = try container.decodeIfPresent(Int.self, forKey: .toUserId)
        groupId = try container.decodeIfPresent(Int.self, forKey: .groupId)
        fromUserName = try container.decodeIfPresent(String.self, forKey: .fromUserName)
        body = try container.decode(String.self, forKey: .body)
        ticketId = try container.decodeIfPresent(Int.self, forKey: .ticketId)
        ticketNumber = try container.decodeIfPresent(String.self, forKey: .ticketNumber)
        attachmentId = try container.decodeIfPresent(Int.self, forKey: .attachmentId)
        attachmentName = try container.decodeIfPresent(String.self, forKey: .attachmentName)
        attachmentMime = try container.decodeIfPresent(String.self, forKey: .attachmentMime)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        isEncrypted = try container.decodeIfPresent(Bool.self, forKey: .isEncrypted) ?? false
    }
}

/// A pending outgoing attachment (photo or file), pre-encryption.
struct PendingChatAttachment {
    let data: Data
    let filename: String
    let mimeType: String

    var isImage: Bool { mimeType.hasPrefix("image/") }
    static let maxBytes = 10 * 1024 * 1024
}

/// Either a direct conversation partner or a group.
enum ChatTarget: Identifiable, Hashable {
    case direct(ChatUser)
    case group(ChatGroup)

    var id: String {
        switch self {
        case .direct(let user): "dm-\(user.id)"
        case .group(let group): "group-\(group.id)"
        }
    }

    var displayName: String {
        switch self {
        case .direct(let user): user.name
        case .group(let group): group.name
        }
    }
}

struct ChatConversation: Codable, Identifiable {
    let partner: ChatUser?
    let group: ChatGroup?
    var lastMessage: ChatMessage?
    let unreadCount: Int

    var id: String {
        if let partner { return "dm-\(partner.id)" }
        if let group { return "group-\(group.id)" }
        return "unknown"
    }

    var target: ChatTarget? {
        if let partner { return .direct(partner) }
        if let group { return .group(group) }
        return nil
    }
}

enum ChatError: Error, LocalizedError {
    case notRegistered
    case serverUnavailable
    case serverError(statusCode: Int)
    case encryptionUnavailable
    case attachmentTooLarge

    var errorDescription: String? {
        switch self {
        case .notRegistered, .serverUnavailable: return "chat_unavailable".localized()
        case .serverError(let code): return String(format: "chat_server_error".localized(), code)
        case .encryptionUnavailable: return "chat_encryption_unavailable".localized()
        case .attachmentTooLarge: return "chat_attachment_too_large".localized()
        }
    }
}

// MARK: - End-to-end encryption

/// End-to-end encryption for chat bodies. Each device holds a Curve25519 key
/// pair (private key in the Keychain, public key published via the chat
/// directory). Direct messages use a pairwise ECDH + HKDF key; groups use a
/// random symmetric group key that is wrapped per member with the
/// creator↔member pairwise key. Bodies and attachments are sealed with
/// ChaChaPoly — the proxy only ever stores ciphertext and wrapped keys.
///
/// Limitations (deliberate, for simplicity): one key pair per device — a
/// reinstall keeps the key (Keychain survives), but a *new* device generates a
/// new key and can't read older ciphertext; there is no forward secrecy or
/// out-of-band key verification.
enum ChatCrypto {
    private static let keychainKey = "chat_e2e_private_key"
    private static let prefix = "enc1:"

    private static func privateKey() -> Curve25519.KeyAgreement.PrivateKey {
        if let stored = KeychainHelper.load(forKey: keychainKey),
           let data = Data(base64Encoded: stored),
           let key = try? Curve25519.KeyAgreement.PrivateKey(rawRepresentation: data) {
            return key
        }
        let key = Curve25519.KeyAgreement.PrivateKey()
        KeychainHelper.save(key.rawRepresentation.base64EncodedString(), forKey: keychainKey)
        return key
    }

    static var publicKeyBase64: String {
        privateKey().publicKey.rawRepresentation.base64EncodedString()
    }

    /// Whether a wire body is an encrypted payload (has the `enc1:` prefix).
    static func isEncrypted(_ body: String) -> Bool {
        body.hasPrefix(prefix)
    }

    private static func pairwiseKey(partnerPublicKeyBase64: String) throws -> SymmetricKey {
        guard let partnerData = Data(base64Encoded: partnerPublicKeyBase64) else {
            throw CryptoKitError.incorrectParameterSize
        }
        let partnerKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: partnerData)
        let secret = try privateKey().sharedSecretFromKeyAgreement(with: partnerKey)
        return secret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: Data("zammad-helpdesk-chat-v1".utf8),
            sharedInfo: Data(),
            outputByteCount: 32
        )
    }

    // MARK: Direct messages (pairwise key)

    static func encrypt(_ plaintext: String, partnerPublicKey: String) throws -> String {
        let key = try pairwiseKey(partnerPublicKeyBase64: partnerPublicKey)
        let sealed = try ChaChaPoly.seal(Data(plaintext.utf8), using: key)
        return prefix + sealed.combined.base64EncodedString()
    }

    /// Returns the plaintext for encrypted bodies, the body unchanged when it
    /// isn't encrypted, or a placeholder when decryption fails (e.g. the
    /// message was encrypted for a key this device no longer has).
    static func decrypt(_ body: String, partnerPublicKey: String?) -> String {
        guard body.hasPrefix(prefix) else { return body }
        guard let partnerPublicKey,
              let key = try? pairwiseKey(partnerPublicKeyBase64: partnerPublicKey) else {
            return "chat_encrypted_placeholder".localized()
        }
        return open(body, with: key) ?? "chat_encrypted_placeholder".localized()
    }

    // MARK: Groups (wrapped group key)

    /// A fresh random group key.
    static func generateGroupKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// Wraps (seals) a group key for a member using our pairwise key with them.
    static func wrapKey(_ groupKey: Data, forMemberPublicKey memberKey: String) throws -> String {
        let key = try pairwiseKey(partnerPublicKeyBase64: memberKey)
        let sealed = try ChaChaPoly.seal(groupKey, using: key)
        return sealed.combined.base64EncodedString()
    }

    /// Unwraps our copy of a group key using the pairwise key with the creator.
    static func unwrapKey(_ wrapped: String, creatorPublicKey: String) -> Data? {
        guard let data = Data(base64Encoded: wrapped),
              let key = try? pairwiseKey(partnerPublicKeyBase64: creatorPublicKey),
              let sealed = try? ChaChaPoly.SealedBox(combined: data),
              let plain = try? ChaChaPoly.open(sealed, using: key) else { return nil }
        return plain
    }

    static func encrypt(_ plaintext: String, groupKey: Data) throws -> String {
        let sealed = try ChaChaPoly.seal(Data(plaintext.utf8), using: SymmetricKey(data: groupKey))
        return prefix + sealed.combined.base64EncodedString()
    }

    static func decrypt(_ body: String, groupKey: Data?) -> String {
        guard body.hasPrefix(prefix) else { return body }
        guard let groupKey else { return "chat_encrypted_placeholder".localized() }
        return open(body, with: SymmetricKey(data: groupKey)) ?? "chat_encrypted_placeholder".localized()
    }

    private static func open(_ body: String, with key: SymmetricKey) -> String? {
        guard let data = Data(base64Encoded: String(body.dropFirst(prefix.count))),
              let sealed = try? ChaChaPoly.SealedBox(combined: data),
              let plain = try? ChaChaPoly.open(sealed, using: key),
              let text = String(data: plain, encoding: .utf8) else { return nil }
        return text
    }

    // MARK: Attachment data (always encrypted)

    static func encryptData(_ data: Data, partnerPublicKey: String) throws -> Data {
        let key = try pairwiseKey(partnerPublicKeyBase64: partnerPublicKey)
        return try ChaChaPoly.seal(data, using: key).combined
    }

    static func decryptData(_ data: Data, partnerPublicKey: String) throws -> Data {
        let key = try pairwiseKey(partnerPublicKeyBase64: partnerPublicKey)
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: key)
    }

    static func encryptData(_ data: Data, groupKey: Data) throws -> Data {
        try ChaChaPoly.seal(data, using: SymmetricKey(data: groupKey)).combined
    }

    static func decryptData(_ data: Data, groupKey: Data) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: SymmetricKey(data: groupKey))
    }
}

// MARK: - Local history cache

/// On-device message history, one JSON file per conversation. Messages are
/// stored decrypted (the files live in the app sandbox, protected by iOS file
/// protection) and pruned to the configured retention window.
final class ChatHistoryStore {
    static let shared = ChatHistoryStore()

    static let retentionKey = "chat_history_retention_days"
    static let defaultRetentionDays = 90

    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("ChatHistory", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
    }

    /// 0 means keep forever.
    var retentionDays: Int {
        let defaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk") ?? .standard
        let value = defaults.object(forKey: Self.retentionKey) as? Int
        return value ?? Self.defaultRetentionDays
    }

    private var cutoffDate: Date? {
        let days = retentionDays
        guard days > 0 else { return nil }
        return Calendar.current.date(byAdding: .day, value: -days, to: Date())
    }

    private func fileURL(for key: String) -> URL {
        directory.appendingPathComponent("\(key).json")
    }

    func load(key: String) -> [ChatMessage] {
        guard let data = try? Data(contentsOf: fileURL(for: key)),
              let messages = try? decoder.decode([ChatMessage].self, from: data) else { return [] }
        return prune(messages)
    }

    /// Merges new messages into the cached history (by id), prunes to the
    /// retention window, persists, and returns the merged list.
    @discardableResult
    func merge(_ new: [ChatMessage], key: String) -> [ChatMessage] {
        var byId = Dictionary(uniqueKeysWithValues: load(key: key).map { ($0.id, $0) })
        for message in new { byId[message.id] = message }
        let merged = prune(byId.values.sorted { $0.id < $1.id })
        if let data = try? encoder.encode(merged) {
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
        return merged
    }

    private func prune(_ messages: [ChatMessage]) -> [ChatMessage] {
        guard let cutoff = cutoffDate else { return messages }
        return messages.filter { $0.createdAt >= cutoff }
    }

    /// Re-prunes all conversation files; called at app launch.
    func pruneAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension == "json" {
            let key = file.deletingPathExtension().lastPathComponent
            merge([], key: key)
        }
    }
}

// MARK: - Chat Service

/// REST client for the chat endpoints on the notification proxy
/// (zammadproxy.world-ict.nl). The proxy authenticates every request by
/// validating the Zammad token against the caller's own Zammad instance,
/// and scopes the engineer directory per instance. See PROXY_CHAT_API.md
/// in the repository root for the server-side spec.
@MainActor
final class ChatService: ObservableObject {
    static let shared = ChatService()

    /// Our own chat identity on the proxy, set after register().
    @Published private(set) var myChatUserId: Int?

    /// Total unread messages across all conversations, for the toolbar badge.
    @Published private(set) var totalUnread = 0

    private let baseURL = URL(string: "https://zammadproxy.world-ict.nl/api/chat")!
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Unwrapped group keys, cached per group id for this session.
    private var groupKeys: [Int: Data] = [:]

    private init() {
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: Requests

    private func makeRequest(path: String, method: String = "GET", queryItems: [URLQueryItem] = [], body: [String: Any]? = nil) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else { throw APIError.invalidURL }

        guard let token = SettingsManager.shared.loadToken(), !token.isEmpty else { throw APIError.tokenNotSet }
        let serverURL = SettingsManager.shared.loadServerURL()

        var request = URLRequest(url: url, timeoutInterval: 60)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Token token=\(token)", forHTTPHeaderField: "Authorization")
        request.setValue(serverURL, forHTTPHeaderField: "X-Zammad-Url")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        return request
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw ChatError.serverUnavailable
        }
        guard let httpResponse = response as? HTTPURLResponse else { throw ChatError.serverUnavailable }
        // 404 means the proxy doesn't have the chat endpoints (yet).
        if httpResponse.statusCode == 404 { throw ChatError.serverUnavailable }
        if httpResponse.statusCode == 401 { throw APIError.authenticationFailed }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw ChatError.serverError(statusCode: httpResponse.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    // MARK: Registration & directory

    /// Registers (or refreshes) our identity in the proxy's chat directory,
    /// including our public key so colleagues can encrypt messages to us.
    @discardableResult
    func register(currentUser: User) async throws -> Int {
        struct RegisterResponse: Decodable { let chatUserId: Int }
        let body: [String: Any] = [
            "zammad_user_id": currentUser.id,
            "name": currentUser.fullname,
            "email": currentUser.email,
            "proxy_user_id": SettingsManager.shared.getProxyUserID() ?? "",
            "public_key": ChatCrypto.publicKeyBase64
        ]
        let proxyUserID = SettingsManager.shared.getProxyUserID() ?? ""
        print("DEBUG: [Chat] Registreren — proxy user ID \(proxyUserID.isEmpty ? "ONTBREEKT (geen pushes mogelijk)" : "gekoppeld") ")
        let request = try makeRequest(path: "register", method: "POST", body: body)
        let response: RegisterResponse = try await perform(request)
        myChatUserId = response.chatUserId
        return response.chatUserId
    }

    /// All engineers registered for chat on the same Zammad instance (excluding ourselves).
    func fetchEngineers() async throws -> [ChatUser] {
        let request = try makeRequest(path: "users")
        let users: [ChatUser] = try await perform(request)
        return users.filter { $0.id != myChatUserId }
    }

    // MARK: Conversations

    func fetchConversations() async throws -> [ChatConversation] {
        let request = try makeRequest(path: "conversations")
        var conversations: [ChatConversation] = try await perform(request)
        for index in conversations.indices {
            guard let last = conversations[index].lastMessage else { continue }
            var decrypted = last
            decrypted.isEncrypted = ChatCrypto.isEncrypted(last.body)
            if let group = conversations[index].group {
                decrypted.body = ChatCrypto.decrypt(last.body, groupKey: groupKey(for: group))
            } else {
                decrypted.body = ChatCrypto.decrypt(last.body, partnerPublicKey: conversations[index].partner?.publicKey)
            }
            conversations[index].lastMessage = decrypted
        }
        totalUnread = conversations.reduce(0) { $0 + $1.unreadCount }
        return conversations
    }

    // MARK: Groups

    /// Creates a group. Requires every member (and ourselves) to have a
    /// published public key: the group key is wrapped per member so the proxy
    /// never sees it in the clear.
    @discardableResult
    func createGroup(name: String, members: [ChatUser], me: ChatUser) async throws -> ChatGroup {
        let allMembers = members + [me]
        let groupKey = ChatCrypto.generateGroupKey()

        var wrappedKeys: [[String: Any]] = []
        for member in allMembers {
            guard let memberKey = member.publicKey, !memberKey.isEmpty else {
                throw ChatError.encryptionUnavailable
            }
            let wrapped = try ChatCrypto.wrapKey(groupKey, forMemberPublicKey: memberKey)
            wrappedKeys.append(["user_id": member.id, "wrapped_key": wrapped])
        }

        let body: [String: Any] = [
            "name": name,
            "member_ids": allMembers.map(\.id),
            "wrapped_keys": wrappedKeys
        ]
        let request = try makeRequest(path: "groups", method: "POST", body: body)
        let group: ChatGroup = try await perform(request)
        groupKeys[group.id] = groupKey
        return group
    }

    func fetchGroups() async throws -> [ChatGroup] {
        let request = try makeRequest(path: "groups")
        return try await perform(request)
    }

    /// The unwrapped group key, or nil when this device can't unwrap it
    /// (e.g. new device key). Cached per session.
    func groupKey(for group: ChatGroup) -> Data? {
        if let cached = groupKeys[group.id] { return cached }
        guard let wrapped = group.myWrappedKey,
              let creatorKey = group.creatorPublicKey,
              let key = ChatCrypto.unwrapKey(wrapped, creatorPublicKey: creatorKey) else { return nil }
        groupKeys[group.id] = key
        return key
    }

    // MARK: Messages

    /// Messages for a target, decrypted for display. Pass `since` (last known
    /// message id) for incremental polling.
    func fetchMessages(for target: ChatTarget, since: Int? = nil) async throws -> [ChatMessage] {
        var query: [URLQueryItem]
        switch target {
        case .direct(let partner): query = [URLQueryItem(name: "with", value: String(partner.id))]
        case .group(let group): query = [URLQueryItem(name: "group", value: String(group.id))]
        }
        if let since { query.append(URLQueryItem(name: "since", value: String(since))) }
        let request = try makeRequest(path: "messages", queryItems: query)
        var messages: [ChatMessage] = try await perform(request)
        for index in messages.indices {
            let raw = messages[index].body
            messages[index].isEncrypted = ChatCrypto.isEncrypted(raw)
            switch target {
            case .direct(let partner):
                messages[index].body = ChatCrypto.decrypt(raw, partnerPublicKey: partner.publicKey)
            case .group(let group):
                messages[index].body = ChatCrypto.decrypt(raw, groupKey: groupKey(for: group))
            }
        }
        return messages
    }

    /// Backwards-compatible direct-message fetch (used by existing callers).
    func fetchMessages(with partner: ChatUser, since: Int? = nil) async throws -> [ChatMessage] {
        try await fetchMessages(for: .direct(partner), since: since)
    }

    /// Sends a message, always end-to-end encrypted. Refuses to send (throws
    /// `ChatError.encryptionUnavailable`) when no encryption key is available,
    /// so plaintext never reaches the proxy — no silent downgrade.
    @discardableResult
    func send(to target: ChatTarget, body: String, ticket: Ticket? = nil, attachment: PendingChatAttachment? = nil) async throws -> ChatMessage {
        var payload: [String: Any] = [:]
        let wireBody: String

        switch target {
        case .direct(let partner):
            guard let partnerKey = partner.publicKey, !partnerKey.isEmpty else {
                throw ChatError.encryptionUnavailable
            }
            wireBody = try ChatCrypto.encrypt(body, partnerPublicKey: partnerKey)
            payload["to_user_id"] = partner.id
            if let attachment {
                let sealed = try ChatCrypto.encryptData(attachment.data, partnerPublicKey: partnerKey)
                let attachmentId = try await uploadAttachment(sealed, filename: attachment.filename, mimeType: attachment.mimeType)
                payload["attachment_id"] = attachmentId
                payload["attachment_name"] = attachment.filename
                payload["attachment_mime"] = attachment.mimeType
            }
        case .group(let group):
            guard let key = groupKey(for: group) else {
                throw ChatError.encryptionUnavailable
            }
            wireBody = try ChatCrypto.encrypt(body, groupKey: key)
            payload["group_id"] = group.id
            if let attachment {
                let sealed = try ChatCrypto.encryptData(attachment.data, groupKey: key)
                let attachmentId = try await uploadAttachment(sealed, filename: attachment.filename, mimeType: attachment.mimeType)
                payload["attachment_id"] = attachmentId
                payload["attachment_name"] = attachment.filename
                payload["attachment_mime"] = attachment.mimeType
            }
        }

        payload["body"] = wireBody
        if let ticket {
            payload["ticket_id"] = ticket.id
            payload["ticket_number"] = ticket.number
        }

        let request = try makeRequest(path: "messages", method: "POST", body: payload)
        var message: ChatMessage = try await perform(request)
        message.body = body        // return the plaintext for local display
        message.isEncrypted = true // reached only when the body was encrypted
        return message
    }

    /// Backwards-compatible direct send (used by the ticket handoff).
    @discardableResult
    func send(to partner: ChatUser, body: String, ticket: Ticket? = nil) async throws -> ChatMessage {
        try await send(to: .direct(partner), body: body, ticket: ticket)
    }

    func markRead(target: ChatTarget) async {
        struct OkResponse: Decodable { let ok: Bool }
        let body: [String: Any]
        switch target {
        case .direct(let partner): body = ["with_user_id": partner.id]
        case .group(let group): body = ["group_id": group.id]
        }
        guard let request = try? makeRequest(path: "read", method: "POST", body: body) else { return }
        let _: OkResponse? = try? await perform(request)
        await refreshUnreadCount()
    }

    /// Backwards-compatible direct-partner variant.
    func markRead(partnerId: Int) async {
        struct OkResponse: Decodable { let ok: Bool }
        guard let request = try? makeRequest(path: "read", method: "POST", body: ["with_user_id": partnerId]) else { return }
        let _: OkResponse? = try? await perform(request)
        await refreshUnreadCount()
    }

    /// Refreshes the unread total for the toolbar badge.
    func refreshUnreadCount() async {
        _ = try? await fetchConversations()
    }

    // MARK: Attachments

    private struct AttachmentUploadResponse: Decodable { let id: Int }
    private struct AttachmentDownloadResponse: Decodable { let data: String }

    private func uploadAttachment(_ sealedData: Data, filename: String, mimeType: String) async throws -> Int {
        guard sealedData.count <= PendingChatAttachment.maxBytes + 1024 else { throw ChatError.attachmentTooLarge }
        let body: [String: Any] = [
            "data": sealedData.base64EncodedString(),
            "filename": filename,
            "mime_type": mimeType
        ]
        let request = try makeRequest(path: "attachments", method: "POST", body: body)
        let response: AttachmentUploadResponse = try await perform(request)
        return response.id
    }

    /// Downloads and decrypts an attachment for a message in the given target.
    func downloadAttachment(id: Int, for target: ChatTarget) async throws -> Data {
        let request = try makeRequest(path: "attachments/\(id)")
        let response: AttachmentDownloadResponse = try await perform(request)
        guard let sealed = Data(base64Encoded: response.data) else { throw ChatError.serverUnavailable }
        switch target {
        case .direct(let partner):
            guard let key = partner.publicKey else { throw ChatError.encryptionUnavailable }
            return try ChatCrypto.decryptData(sealed, partnerPublicKey: key)
        case .group(let group):
            guard let key = groupKey(for: group) else { throw ChatError.encryptionUnavailable }
            return try ChatCrypto.decryptData(sealed, groupKey: key)
        }
    }
}
