import Foundation
import Combine
import SwiftUI

@MainActor
class TicketViewModel: ObservableObject {
    @Published var currentTickets: [Ticket] = []
    @Published var searchedTickets: [Ticket]? = nil
    @Published var ticketStates: [TicketState] = []
    @Published var ticketPriorities: [TicketPriority] = []
    @Published var currentUser: User?
    @Published var allUsers: [User] = []
    @Published var roles: [Role] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var activeFilter: FilterType = .myTickets

    private let apiService = ZammadAPIService.shared
    private var loadingTask: Task<Void, Never>?

    var displayTickets: [Ticket] {
        return searchedTickets ?? currentTickets
    }

    enum FilterType: Hashable {
        case myTickets, unassigned, allOpen
        case byStatus(id: Int, name: String)
        
        var displayName: String {
            switch self {
            case .myTickets: "my_assigned_tickets".localized()
            case .unassigned: "unassigned_tickets".localized()
            case .allOpen: "all_open_tickets".localized()
            case .byStatus(_, let name): name
            }
        }
    }
    
    var agentUsers: [User] {
        guard let agentRoleID = roles.first(where: { $0.name == "Agent" })?.id else { return [] }
        return allUsers.filter { $0.role_ids?.contains(agentRoleID) ?? false }
    }
    
    // Public Functions
    func applyFilter(_ newFilter: FilterType) async {
        await loadData(filter: newFilter, isFullRefresh: false)
    }
    
    func refreshAllData() async {
        await loadData(filter: activeFilter, isFullRefresh: true)
    }
    
