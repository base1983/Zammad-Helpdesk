//
//  WatchTicketListView.swift
//  Zammad Helpdesk Watch App
//

import SwiftUI

struct WatchTicketListView: View {
    @StateObject private var viewModel = WatchTicketViewModel()
    @State private var selectedFilter: WatchTicketViewModel.FilterType = .myTickets
    
    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    ProgressView("loading_data".localized())
                } else if let errorMessage = viewModel.errorMessage {
                    errorView(errorMessage)
                } else if viewModel.tickets.isEmpty {
                    emptyStateView
                } else {
                    ticketList
                }
            }
            .navigationTitle("tickets".localized())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("my_assigned_tickets".localized()) {
                            selectedFilter = .myTickets
                            Task { await viewModel.loadTickets(filter: .myTickets) }
                        }
                        Button("unassigned_tickets".localized()) {
                            selectedFilter = .unassigned
                            Task { await viewModel.loadTickets(filter: .unassigned) }
                        }
                        Button("all_open_tickets".localized()) {
                            selectedFilter = .allOpen
                            Task { await viewModel.loadTickets(filter: .allOpen) }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
        .task {
            await viewModel.loadTickets(filter: selectedFilter)
        }
    }
    
    private var ticketList: some View {
        List {
            ForEach(viewModel.tickets) { ticket in
                NavigationLink(destination: WatchTicketDetailView(
                    ticketID: ticket.id,
                    viewModel: viewModel
                )) {
                    WatchTicketRow(ticket: ticket, viewModel: viewModel)
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "ticket")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("no_tickets_in_view".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
    
    private func errorView(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text(message)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button("try_again".localized()) {
                Task { await viewModel.loadTickets(filter: selectedFilter) }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

struct WatchTicketRow: View {
    let ticket: Ticket
    @ObservedObject var viewModel: WatchTicketViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("#\(ticket.number)")
                .font(.caption2)
                .foregroundColor(.secondary)
            
            Text(ticket.title)
                .font(.footnote)
                .fontWeight(.semibold)
                .lineLimit(2)
            
            HStack {
                Label(viewModel.stateName(for: ticket.state_id), systemImage: "circle.fill")
                    .font(.caption2)
                    .foregroundColor(viewModel.statusColor(for: ticket.state_id))
                
                Spacer()
                
                Text(ticket.updated_at.timeAgoDisplay())
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
