//
//  WatchTicketViewModel.swift
//  Zammad Helpdesk Watch App
//

import Foundation
import SwiftUI
import Combine

@MainActor
class WatchTicketViewModel: ObservableObject {
    @Published var tickets: [Ticket] = []
    @Published var ticketStates: [TicketState] = []
    @Published var ticketPriorities: [TicketPriority] = []
    @Published var allUsers: [User] = []
    @Published var roles: [Role] = []
    @Published var currentUser: User?
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiService = ZammadAPIService.shared
    
    enum FilterType: Hashable {
        case myTickets, unassigned, allOpen
        case byStatus(id: Int, name: String)
    }
    
    var agentUsers: [User] {
        guard let agentRoleID = roles.first(where: { $0.name == "Agent" })?.id else { 
            return [] 
        }
        return allUsers.filter { $0.role_ids?.contains(agentRoleID) ?? false }
    }
    
    // MARK: - Load Data
    
    func loadTickets(filter: FilterType) async {
        isLoading = true
        errorMessage = nil
        
        do {
            // Load metadata first if needed
            if currentUser == nil {
                try await loadMetadata()
            }
            
            // Fetch tickets based on filter
            tickets = try await fetchTickets(for: filter)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func loadMetadata() async throws {
        async let userTask = apiService.fetchCurrentUser()
        async let statesTask = apiService.fetchTicketStates()
        async let prioritiesTask = apiService.fetchTicketPriorities()
        async let usersTask = apiService.fetchAllUsers()
        async let rolesTask = apiService.fetchRoles()
        
        let (user, states, priorities, users, roles) = try await (
            userTask, statesTask, prioritiesTask, usersTask, rolesTask
        )
        
        self.currentUser = user
        self.ticketStates = states
        self.ticketPriorities = priorities
        self.allUsers = users
        self.roles = roles
    }
    
    private func fetchTickets(for filter: FilterType) async throws -> [Ticket] {
        guard let currentUser = currentUser else { return [] }
        
        switch filter {
        case .myTickets:
            return try await apiService.searchTickets(query: "owner_id:\(currentUser.id) AND state.name:(new OR open)")
        case .unassigned:
            return try await apiService.searchTickets(query: "owner_id:1 AND state.name:(new OR open)")
        case .allOpen:
            return try await apiService.searchTickets(query: "state.name:(new OR open)")
        case .byStatus(let id, _):
            return try await apiService.fetchTickets(byStatusId: id)
        }
    }
    
    // MARK: - Update Ticket
    
    func updateTicket(_ ticket: Ticket) async throws -> Bool {
        // Check if pending state requires pending_time
        let stateName = stateName(for: ticket.state_id)
        
        let formatter = ISO8601DateFormatter()
        
        if stateName.lowercased().contains("pending") && ticket.pending_time == nil {
            // For Watch, we'll set a default pending time of 1 hour from now
            let pendingTime = formatter.string(from: Date().addingTimeInterval(3600))
            let payload = TicketUpdatePayload(
                owner_id: ticket.owner_id,
                state_id: ticket.state_id,
                priority_id: ticket.priority_id,
                customer_id: ticket.customer_id,
                pending_time: pendingTime
            )
            _ = try await apiService.updateTicket(id: ticket.id, payload: payload)
            return true
        }
        
        let payload = TicketUpdatePayload(
            owner_id: ticket.owner_id,
            state_id: ticket.state_id,
            priority_id: ticket.priority_id,
            customer_id: ticket.customer_id,
            pending_time: nil
        )
        _ = try await apiService.updateTicket(id: ticket.id, payload: payload)
        return false
    }
    
    // MARK: - Helper Methods
    
    func userName(for userID: Int) -> String {
        if userID == 1 {
            return "unassigned".localized()
        }
        return allUsers.first(where: { $0.id == userID })?.fullname ?? "unknown".localized()
    }
    
    func stateName(for stateID: Int) -> String {
        ticketStates.first(where: { $0.id == stateID })?.name ?? "unknown".localized()
    }
    
    func localizedStatusName(for name: String) -> String {
        let normalizedName = name.replacingOccurrences(of: " ", with: "_").lowercased()
        let localizedKey = "status_\(normalizedName)"
        let localized = localizedKey.localized()
        return localized != localizedKey ? localized : name
    }
    
    func priorityName(for priorityID: Int) -> String {
        ticketPriorities.first(where: { $0.id == priorityID })?.name ?? "unknown".localized()
    }
    
    func statusColor(for stateID: Int) -> Color {
        guard let state = ticketStates.first(where: { $0.id == stateID }) else {
            return .gray
        }
        
        let name = state.name.lowercased()
        
        switch name {
        case let n where n.contains("new"):
            return .blue
        case let n where n.contains("open"):
            return .green
        case let n where n.contains("pending"):
            return .orange
        case let n where n.contains("closed"):
            return .gray
        default:
            return .gray
        }
    }
}
