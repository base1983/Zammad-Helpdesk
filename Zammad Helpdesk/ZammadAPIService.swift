import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse, decodingError, tokenNotSet, authenticationFailed, userNotFound, invalidURL
    case serverError(statusCode: Int, message: String?)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from the server."
        case .decodingError: return "Could not process data from the server."
        case .tokenNotSet: return "API token not set. Please go to Settings."
        case .authenticationFailed: return "Authentication failed. Please check your API token."
        case .userNotFound: return "Could not find the current user."
        case .invalidURL: return "The configured server URL is invalid."
        case .serverError(let code, let message):
            if let msg = message, let data = msg.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let error = json["error"] as? String {
                return error
            }
            // Fallback if message is not parsable or not present
            return "Server error: Status \(code)."
        }
    }
}

class ZammadAPIService {
    static let shared = ZammadAPIService()
    private init() {}

    private func getBaseURL(from urlString: String? = nil) throws -> URL {
        var urlStr = urlString ?? SettingsManager.shared.loadServerURL()
        if !urlStr.lowercased().hasPrefix("http") { urlStr = "https://" + urlStr }
        if urlStr.hasSuffix("/") { urlStr.removeLast() }
        if !urlStr.hasSuffix("/api/v1") { urlStr += "/api/v1" }
        if !urlStr.hasSuffix("/") { urlStr += "/" }
        guard let url = URL(string: urlStr) else { throw APIError.invalidURL }
        return url
    }
    
