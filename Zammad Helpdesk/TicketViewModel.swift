import Foundation
import Combine

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
    
    // Publieke functies
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

    // DE OPLOSSING: De filterlogica is herschreven om een correcte, dynamische zoekopdracht te bouwen.
    private func fetchTickets(for filter: FilterType) async throws -> [Ticket] {
        // Bouw een dynamische query voor alle "open" statussen.
        let openStateIDs = ticketStates.filter { !["closed", "gesloten"].contains($0.name.lowercased()) }.map { String($0.id) }
        
        // Als er geen open statussen zijn, kunnen we geen tickets vinden.
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
    
    func handleDeepLink(ticketID: Int) async -> Ticket? {
        if currentUser == nil { await refreshAllData() }
        do {
            return try await apiService.fetchTicket(id: ticketID)
        } catch {
            print("Failed to fetch ticket for deep link: \(error)")
            errorMessage = "could_not_load_ticket".localized()
            return nil
        }
    }
    
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
}

