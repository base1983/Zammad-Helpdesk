import SwiftUI

/// Hand a ticket off to a colleague: pick an engineer, send them a chat-style
/// message (stored as an internal note on the ticket) and optionally assign
/// the ticket in the same step. Zammad notifies the colleague via the mention
/// and/or the assignment.
struct TicketHandoffView: View {
    @ObservedObject var viewModel: TicketViewModel
    @Binding var ticket: Ticket
    @Environment(\.dismiss) private var dismiss

    @State private var selectedAgentID: Int?
    @State private var message = ""
    @State private var assignImmediately = true
    @State private var isSending = false
    @State private var errorMessage: String?

    /// Agents that can take the ticket: everyone but the current user and
    /// Zammad's built-in "nobody" user (id 1).
    private var availableAgents: [User] {
        viewModel.agentUsers
            .filter { $0.id != viewModel.currentUser?.id && $0.id != 1 && $0.active }
            .sorted { $0.fullname.localizedCaseInsensitiveCompare($1.fullname) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("handoff_engineer".localized())) {
                    Picker("handoff_select_engineer".localized(), selection: $selectedAgentID) {
                        Text("handoff_select_engineer".localized()).tag(nil as Int?)
                        ForEach(availableAgents) { agent in
                            Text(agent.fullname).tag(agent.id as Int?)
                        }
                    }
                }

                Section(header: Text("handoff_message".localized())) {
                    TextEditor(text: $message)
                        .frame(minHeight: 100)
                    if message.isEmpty {
                        Text("handoff_message_placeholder".localized())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section(footer: Text("handoff_assign_footer".localized())) {
                    Toggle("handoff_assign_immediately".localized(), isOn: $assignImmediately)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(action: send) {
                        HStack {
                            if isSending { ProgressView().padding(.trailing, 4) }
                            Text("handoff_send".localized())
                        }
                    }
                    .disabled(isSending || selectedAgentID == nil || message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("handoff_ticket".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) { dismiss() }
                }
            }
        }
    }

    private func send() {
        guard let agentID = selectedAgentID else { return }
        isSending = true
        errorMessage = nil

        Task {
            do {
                // 1. Prefer a direct chat message (with ticket reference) via the
                //    proxy. Falls back to an internal note + mention when the
                //    colleague isn't registered for chat.
                var sentViaChat = false
                if let currentUser = viewModel.currentUser {
                    do {
                        try await ChatService.shared.register(currentUser: currentUser)
                        let engineers = try await ChatService.shared.fetchEngineers()
                        if let partner = engineers.first(where: { $0.zammadUserId == agentID }) {
                            try await ChatService.shared.send(to: partner, body: message, ticket: ticket)
                            sentViaChat = true
                        }
                    } catch {
                        print("Chat handoff unavailable, falling back to internal note: \(error)")
                    }
                }

                if !sentViaChat {
                    let agentName = viewModel.userName(for: agentID)
                    let senderName = viewModel.currentUser?.fullname ?? ""
                    let noteBody = "@\(agentName)\n\(message)\n\n— \(senderName)"
                    try await viewModel.addInternalNote(for: ticket, with: noteBody)
                    await ZammadAPIService.shared.createMentionGracefully(ticketId: ticket.id, userId: agentID)
                }

                // 2. Assign, which also triggers Zammad's "assigned to you" notification.
                if assignImmediately {
                    var updatedTicket = ticket
                    updatedTicket.owner_id = agentID
                    let needsPendingTime = try await viewModel.updateTicket(updatedTicket)
                    if needsPendingTime {
                        errorMessage = "handoff_error_pending_time".localized()
                        isSending = false
                        return
                    }
                    ticket = updatedTicket
                }

                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSending = false
        }
    }
}
