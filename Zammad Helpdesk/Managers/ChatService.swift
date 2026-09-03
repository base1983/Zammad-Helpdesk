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

struct ChatMessage: Codable, Identifiable, Hashable {
    let id: Int
    let fromUserId: Int
    let toUserId: Int
    var body: String
    let ticketId: Int?       // Optional ticket reference for handoffs
    let ticketNumber: String?
    let createdAt: Date
}

struct ChatConversation: Codable, Identifiable {
    let partner: ChatUser
    var lastMessage: ChatMessage?
    let unreadCount: Int
    var id: Int { partner.id }
}

enum ChatError: Error, LocalizedError {
    case notRegistered
    case serverUnavailable
    case serverError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .notRegistered, .serverUnavailable: return "chat_unavailable".localized()
        case .serverError(let code): return String(format: "chat_server_error".localized(), code)
        }
    }
}

// MARK: - End-to-end encryption

/// End-to-end encryption for chat bodies. Each device holds a Curve25519 key
/// pair (private key in the Keychain, public key published via the chat
/// directory). A pairwise symmetric key is derived with ECDH + HKDF and bodies
/// are sealed with ChaChaPoly. The proxy only ever stores ciphertext.
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

    private static func symmetricKey(partnerPublicKeyBase64: String) throws -> SymmetricKey {
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

    static func encrypt(_ plaintext: String, partnerPublicKey: String) throws -> String {
        let key = try symmetricKey(partnerPublicKeyBase64: partnerPublicKey)
        let sealed = try ChaChaPoly.seal(Data(plaintext.utf8), using: key)
        return prefix + sealed.combined.base64EncodedString()
    }

    /// Returns the plaintext for encrypted bodies, the body unchanged when it
    /// isn't encrypted, or a placeholder when decryption fails (e.g. the
    /// message was encrypted for a key this device no longer has).
    static func decrypt(_ body: String, partnerPublicKey: String?) -> String {
        guard body.hasPrefix(prefix) else { return body }
        guard let partnerPublicKey,
              let data = Data(base64Encoded: String(body.dropFirst(prefix.count))),
              let key = try? symmetricKey(partnerPublicKeyBase64: partnerPublicKey),
              let sealed = try? ChaChaPoly.SealedBox(combined: data),
              let plain = try? ChaChaPoly.open(sealed, using: key),
              let text = String(data: plain, encoding: .utf8) else {
            return "chat_encrypted_placeholder".localized()
        }
        return text
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

        var request = URLRequest(url: url, timeoutInterval: 30)
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

    // MARK: API

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

    func fetchConversations() async throws -> [ChatConversation] {
        let request = try makeRequest(path: "conversations")
        var conversations: [ChatConversation] = try await perform(request)
        for index in conversations.indices {
            if let last = conversations[index].lastMessage {
                var decrypted = last
                decrypted.body = ChatCrypto.decrypt(last.body, partnerPublicKey: conversations[index].partner.publicKey)
                conversations[index].lastMessage = decrypted
            }
        }
        totalUnread = conversations.reduce(0) { $0 + $1.unreadCount }
        return conversations
    }

    /// Messages exchanged with a partner, decrypted for display. Pass `since`
    /// (last known message id) for incremental polling.
    func fetchMessages(with partner: ChatUser, since: Int? = nil) async throws -> [ChatMessage] {
        var query = [URLQueryItem(name: "with", value: String(partner.id))]
        if let since { query.append(URLQueryItem(name: "since", value: String(since))) }
        let request = try makeRequest(path: "messages", queryItems: query)
        var messages: [ChatMessage] = try await perform(request)
        for index in messages.indices {
            messages[index].body = ChatCrypto.decrypt(messages[index].body, partnerPublicKey: partner.publicKey)
        }
        return messages
    }

    /// Sends a message, end-to-end encrypted when the partner has published a
    /// public key (plaintext fallback for partners on older app versions).
    @discardableResult
    func send(to partner: ChatUser, body: String, ticket: Ticket? = nil) async throws -> ChatMessage {
        var wireBody = body
        if let partnerKey = partner.publicKey, !partnerKey.isEmpty {
            wireBody = try ChatCrypto.encrypt(body, partnerPublicKey: partnerKey)
        }
        var payload: [String: Any] = [
            "to_user_id": partner.id,
            "body": wireBody
        ]
        if let ticket {
            payload["ticket_id"] = ticket.id
            payload["ticket_number"] = ticket.number
        }
        let request = try makeRequest(path: "messages", method: "POST", body: payload)
        var message: ChatMessage = try await perform(request)
        message.body = body // return the plaintext for local display
        return message
    }

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
}
