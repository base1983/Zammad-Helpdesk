import Foundation

enum APIError: Error, LocalizedError {
    case invalidResponse, decodingError, tokenNotSet, authenticationFailed, userNotFound, invalidURL
    case serverError(statusCode: Int)
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Ongeldig antwoord van de server."
        case .decodingError: "Kon de data van de server niet verwerken."
        case .tokenNotSet: "API token niet ingesteld. Ga naar Instellingen."
        case .authenticationFailed: "Authenticatie mislukt. Controleer je API-token."
        case .userNotFound: "Kon de huidige gebruiker niet vinden."
        case .invalidURL: "De ingestelde server URL is ongeldig."
        case .serverError(let code): "Serverfout: Status \(code)."
        }
    }
}

class ZammadAPIService {
    static let shared = ZammadAPIService()
    private init() {}

    private func getBaseURL() throws -> URL {
        var urlString = SettingsManager.shared.loadServerURL()
        if !urlString.lowercased().hasPrefix("http") { urlString = "https://" + urlString }
        if urlString.hasSuffix("/") { urlString.removeLast() }
        if !urlString.hasSuffix("/api/v1") { urlString += "/api/v1" }
        if !urlString.hasSuffix("/") { urlString += "/" }
        guard let url = URL(string: urlString) else { throw APIError.invalidURL }
        return url
    }
    
    private func createRequest(for endpoint: String, method: String = "GET") throws -> URLRequest {
        let baseURL = try getBaseURL()
        guard let url = URL(string: endpoint, relativeTo: baseURL) else { throw APIError.invalidURL }
        guard let apiToken = SettingsManager.shared.loadToken(), !apiToken.isEmpty else { throw APIError.tokenNotSet }
        var request = URLRequest(url: url, timeoutInterval: 120.0)
        request.httpMethod = method
        request.setValue("Token token=\(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }
    
    private func fetchData<T: Decodable>(for request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if httpResponse.statusCode == 401 { throw APIError.authenticationFailed }
        guard (200...299).contains(httpResponse.statusCode) else {
            if let errorBody = String(data: data, encoding: .utf8) { print("Server Error (\(httpResponse.statusCode)): \(errorBody)") }
            throw APIError.serverError(statusCode: httpResponse.statusCode)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            print("JSON Decoding Error for \(T.self): \(error)")
            throw APIError.decodingError
        }
    }
    
    func searchTickets(query: String) async throws -> [Ticket] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let endpoint = "tickets/search?query=\(encodedQuery)&expand=true&per_page=200"
        let request = try createRequest(for: endpoint)
        let tickets: [Ticket] = try await fetchData(for: request)
        return tickets.sorted { $0.created_at > $1.created_at }
    }
    
    func fetchTickets(byStatusId id: Int) async throws -> [Ticket] {
        let endpoint = "tickets/search?query=state_id:\(id)&expand=true&per_page=200"
        let request = try createRequest(for: endpoint)
        return try await fetchData(for: request)
    }

    func fetchOverviews() async throws -> [ZammadView] {
        let request = try createRequest(for: "overviews")
        return try await fetchData(for: request)
    }

    func executeOverview(id: Int) async throws -> [Ticket] {
        let idRequest = try createRequest(for: "overviews/\(id)/execute")
        let (idData, response) = try await URLSession.shared.data(for: idRequest)
        
        guard let httpResponse = response as? HTTPURLResponse, (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }
        
        struct TicketIdResponse: Codable { let tickets: [Int] }
        let ticketIds = try JSONDecoder().decode(TicketIdResponse.self, from: idData).tickets
        
        if ticketIds.isEmpty {
            return []
        }
        
        let idQuery = ticketIds.map(String.init).joined(separator: " OR ")
        return try await searchTickets(query: "id:(\(idQuery))")
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