    func performSearch(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            clearSearch()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            searchedTickets = try await apiService.searchTickets(query: query)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func clearSearch() {
        searchedTickets = nil
    }

    private func loadData(filter: FilterType, isFullRefresh: Bool) async {
        loadingTask?.cancel()
        
        let task = Task {
            if isFullRefresh || currentUser == nil { self.isLoading = true }
            self.activeFilter = filter
            
            do {
                if isFullRefresh || currentUser == nil {
                    try await loadMetadata()
                }
                try Task.checkCancellation()
                
                let tickets = try await fetchTickets(for: filter)
                try Task.checkCancellation()

                self.currentTickets = tickets
                self.errorMessage = nil
                
            } catch {
                if !(error is CancellationError) {
                    print("Failed to load data: \(error)")
                    self.errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
            }
            
            if !Task.isCancelled {
                self.isLoading = false
            }
        }
        self.loadingTask = task
        await task.value
    }

    private func loadMetadata() async throws {
        async let data = (
            states: apiService.fetchTicketStates(),
            priorities: apiService.fetchTicketPriorities(),
            user: apiService.fetchCurrentUser(),
            allUsers: apiService.fetchAllUsers(),
            roles: apiService.fetchRoles()
        )
        let loaded = try await data
        (ticketStates, ticketPriorities, currentUser, allUsers, roles) = loaded
    }

    private func fetchTickets(for filter: FilterType) async throws -> [Ticket] {
        let openStateIDs = ticketStates.filter { !["closed", "gesloten"].contains($0.name.lowercased()) }.map { String($0.id) }
        
        guard !openStateIDs.isEmpty else { return [] }
        
        let openStatesQuery = "state_id:(\(openStateIDs.joined(separator: " OR ")))"
        
        switch filter {
        case .myTickets:
            guard let userId = self.currentUser?.id else { throw APIError.userNotFound }
            return try await apiService.searchTickets(query: "owner_id:\(userId) AND \(openStatesQuery)")
        
        case .unassigned:
            return try await apiService.searchTickets(query: "owner_id:1 AND \(openStatesQuery)")
        
        case .allOpen:
            return try await apiService.searchTickets(query: openStatesQuery)
        
        case .byStatus(let id, _):
            return try await apiService.fetchTickets(byStatusId: id)
        }
    }
    
    // Vervang je huidige handleDeepLink functie met deze slimme versie:
        func handleDeepLink(ticketID: Int) async -> Ticket? {
            print("DEBUG: DeepLink start voor ID/Nummer: \(ticketID)")
            
            // STAP 1: Check lokale cache (op Database ID)
            if let existingTicket = currentTickets.first(where: { $0.id == ticketID }) {
                print("DEBUG: Gevonden in cache op ID \(ticketID)")
                return existingTicket
            }
            
            // Zorg dat we rechten hebben/ingelogd zijn
            if currentUser == nil { await refreshAllData() }
            
            // STAP 2: Probeer te fetchen als Database ID (bijv. 486)
            do {
                let ticket = try await apiService.fetchTicket(id: ticketID)
                print("DEBUG: Direct opgehaald via API op ID \(ticketID)")
                return ticket
            } catch {
                print("DEBUG: Fetch op ID \(ticketID) mislukt. Fout: \(error).")
                print("DEBUG: We proberen nu te zoeken op Ticket NUMMER...")
                
                // STAP 3: FALLBACK - Het was waarschijnlijk een Ticket Nummer (bijv. 14478)
                // We zoeken via de search endpoint naar "number:14478"
                do {
                    // Let op: Zorg dat 'searchTickets' bestaat in je APIService
                    // De query zoekt specifiek naar het ticketnummer
                    let foundTickets = try await apiService.searchTickets(query: "number:\(ticketID)")
                    
                    if let firstMatch = foundTickets.first {
                        print("DEBUG: Gevonden via zoekopdracht op Nummer \(ticketID) (Echte ID: \(firstMatch.id))")
                        return firstMatch
                    } else {
                        print("DEBUG: Ook via zoeken niets gevonden.")
                    }
                } catch {
                    print("DEBUG: Zoekopdracht mislukt: \(error)")
                }
                
                // STAP 4: Als alles faalt, toon error
                await MainActor.run {
                    // We tonen nu het nummer in de foutmelding, handig voor debuggen!
                    self.errorMessage = "Kon ticket #\(ticketID) niet vinden (niet als ID en niet als nummer)."
                }
                return nil
            }
        }
    
    // MARK: - Update and Reply Logic
    func updateTicket(_ ticket: Ticket, pendingTime: Date? = nil) async throws -> Bool {
        var payload = TicketUpdatePayload(owner_id: ticket.owner_id, state_id: ticket.state_id, priority_id: ticket.priority_id, pending_time: nil)
        
        if let pendingTime = pendingTime {
            let formatter = ISO8601DateFormatter()
            payload.pending_time = formatter.string(from: pendingTime)
        }
        
        do {
            _ = try await apiService.updateTicket(id: ticket.id, payload: payload)
            await refreshAllData()
            return false // Success, no pending time needed
        } catch APIError.serverError(let statusCode, let message) {
            var isPendingTimeError = false
            if let msg = message, let data = msg.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
               let errorStr = json["error"] as? String {
                if errorStr.contains("Missing required value for field 'pending_time'") {
                    isPendingTimeError = true
                }
            }

            if statusCode == 422 && isPendingTimeError {
                return true // Pending time is required
            }
            
            throw APIError.serverError(statusCode: statusCode, message: message) // Re-throw other errors
        } catch {
            throw error // Re-throw other error types
        }
    }
    
    func sendReply(for ticket: Ticket, with body: String, subject: String, recipient: String, articleToReplyTo: TicketArticle?) async throws {
        let payload = ArticleCreationPayload(ticket_id: ticket.id, body: body, internal_note: false, to: recipient, subject: subject)
        _ = try await apiService.createArticle(payload: payload)
    }
    
    func addInternalNote(for ticket: Ticket, with body: String) async throws {
        let payload = ArticleCreationPayload(ticket_id: ticket.id, body: body, internal_note: true, to: "", subject: ticket.title)
        _ = try await apiService.createArticle(payload: payload)
    }

    // MARK: - Helper & Formatting Functions
    func stateName(for id: Int) -> String { ticketStates.first { $0.id == id }?.name ?? "unknown".localized() }
    func priorityName(for id: Int) -> String { ticketPriorities.first { $0.id == id }?.name ?? "unknown".localized() }
    func userName(for id: Int) -> String { allUsers.first { $0.id == id }?.fullname ?? "unassigned".localized() }
    
    func localizedStatusName(for statusName: String) -> String {
        switch statusName.lowercased() {
        case "new": "status_new".localized()
        case "pending reminder": "status_pending_reminder".localized()
        case "closed": "status_closed".localized()
        case "merged": "status_merged".localized()
        case "pending close": "status_pending_close".localized()
        default: statusName.prefix(1).capitalized + statusName.dropFirst()
        }
    }

    func colorForStatus(named name: String) -> Color {
        switch name.lowercased() {
        case "new": .green
        case "open": .yellow
        case "in behandeling": .yellow
        case "pending reminder", "pending close": .orange
        case "merged": .pink
        case "closed": .gray
        default: .secondary
        }
    }
    
    func colorForPriority(named name: String) -> Color {
        switch name.lowercased() {
        case "1 low": .green
        case "2 normal": .blue
        case "3 high": .red
        default: .secondary
        }
    }
}

