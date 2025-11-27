import SwiftUI

struct TicketEditView: View {
    @ObservedObject var viewModel: TicketViewModel
    @Binding var ticket: Ticket
    
    @Environment(\.dismiss) var dismiss
    
    @State private var showPendingTimePicker = false
    @State private var isShowingCustomerSearch = false
    @State private var optionalCustomerId: Int? = nil
    @State private var pendingTime = Date()
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
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
            .sheet(isPresented: $showPendingTimePicker) {
                pendingTimePickerView
            }
            .sheet(isPresented: $isShowingCustomerSearch, onDismiss: {
                if let customerId = optionalCustomerId {
                    ticket.customer_id = customerId
                }
            }) {
                CustomerSearchView(selectedCustomerId: $optionalCustomerId, viewModel: viewModel)
            }
            .onAppear {
                optionalCustomerId = ticket.customer_id
            }
        }
    }

    @ViewBuilder
    private var detailsSection: some View {
        Section(header: Text("details_section_header".localized())) {
            TextField("ticket_title_placeholder".localized(), text: $ticket.title)
            
            HStack {
                Text("customer".localized())
                Spacer()
                Button(action: {
                    isShowingCustomerSearch = true
                }) {
                    HStack {
                        Text(viewModel.userName(for: ticket.customer_id))
                        Image(systemName: "chevron.up.chevron.down")
                    }
                }
                .buttonStyle(.plain)
            }
            
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
    
    @ViewBuilder
    private var pendingTimePickerView: some View {
        NavigationStack {
            VStack {
                DatePicker(
                    "select_pending_time".localized(),
                    selection: $pendingTime,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.graphical)
                .padding()
            }
            .navigationTitle("pending_time_title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized(), action: { showPendingTimePicker = false })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("done".localized(), action: {
                        saveTicket(pendingTime: pendingTime)
                        showPendingTimePicker = false
                    })
                }
            }
        }
    }

    private func saveTicket(pendingTime: Date? = nil) {
        Task {
            do {
                let needsPendingTime = try await viewModel.updateTicket(ticket, pendingTime: pendingTime)
                if needsPendingTime {
                    showPendingTimePicker = true
                } else {
                    dismiss()
                }
            } catch {
                self.error = error.localizedDescription
                print("Failed to update ticket: \(error.localizedDescription)")
            }
        }
    }
}

