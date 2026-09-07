import Foundation
import CryptoKit

// MARK: - Chat Models

/// One installation of the app belonging to a colleague. Each device has its own
/// Curve25519 key pair, so an agent can run the app on an iPhone and an iPad at
/// the same time and both can read the conversation.
struct ChatDevice: Codable, Identifiable, Hashable {
    let id: Int              // Proxy-assigned device id
    let publicKey: String    // Curve25519 public key (base64)
}

/// An engineer registered for chat on the same Zammad instance.
struct ChatUser: Codable, Identifiable, Hashable {
    let id: Int              // Proxy-assigned chat user id
    let zammadUserId: Int    // The user's id on the Zammad instance
    let name: String
    let email: String?
    let devices: [ChatDevice]

    /// Whether we can encrypt to this colleague at all — false until they have
    /// opened the app once and published a device key.
    var canReceiveEncrypted: Bool { !devices.isEmpty }
}

/// A group chat. The group key is end-to-end encrypted: it exists on the proxy
/// only in wrapped form, sealed once per member *device* with the pairwise key
/// between the wrapping device and that device.
struct ChatGroup: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let creatorId: Int
    let myWrappedKey: String?
    /// Public key of the device that wrapped our copy of the group key.
    let wrapperPublicKey: String?
    var members: [ChatUser]?
    /// Member devices that joined after the group was created and hold no copy
    /// of the group key yet. Any member that can open the group re-wraps for them.
    let devicesMissingKeys: [ChatDevice]?
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
    var deleted: Bool?

    /// v4 direct messages: the public key of the device that sent this message,
    /// and this device's wrapped copy of the random body key. Both are nil for
    /// group messages (which use the group key) and for a direct message that
    /// was not addressed to this device.
    let senderPublicKey: String?
    let wrappedKey: String?

    /// Whether this message travelled end-to-end encrypted. Not part of the
    /// wire format — set locally from the `enc1:` prefix on decrypt (received)
    /// or to `true` on send (we only send when we can encrypt).
    var isEncrypted: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, fromUserId, toUserId, groupId, fromUserName, body, ticketId, ticketNumber
        case attachmentId, attachmentName, attachmentMime, createdAt, deleted
        case senderPublicKey, wrappedKey
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
        deleted = try container.decodeIfPresent(Bool.self, forKey: .deleted)
        senderPublicKey = try container.decodeIfPresent(String.self, forKey: .senderPublicKey)
        wrappedKey = try container.decodeIfPresent(String.self, forKey: .wrappedKey)
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
    /// The proxy answered, but not in the shape this app understands — in
    /// practice a proxy still running the pre-v4 (one key per user) protocol.
    case protocolMismatch

    var errorDescription: String? {
        switch self {
        case .notRegistered, .serverUnavailable: return "chat_unavailable".localized()
        case .serverError(let code): return String(format: "chat_server_error".localized(), code)
        case .encryptionUnavailable: return "chat_encryption_unavailable".localized()
        case .attachmentTooLarge: return "chat_attachment_too_large".localized()
        case .protocolMismatch: return "chat_server_outdated".localized()
        }
    }
}

// MARK: - End-to-end encryption

/// End-to-end encryption for chat bodies. Each device holds a Curve25519 key
/// pair (private key in the Keychain, public key published per device in the
/// chat directory). Bodies and attachments are sealed with ChaChaPoly under a
/// symmetric content key — random per message for direct chats, long-lived per
/// group — and that content key is wrapped for each recipient device with the
/// pairwise ECDH + HKDF key. The proxy only ever stores ciphertext and wrapped
/// keys.
///
/// Each device publishes its own public key under a stable device id, so one
/// agent can use several devices at once: a direct message body is sealed with a
/// random message key that is wrapped for every device of the recipient and for
/// the sender's other devices.
///
/// Limitations (deliberate, for simplicity): a device that registers after a
/// message was sent can't read that message — keys are wrapped at send time for
/// the devices known then. There is no forward secrecy and no out-of-band key
/// verification.
enum ChatCrypto {
    private static let keychainKey = "chat_e2e_private_key"
    private static let deviceIdKey = "chat_device_id"
    private static let prefix = "enc1:"

