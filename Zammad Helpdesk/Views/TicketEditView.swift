import SwiftUI

struct TicketEditView: View {
    @ObservedObject var viewModel: TicketViewModel
    @Binding var ticket: Ticket
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            Form {
                detailsSection
                assignmentSection
            }
            .navigationTitle("edit_ticket".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .toolbarButtonStyle()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { saveTicket() }) {
                        Image(systemName: "checkmark")
                    }
                    .toolbarButtonStyle()
                }
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section(header: Text("details_section_header".localized())) {
            TextField("ticket_title_placeholder".localized(), text: $ticket.title)
            
            Picker("status_picker_label".localized(), selection: $ticket.state_id) {
                ForEach(viewModel.ticketStates) { state in
                    Text(viewModel.localizedStatusName(for: state.name)).tag(state.id)
                }
            }
            
            Picker("priority_picker_label".localized(), selection: $ticket.priority_id) {
                ForEach(viewModel.ticketPriorities) { priority in
                    Text(priority.name).tag(priority.id)
                }
            }
        }
    }
    
    @ViewBuilder
    private var assignmentSection: some View {
        Section(header: Text("assignment_section_header".localized())) {
            Picker("owner_picker_label".localized(), selection: $ticket.owner_id) {
                Text("unassigned".localized()).tag(1)
                ForEach(viewModel.agentUsers) { user in
                    Text(user.fullname).tag(user.id)
                }
            }
        }
    }

    private func saveTicket() {
        Task {
            do {
                try await viewModel.updateTicket(ticket)
                dismiss()
            } catch {
                print("Failed to update ticket: \(error.localizedDescription)")
            }
        }
    }
}

