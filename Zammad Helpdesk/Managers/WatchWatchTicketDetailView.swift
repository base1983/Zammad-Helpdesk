//
//  WatchTicketDetailView.swift
//  Zammad Helpdesk Watch App
//

import SwiftUI

struct WatchTicketDetailView: View {
    let ticketID: Int
    @ObservedObject var viewModel: WatchTicketViewModel
    
    @State private var ticket: Ticket?
    @State private var isLoading = true
    @State private var showingStatusPicker = false
    @State private var showingPriorityPicker = false
    @State private var showingOwnerPicker = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView("loading_ticket_details".localized())
            } else if let ticket = ticket {
                ticketDetails(ticket)
            } else {
                Text("ticket_not_found".localized())
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("#\(ticket?.number ?? "")")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadTicketDetail()
        }
    }
    
    @ViewBuilder
    private func ticketDetails(_ ticket: Ticket) -> some View {
        List {
            Section {
                Text(ticket.title)
                    .font(.headline)
            }
            
            Section("details_section_header".localized()) {
                HStack {
                    Text("customer".localized())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(viewModel.userName(for: ticket.customer_id))
                        .lineLimit(1)
                }
                
                Button {
                    showingStatusPicker = true
                } label: {
                    HStack {
                        Text("status".localized())
                            .foregroundColor(.secondary)
                        Spacer()
                        HStack(spacing: 4) {
                            Circle()
                                .fill(viewModel.statusColor(for: ticket.state_id))
                                .frame(width: 8, height: 8)
                            Text(viewModel.stateName(for: ticket.state_id))
                        }
                    }
                }
                
                Button {
                    showingPriorityPicker = true
                } label: {
                    HStack {
                        Text("priority".localized())
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.priorityName(for: ticket.priority_id))
                    }
                }
                
                Button {
                    showingOwnerPicker = true
                } label: {
                    HStack {
                        Text("owner".localized())
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(viewModel.userName(for: ticket.owner_id))
                            .lineLimit(1)
                    }
                }
            }
            
            Section {
                HStack {
                    Text("created_at".localized())
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(ticket.created_at.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                }
            }
        }
        .sheet(isPresented: $showingStatusPicker) {
            WatchStatusPickerView(
                ticket: Binding($ticket)!,
                viewModel: viewModel,
                onSave: { await saveTicket() }
            )
        }
        .sheet(isPresented: $showingPriorityPicker) {
            WatchPriorityPickerView(
                ticket: Binding($ticket)!,
                viewModel: viewModel,
                onSave: { await saveTicket() }
            )
        }
        .sheet(isPresented: $showingOwnerPicker) {
            WatchOwnerPickerView(
                ticket: Binding($ticket)!,
                viewModel: viewModel,
                onSave: { await saveTicket() }
            )
        }
    }
    
    private func loadTicketDetail() async {
        isLoading = true
        do {
            ticket = try await ZammadAPIService.shared.fetchTicket(id: ticketID)
        } catch {
            print("Error loading ticket: \(error)")
        }
        isLoading = false
    }
    
    private func saveTicket() async {
        guard let ticket = ticket else { return }
        do {
            _ = try await viewModel.updateTicket(ticket)
            await loadTicketDetail()
        } catch {
            print("Error saving ticket: \(error)")
        }
    }
}

struct WatchStatusPickerView: View {
    @Binding var ticket: Ticket
    @ObservedObject var viewModel: WatchTicketViewModel
    var onSave: () async -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.ticketStates) { state in
                    Button {
                        ticket.state_id = state.id
                        Task {
                            await onSave()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Circle()
                                .fill(viewModel.statusColor(for: state.id))
                                .frame(width: 8, height: 8)
                            Text(viewModel.localizedStatusName(for: state.name))
                            Spacer()
                            if ticket.state_id == state.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("status".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WatchPriorityPickerView: View {
    @Binding var ticket: Ticket
    @ObservedObject var viewModel: WatchTicketViewModel
    var onSave: () async -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.ticketPriorities) { priority in
                    Button {
                        ticket.priority_id = priority.id
                        Task {
                            await onSave()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text(priority.name)
                            Spacer()
                            if ticket.priority_id == priority.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("priority".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct WatchOwnerPickerView: View {
    @Binding var ticket: Ticket
    @ObservedObject var viewModel: WatchTicketViewModel
    var onSave: () async -> Void
    
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.agentUsers) { user in
                    Button {
                        ticket.owner_id = user.id
                        Task {
                            await onSave()
                            dismiss()
                        }
                    } label: {
                        HStack {
                            Text(user.fullname)
                            Spacer()
                            if ticket.owner_id == user.id {
                                Image(systemName: "checkmark")
                                    .foregroundColor(.accentColor)
                            }
                        }
                    }
                }
            }
            .navigationTitle("owner".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) {
                        dismiss()
                    }
                }
            }
        }
    }
}