    /// This install's stable device id, generated once and kept in the Keychain
    /// beside the private key so the two always travel together: a reinstall
    /// that keeps the Keychain keeps both, and one that doesn't gets a fresh
    /// identity rather than a device id pointing at a key we no longer hold.
    static var deviceId: String {
        if let existing = KeychainHelper.load(forKey: deviceIdKey), !existing.isEmpty {
            return existing
        }
        let generated = UUID().uuidString
        KeychainHelper.save(generated, forKey: deviceIdKey)
        return generated
    }

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

    // MARK: Content keys
    //
    // Both kinds of conversation seal their bodies and attachments with a random
    // 256-bit symmetric "content key": a fresh one per message for direct chats,
    // a long-lived group key for groups. Only the way the key is distributed
    // differs — it is wrapped per recipient device with the pairwise ECDH key.

    /// A fresh random content key (per-message for direct chats, per-group for groups).
    static func generateContentKey() -> Data {
        SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
    }

    /// Wraps (seals) a content key for one device, using our pairwise key with it.
    static func wrapKey(_ contentKey: Data, forDevicePublicKey devicePublicKey: String) throws -> String {
        let key = try pairwiseKey(partnerPublicKeyBase64: devicePublicKey)
        let sealed = try ChaChaPoly.seal(contentKey, using: key)
        return sealed.combined.base64EncodedString()
    }

    /// Unwraps our copy of a content key, using our pairwise key with the device
    /// that wrapped it.
    static func unwrapKey(_ wrapped: String, wrapperPublicKey: String) -> Data? {
        guard let data = Data(base64Encoded: wrapped),
              let key = try? pairwiseKey(partnerPublicKeyBase64: wrapperPublicKey),
              let sealed = try? ChaChaPoly.SealedBox(combined: data),
              let plain = try? ChaChaPoly.open(sealed, using: key) else { return nil }
        return plain
    }

    // MARK: Bodies

    static func encrypt(_ plaintext: String, contentKey: Data) throws -> String {
        let sealed = try ChaChaPoly.seal(Data(plaintext.utf8), using: SymmetricKey(data: contentKey))
        return prefix + sealed.combined.base64EncodedString()
    }

    /// Returns the plaintext for encrypted bodies, the body unchanged when it
    /// isn't encrypted, or a placeholder when we have no key for it (e.g. the
    /// message predates this device's registration).
    static func decrypt(_ body: String, contentKey: Data?) -> String {
        guard body.hasPrefix(prefix) else { return body }
        guard let contentKey else { return "chat_encrypted_placeholder".localized() }
        return open(body, with: SymmetricKey(data: contentKey)) ?? "chat_encrypted_placeholder".localized()
    }

    private static func open(_ body: String, with key: SymmetricKey) -> String? {
        guard let data = Data(base64Encoded: String(body.dropFirst(prefix.count))),
              let sealed = try? ChaChaPoly.SealedBox(combined: data),
              let plain = try? ChaChaPoly.open(sealed, using: key),
              let text = String(data: plain, encoding: .utf8) else { return nil }
        return text
    }

    // MARK: Attachment data (always encrypted, with the message's content key)

    static func encryptData(_ data: Data, contentKey: Data) throws -> Data {
        try ChaChaPoly.seal(data, using: SymmetricKey(data: contentKey)).combined
    }