    private func createRequest(for endpoint: String, method: String = "GET", url: String? = nil, token: String? = nil) throws -> URLRequest {
        let baseURL = try getBaseURL(from: url)
        guard let fullUrl = URL(string: endpoint, relativeTo: baseURL) else { throw APIError.invalidURL }
        
        let apiToken = token ?? SettingsManager.shared.loadToken()
        guard let finalToken = apiToken, !finalToken.isEmpty else { throw APIError.tokenNotSet }
        
        var request = URLRequest(url: fullUrl, timeoutInterval: 120.0)
        request.httpMethod = method
        request.setValue("Token token=\(finalToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    private func fetchData<T: Decodable>(for request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        let urlForLog = request.url?.absoluteString ?? "?"
        if httpResponse.statusCode == 401 {
            let errorBody = String(data: data, encoding: .utf8) ?? ""
            print("Auth failed (401) on \(urlForLog): \(errorBody)")
            if !errorBody.isEmpty {
                throw APIError.serverError(statusCode: 401, message: errorBody)
            }
            throw APIError.authenticationFailed
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8)
            print("Server Error (\(httpResponse.statusCode)) on \(urlForLog): \(errorBody ?? "no body")")
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorBody)
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            print("JSON Decoding Error for \(T.self): \(error)")
            if let decodingError = error as? DecodingError {
                print("Decoding Error Details: \(decodingError)")
            }
            throw APIError.decodingError
        }
    }
    
    func testConnection(url: String, token: String) async -> Bool {
        do {
            let request = try createRequest(for: "users/me", url: url, token: token)
            let _: User = try await fetchData(for: request)
            return true
        } catch {
            print("Connection test failed: \(error)")
            return false
        }
    }

    /// Uses an existing Zammad browser session (from a WKWebView) to mint a personal access token.
    /// Pairs the captured cookies with the page's CSRF token to satisfy session-based CSRF protection.
    func createAccessTokenWithSession(url: String, cookies: [HTTPCookie], csrfToken: String?, tokenName: String) async throws -> String {
        let baseURL = try getBaseURL(from: url)
        guard let tokenURL = URL(string: "user_access_token", relativeTo: baseURL) else { throw APIError.invalidURL }

        var request = URLRequest(url: tokenURL, timeoutInterval: 30.0)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if let csrfToken, !csrfToken.isEmpty {
            request.setValue(csrfToken, forHTTPHeaderField: "X-CSRF-Token")
        }

        // Request a comprehensive set of permissions. Zammad only grants the ones
        // the authenticated user actually has, so listing unknowns is harmless.
        let body: [String: Any] = [
            "name": tokenName,
            "permission": Self.tokenPermissionsList
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if httpResponse.statusCode == 401 { throw APIError.authenticationFailed }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "no body"
            print("SSO token creation failed: HTTP \(httpResponse.statusCode) — \(body)")
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: "HTTP \(httpResponse.statusCode): \(body.prefix(200))")
        }

        let bodyStr = String(data: data, encoding: .utf8) ?? "nil"
        print("SSO token creation response: \(bodyStr.prefix(500))")

        struct TokenResponse: Decodable { let token: String }
        do {
            let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
            return decoded.token
        } catch {
            print("SSO token decoding failed. Body: \(bodyStr)")
            throw APIError.decodingError
        }
    }

    /// Logs in with username/password (HTTP Basic) and asks Zammad to mint a personal access token.
    /// The password is never persisted — only the resulting token is returned.
    func createAccessToken(url: String, username: String, password: String, tokenName: String) async throws -> String {
        let baseURL = try getBaseURL(from: url)
        guard let fullUrl = URL(string: "user_access_token", relativeTo: baseURL) else { throw APIError.invalidURL }

        var request = URLRequest(url: fullUrl, timeoutInterval: 30.0)
        request.httpMethod = "POST"
        let credentials = "\(username):\(password)"
        guard let credentialsData = credentials.data(using: .utf8) else { throw APIError.authenticationFailed }
        request.setValue("Basic \(credentialsData.base64EncodedString())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": tokenName,
            "permission": Self.tokenPermissionsList
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if httpResponse.statusCode == 401 { throw APIError.authenticationFailed }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.serverError(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8))
        }

        let bodyStr = String(data: data, encoding: .utf8) ?? "nil"
        print("Password token creation response: \(bodyStr.prefix(500))")

        struct TokenResponse: Decodable { let token: String }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return decoded.token
    }

    /// Permissions requested when creating a personal access token. Zammad only
    /// grants the subset that the authenticated user actually has, so listing
    /// admin permissions is harmless for normal agents.
    private static let tokenPermissionsList: [String] = [
        "ticket.agent",
        "ticket.customer",
        "user_preferences.notifications",
        "user_preferences.password",
        "user_preferences.access_token",
        "user_preferences.language",
        "user_preferences.avatar",
        "user_preferences.calendar",
        "user_preferences.device",
        "user_preferences.out_of_office",
        "cti.agent",
        "chat.agent",
        "knowledge_base.editor",
        "knowledge_base.reader",
        "report",
        "admin.user",
        "admin.organization",
        "admin.group",
        "admin.role",
        "admin.tag"
    ]
    
    func searchTickets(query: String) async throws -> [Ticket] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = "tickets/search?query=\(encodedQuery)&expand=true&per_page=200"
        let request = try createRequest(for: endpoint)
        return try await fetchData(for: request)
    }
    
    func fetchTickets(byStatusId id: Int) async throws -> [Ticket] {
        let endpoint = "tickets/search?query=state_id:\(id)&expand=true&per_page=200"
        let request = try createRequest(for: endpoint)
        return try await fetchData(for: request)
    }

    func fetchTicket(id: Int) async throws -> Ticket {
        let request = try createRequest(for: "tickets/\(id)?expand=true")
        return try await fetchData(for: request)
    }
    
    func fetchTicketStates() async throws -> [TicketState] {
        let request = try createRequest(for: "ticket_states")
        return try await fetchData(for: request)
    }
    
    func fetchTicketPriorities() async throws -> [TicketPriority] {
        let request = try createRequest(for: "ticket_priorities")
        return try await fetchData(for: request)
    }
    
    func fetchArticles(for ticketId: Int) async throws -> [TicketArticle] {
        let request = try createRequest(for: "ticket_articles/by_ticket/\(ticketId)")
        return try await fetchData(for: request)
    }
    
    func fetchCurrentUser() async throws -> User {
        let request = try createRequest(for: "users/me")
        return try await fetchData(for: request)
    }
    
    func fetchAllUsers() async throws -> [User] {
        var allUsers: [User] = []
        var currentPage = 1
        var hasMorePages = true
        let perPage = 100

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        while hasMorePages {
            let endpoint = "users?page=\(currentPage)&per_page=\(perPage)&expand=true"
            let request = try createRequest(for: endpoint)
            
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 401 { throw APIError.authenticationFailed }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8)
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorBody)
            }
            
            do {
                let users = try decoder.decode([User].self, from: data)
                allUsers.append(contentsOf: users)
                print("Fetched page \(currentPage) of users, got \(users.count) users. Total users so far: \(allUsers.count)")

                if users.count < perPage {
                    hasMorePages = false
                } else {
                    currentPage += 1
                }
            } catch {
                print("JSON Decoding Error for [User]: \(error)")
                if let decodingError = error as? DecodingError {
                    print("Decoding Error Details: \(decodingError)")
                }
                throw APIError.decodingError
            }
        }
        
        print("Finished fetching all users. Total: \(allUsers.count)")
        return allUsers
    }
    
    func fetchRoles() async throws -> [Role] {
        let request = try createRequest(for: "roles")
        return try await fetchData(for: request)
    }
    
    func fetchGroups() async throws -> [TicketGroup] {
        let request = try createRequest(for: "groups")
        return try await fetchData(for: request)
    }

    func fetchOrganizations() async throws -> [Organization] {
        var allOrganizations: [Organization] = []
        var currentPage = 1
        var hasMorePages = true
        let perPage = 100

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        while hasMorePages {
            let endpoint = "organizations?page=\(currentPage)&per_page=\(perPage)"
            let request = try createRequest(for: endpoint)

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            if httpResponse.statusCode == 401 { throw APIError.authenticationFailed }

            guard (200...299).contains(httpResponse.statusCode) else {
                let errorBody = String(data: data, encoding: .utf8)
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: errorBody)
            }

            do {
                let organizations = try decoder.decode([Organization].self, from: data)
                allOrganizations.append(contentsOf: organizations)
                print("Fetched page \(currentPage) of organizations, got \(organizations.count) organizations. Total organizations so far: \(allOrganizations.count)")

                if organizations.count < perPage {
                    hasMorePages = false
                } else {
                    currentPage += 1
                }
            } catch {
                print("JSON Decoding Error for [Organization]: \(error)")
                if let decodingError = error as? DecodingError {
                    print("Decoding Error Details: \(decodingError)")
                }
                throw APIError.decodingError
            }
        }
        
        print("Finished fetching all organizations. Total: \(allOrganizations.count)")
        return allOrganizations
    }
    
    // ... (Keep your existing code above updateTicket) ...

        func updateTicket(id: Int, payload: TicketUpdatePayload) async throws -> Ticket {
            var request = try createRequest(for: "tickets/\(id)", method: "PUT")
            request.httpBody = try JSONEncoder().encode(payload)
            return try await fetchData(for: request)
        }
        
        func createArticle(payload: ArticleCreationPayload) async throws -> TicketArticle {
            var request = try createRequest(for: "ticket_articles", method: "POST")
            request.httpBody = try JSONEncoder().encode(payload)
            return try await fetchData(for: request)
        }

        func createTicket(payload: TicketCreationPayload) async throws -> Ticket {
            var request = try createRequest(for: "tickets", method: "POST")
            
            // Because 'internal' is a keyword, we need a custom encoder for the payload.
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .useDefaultKeys
            
            request.httpBody = try encoder.encode(payload)
            return try await fetchData(for: request)
        }
        
        // MARK: - Time Accounting Methods
        
    func fetchTimeAccountingTypes() async throws -> [TimeAccountingType] {
            // OLD (Incorrect):
            // let request = try createRequest(for: "time_accounting_types")
            
            // NEW (Correct):
            let request = try createRequest(for: "time_accounting/types")
            return try await fetchData(for: request)
        }
        func createTimeAccounting(ticketId: Int, payload: TimeAccountingPayload) async throws -> TimeAccounting {
            var request = try createRequest(for: "tickets/\(ticketId)/time_accountings", method: "POST")
            request.httpBody = try JSONEncoder().encode(payload)
            return try await fetchData(for: request)
        }

        func fetchTimeAccountings(for ticketId: Int) async throws -> [TimeAccounting] {
            let request = try createRequest(for: "time_accountings?ticket_id=\(ticketId)")
            return try await fetchData(for: request)
        }

        func fetchTimeAccountingsGracefully(for ticketId: Int) async -> [TimeAccounting] {
            do {
                return try await fetchTimeAccountings(for: ticketId)
            } catch APIError.serverError(let statusCode, _) where statusCode == 401 || statusCode == 403 || statusCode == 404 {
                print("Time accountings endpoint forbidden (\(statusCode)). Continuing without time accountings.")
                return []
            } catch APIError.authenticationFailed {
                print("Time accountings endpoint auth failed. Continuing without time accountings.")
                return []
            } catch {
                print("Time accountings endpoint failed: \(error). Continuing without.")
                return []
            }
        }

        func fetchTimeAccountingTypesGracefully() async -> [TimeAccountingType] {
            do {
                return try await fetchTimeAccountingTypes()
            } catch APIError.serverError(let statusCode, _) where statusCode == 401 || statusCode == 403 || statusCode == 404 {
                print("Time accounting types endpoint forbidden (\(statusCode)). Continuing without time accounting.")
                return []
            } catch APIError.authenticationFailed {
                print("Time accounting types endpoint auth failed. Continuing without time accounting.")
                return []
            } catch {
                print("Time accounting types endpoint failed: \(error). Continuing without.")
                return []
            }
        }

        func fetchRolesGracefully() async -> [Role] {
            do {
                return try await fetchRoles()
            } catch APIError.serverError(let statusCode, _) where statusCode == 401 || statusCode == 403 || statusCode == 404 {
                print("Roles endpoint forbidden (\(statusCode)). Continuing without roles.")
                return []
            } catch APIError.authenticationFailed {
                print("Roles endpoint auth failed. Continuing without roles.")
                return []
            } catch {
                print("Roles endpoint failed: \(error). Continuing without roles.")
                return []
            }
        }

        func fetchGroupsGracefully() async -> [TicketGroup] {
            do {
                return try await fetchGroups()
            } catch APIError.serverError(let statusCode, _) where statusCode == 401 || statusCode == 403 || statusCode == 404 {
                print("Groups endpoint forbidden (\(statusCode)). Continuing without groups.")
                return []
            } catch APIError.authenticationFailed {
                print("Groups endpoint auth failed. Continuing without groups.")
                return []
            } catch {
                print("Groups endpoint failed: \(error). Continuing without groups.")
                return []
            }
        }

        func fetchOrganizationsGracefully() async -> [Organization] {
            do {
                return try await fetchOrganizations()
            } catch APIError.serverError(let statusCode, _) where statusCode == 401 || statusCode == 403 || statusCode == 404 {
                print("Organizations endpoint forbidden (\(statusCode)). Continuing without organizations.")
                return []
            } catch APIError.authenticationFailed {
                print("Organizations endpoint auth failed. Continuing without organizations.")
                return []
            } catch {
                print("Organizations endpoint failed: \(error). Continuing without organizations.")
                return []
            }
        }

        func fetchAllUsersGracefully() async -> [User] {
            do {
                return try await fetchAllUsers()
            } catch APIError.serverError(let statusCode, _) where statusCode == 401 || statusCode == 403 || statusCode == 404 {
                print("Users endpoint forbidden (\(statusCode)). Continuing without user list.")
                return []
            } catch APIError.authenticationFailed {
                print("Users endpoint auth failed. Continuing without user list.")
                return []
            } catch {
                print("Users endpoint failed: \(error). Continuing without user list.")
                return []
            }
        }

        // MARK: - Attachments
        func downloadAttachment(ticketId: Int, articleId: Int, attachment: Attachment) async throws -> URL {
            let endpoint = "ticket_attachment/\(ticketId)/\(articleId)/\(attachment.id)"
            let request = try createRequest(for: endpoint)
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            if httpResponse.statusCode == 401 { throw APIError.authenticationFailed }
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.serverError(statusCode: httpResponse.statusCode, message: String(data: data, encoding: .utf8))
            }

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("zammad_attachments", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let fileURL = tempDir.appendingPathComponent("\(attachment.id)_\(attachment.filename)")
            try? FileManager.default.removeItem(at: fileURL)
            try data.write(to: fileURL, options: .atomic)
            return fileURL
        }
    }
