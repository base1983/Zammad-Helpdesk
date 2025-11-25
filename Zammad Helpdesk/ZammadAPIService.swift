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
        if httpResponse.statusCode == 401 { throw APIError.authenticationFailed }
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8)
            if let errorBody { print("Server Error (\(httpResponse.statusCode)): \(errorBody)") }
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
        let request = try createRequest(for: "users")
        return try await fetchData(for: request)
    }
    
    func fetchRoles() async throws -> [Role] {
        let request = try createRequest(for: "roles")
        return try await fetchData(for: request)
    }
    
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
}