    static func decryptData(_ data: Data, contentKey: Data) throws -> Data {
        try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data), using: SymmetricKey(data: contentKey))
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

    /// Removes a single message from the cached history (local delete).
    func remove(id: Int, key: String) {
        let remaining = load(key: key).filter { $0.id != id }
        if let data = try? encoder.encode(remaining) {
            try? data.write(to: fileURL(for: key), options: .atomic)
        }
    }

    /// Deletes the entire cached history for a conversation.
    func clear(key: String) {
        try? FileManager.default.removeItem(at: fileURL(for: key))
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

    /// This device's proxy-side id, and every device registered to our own
    /// account — set by register(). Outgoing direct messages are wrapped for our
    /// other devices too, so an agent's iPad can read what their iPhone sent.
    private(set) var myChatDeviceId: Int?
    private(set) var myDevices: [ChatDevice] = []

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
        // Identifies which of our devices is calling, so the proxy can hand back
        // the key envelopes addressed to this device.
        request.setValue(ChatCrypto.deviceId, forHTTPHeaderField: "X-Device-Id")
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
        do {
            return try decoder.decode(T.self, from: data)
        } catch let error as DecodingError {
            // A field we require is absent or the wrong type. The realistic cause
            // is a proxy still speaking the pre-v4 protocol, so report that rather
            // than Foundation's "the data couldn't be read because it is missing".
            print("DEBUG: [Chat] Decode failed for \(T.self) at \(decodingPath(error)): \(error)")
            throw ChatError.protocolMismatch
        }
    }

    /// The key path Foundation choked on, for the debug log.
    private func decodingPath(_ error: DecodingError) -> String {
        let context: DecodingError.Context
        switch error {
        case .keyNotFound(let key, let ctx):
            return (ctx.codingPath.map(\.stringValue) + [key.stringValue]).joined(separator: ".")
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
            context = ctx
        @unknown default:
            return "unknown"
        }
        return context.codingPath.map(\.stringValue).joined(separator: ".")
    }

    // MARK: Registration & directory

    /// Registers (or refreshes) this device in the proxy's chat directory. Each
    /// device publishes its own public key and its own push registration, so
    /// registering on a second device leaves the first one working.
    @discardableResult
    func register(currentUser: User) async throws -> Int {
        struct RegisterResponse: Decodable {
            let chatUserId: Int
            let chatDeviceId: Int
            let devices: [ChatDevice]
        }
        let body: [String: Any] = [
            "zammad_user_id": currentUser.id,
            "name": currentUser.fullname,
            "email": currentUser.email,
            "proxy_user_id": SettingsManager.shared.getProxyUserID() ?? "",
            "public_key": ChatCrypto.publicKeyBase64,
            "device_id": ChatCrypto.deviceId
        ]
        let proxyUserID = SettingsManager.shared.getProxyUserID() ?? ""
        print("DEBUG: [Chat] Registreren — proxy user ID \(proxyUserID.isEmpty ? "ONTBREEKT (geen pushes mogelijk)" : "gekoppeld") ")
        let request = try makeRequest(path: "register", method: "POST", body: body)
        let response: RegisterResponse = try await perform(request)
        myChatUserId = response.chatUserId
        myChatDeviceId = response.chatDeviceId
        myDevices = response.devices
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
                decrypted.body = ChatCrypto.decrypt(last.body, contentKey: groupKey(for: group))
            } else {
                decrypted.body = ChatCrypto.decrypt(last.body, contentKey: messageKey(for: last))
            }
            conversations[index].lastMessage = decrypted
        }
        totalUnread = conversations.reduce(0) { $0 + $1.unreadCount }
        return conversations
    }

    // MARK: Groups

    /// Creates a group. The group key is wrapped once per member *device* — plus
    /// each of our own devices — so the proxy never sees it in the clear and
    /// every device of every member can open it.
    @discardableResult
    func createGroup(name: String, members: [ChatUser]) async throws -> ChatGroup {
        guard let myChatUserId else { throw ChatError.notRegistered }
        let groupKey = ChatCrypto.generateContentKey()

        var wrappedKeys: [[String: Any]] = []
        for member in members {
            guard member.canReceiveEncrypted else { throw ChatError.encryptionUnavailable }
            for device in member.devices {
                wrappedKeys.append([
                    "device_id": device.id,
                    "wrapped_key": try ChatCrypto.wrapKey(groupKey, forDevicePublicKey: device.publicKey),
                    "wrapper_public_key": ChatCrypto.publicKeyBase64
                ])
            }
        }
        // Our own devices, including this one — wrapping to ourselves works
        // because ECDH(our private, our public) is a valid shared secret.
        for device in myDevices {
            wrappedKeys.append([
                "device_id": device.id,
                "wrapped_key": try ChatCrypto.wrapKey(groupKey, forDevicePublicKey: device.publicKey),
                "wrapper_public_key": ChatCrypto.publicKeyBase64
            ])
        }

        let body: [String: Any] = [
            "name": name,
            "member_ids": members.map(\.id) + [myChatUserId],
            "wrapped_keys": wrappedKeys
        ]
        let request = try makeRequest(path: "groups", method: "POST", body: body)
        let group: ChatGroup = try await perform(request)
        groupKeys[group.id] = groupKey
        return group
    }

    func fetchGroups() async throws -> [ChatGroup] {
        let request = try makeRequest(path: "groups")
        let groups: [ChatGroup] = try await perform(request)
        await shareGroupKeysWithNewDevices(in: groups)
        return groups
    }

    /// Re-wraps the group key for member devices that don't have it yet — a
    /// colleague who added an iPad after the group was created would otherwise
    /// never be able to read it. Best-effort: we can only help with groups this
    /// device can open itself, and any member who can will do the same.
    private func shareGroupKeysWithNewDevices(in groups: [ChatGroup]) async {
        for group in groups {
            let missing = group.devicesMissingKeys ?? []
            guard !missing.isEmpty, let key = groupKey(for: group) else { continue }

            var wrappedKeys: [[String: Any]] = []
            for device in missing {
                guard let wrapped = try? ChatCrypto.wrapKey(key, forDevicePublicKey: device.publicKey) else { continue }
                wrappedKeys.append([
                    "device_id": device.id,
                    "wrapped_key": wrapped,
                    "wrapper_public_key": ChatCrypto.publicKeyBase64
                ])
            }
            guard !wrappedKeys.isEmpty else { continue }

            struct TopUpResponse: Decodable { let added: Int }
            guard let request = try? makeRequest(path: "groups/\(group.id)/keys", method: "POST",
                                                 body: ["wrapped_keys": wrappedKeys]) else { continue }
            let _: TopUpResponse? = try? await perform(request)
        }
    }

    /// The unwrapped group key, or nil when this device has no envelope for the
    /// group (it was created before this device registered). Cached per session.
    func groupKey(for group: ChatGroup) -> Data? {
        if let cached = groupKeys[group.id] { return cached }
        guard let wrapped = group.myWrappedKey,
              let wrapperKey = group.wrapperPublicKey,
              let key = ChatCrypto.unwrapKey(wrapped, wrapperPublicKey: wrapperKey) else { return nil }
        groupKeys[group.id] = key
        return key
    }

    /// The content key for one direct message: this device's envelope, unwrapped
    /// against the sending device's public key. Nil when the message carries no
    /// envelope for us, which is what produces the "encrypted message"
    /// placeholder rather than a crash.
    private func messageKey(for message: ChatMessage) -> Data? {
        guard let wrapped = message.wrappedKey,
              let senderKey = message.senderPublicKey else { return nil }
        return ChatCrypto.unwrapKey(wrapped, wrapperPublicKey: senderKey)
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
            if messages[index].deleted == true {
                // Tombstone: the sender deleted this message for everyone.
                messages[index].body = "chat_message_deleted".localized()
                messages[index].isEncrypted = true
                continue
            }
            let raw = messages[index].body
            messages[index].isEncrypted = ChatCrypto.isEncrypted(raw)
            switch target {
            case .direct:
                messages[index].body = ChatCrypto.decrypt(raw, contentKey: messageKey(for: messages[index]))
            case .group(let group):
                messages[index].body = ChatCrypto.decrypt(raw, contentKey: groupKey(for: group))
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
            guard partner.canReceiveEncrypted else { throw ChatError.encryptionUnavailable }
            // Our own device list comes from register(); without it we'd send a
            // message we couldn't read back ourselves.
            guard !myDevices.isEmpty else { throw ChatError.notRegistered }

            // One random key per message, wrapped for every device that may read
            // it: all of the recipient's, and all of ours. Ours includes *this*
            // device — unlike the old pairwise key, a random message key can't be
            // re-derived, so without an envelope of our own we could not read our
            // own sent messages after a refetch.
            let messageKey = ChatCrypto.generateContentKey()
            var envelopes: [[String: Any]] = []
            for device in partner.devices + myDevices {
                envelopes.append([
                    "device_id": device.id,
                    "wrapped_key": try ChatCrypto.wrapKey(messageKey, forDevicePublicKey: device.publicKey)
                ])
            }

            wireBody = try ChatCrypto.encrypt(body, contentKey: messageKey)
            payload["to_user_id"] = partner.id
            payload["sender_public_key"] = ChatCrypto.publicKeyBase64
            payload["keys"] = envelopes
            if let attachment {
                let sealed = try ChatCrypto.encryptData(attachment.data, contentKey: messageKey)
                let attachmentId = try await uploadAttachment(sealed, filename: attachment.filename, mimeType: attachment.mimeType)
                payload["attachment_id"] = attachmentId
                payload["attachment_name"] = attachment.filename
                payload["attachment_mime"] = attachment.mimeType
            }
        case .group(let group):
            guard let key = groupKey(for: group) else {
                throw ChatError.encryptionUnavailable
            }
            wireBody = try ChatCrypto.encrypt(body, contentKey: key)
            payload["group_id"] = group.id
            if let attachment {
                let sealed = try ChatCrypto.encryptData(attachment.data, contentKey: key)
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

    // MARK: Deletion

    /// Deletes one of our own messages for everyone (the proxy tombstones it;
    /// only the sender is allowed to do this).
    func deleteMessage(id: Int) async throws {
        struct OkResponse: Decodable { let ok: Bool }
        let request = try makeRequest(path: "messages/\(id)", method: "DELETE")
        let _: OkResponse = try await perform(request)
    }

    /// Deletes an entire conversation on the proxy. For a direct chat this
    /// removes all messages for both participants; for a group the creator
    /// deletes the group for everyone, while a regular member leaves it.
    func deleteConversation(_ target: ChatTarget) async throws {
        struct OkResponse: Decodable { let ok: Bool }
        let body: [String: Any]
        switch target {
        case .direct(let partner): body = ["with_user_id": partner.id]
        case .group(let group): body = ["group_id": group.id]
        }
        let request = try makeRequest(path: "conversations/delete", method: "POST", body: body)
        let _: OkResponse = try await perform(request)
        await refreshUnreadCount()
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

    /// Downloads and decrypts a message's attachment. An attachment is sealed
    /// with the same content key as the message that carries it, so decrypting
    /// it needs that message rather than just the conversation.
    func downloadAttachment(for message: ChatMessage, in target: ChatTarget) async throws -> Data {
        guard let attachmentId = message.attachmentId else { throw ChatError.serverUnavailable }
        let contentKey: Data?
        switch target {
        case .direct: contentKey = messageKey(for: message)
        case .group(let group): contentKey = groupKey(for: group)
        }
        guard let contentKey else { throw ChatError.encryptionUnavailable }

        let request = try makeRequest(path: "attachments/\(attachmentId)")
        let response: AttachmentDownloadResponse = try await perform(request)
        guard let sealed = Data(base64Encoded: response.data) else { throw ChatError.serverUnavailable }
        return try ChatCrypto.decryptData(sealed, contentKey: contentKey)
    }
}
