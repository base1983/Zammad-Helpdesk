import SwiftUI

struct TicketCreateView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var ticketViewModel: TicketViewModel
    
    @State private var title = ""
    @State private var selectedCustomerId: Int?
    @State private var articleBody = "Hi there,\n\n"
    @State private var selectedGroupId: Int?
    @State private var selectedAgentId: Int?
    @State private var selectedStateId: Int?
    @State private var selectedPriorityId: Int?
    @State private var tags = ""
    
    @State private var articleType = "note"
    private let articleTypes = ["note", "email"]
    
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var isShowingCustomerSearch = false
    
    var isFormValid: Bool {
        !title.isEmpty && selectedCustomerId != nil && !articleBody.isEmpty && selectedGroupId != nil && selectedStateId != nil && selectedPriorityId != nil
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("details".localized())) {
                    TextField("title".localized(), text: $title)
                    
                    HStack {
                        Text("customer".localized())
                        Spacer()
                        Button(action: {
                            isShowingCustomerSearch = true
                        }) {
                            HStack {
                                Text(selectedCustomerName)
                                    .foregroundColor(selectedCustomerId == nil ? .secondary : .primary)
                                Image(systemName: "chevron.up.chevron.down")
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    Picker("group".localized(), selection: $selectedGroupId) {
                        ForEach(ticketViewModel.groups) { group in
                            Text(group.name).tag(group.id as Int?)
                        }
                    }
                    
                    Picker("owner".localized(), selection: $selectedAgentId) {
                        Text("unassigned".localized()).tag(nil as Int?)
                        ForEach(ticketViewModel.agentUsers) { user in
                            Text(user.fullname).tag(user.id as Int?)
                        }
                    }
                }
                
                Section(header: Text("article".localized())) {
                    Picker("type".localized(), selection: $articleType) {
                        ForEach(articleTypes, id: \.self) { type in
                            Text(type.localized()).tag(type)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    
                    TextEditor(text: $articleBody)
                        .frame(height: 200)
                }

                Section(header: Text("classification".localized())) {
                    Picker("status".localized(), selection: $selectedStateId) {
                        ForEach(ticketViewModel.ticketStates) { state in
                            Text(ticketViewModel.localizedStatusName(for: state.name)).tag(state.id as Int?)
                        }
                    }
                    
                    Picker("priority".localized(), selection: $selectedPriorityId) {
                        ForEach(ticketViewModel.ticketPriorities) { priority in
                            Text(ticketViewModel.localizedPriorityName(for: priority.name)).tag(priority.id as Int?)
                        }
                    }
                    
                    TextField("tags".localized(), text: $tags)
                        .autocapitalization(.none)
                }
            }
            .navigationTitle("new_ticket".localized())
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("create".localized()) {
                        createTicket()
                    }
                    .disabled(!isFormValid)
                }
            }
            .onAppear {
                // Set default values based on the view model
                selectedGroupId = ticketViewModel.groups.first?.id
                selectedStateId = ticketViewModel.ticketStates.first(where: { $0.name.lowercased() == "new" })?.id ?? ticketViewModel.ticketStates.first?.id
                selectedPriorityId = ticketViewModel.ticketPriorities.first(where: { $0.name.lowercased() == "2 normal" })?.id ?? ticketViewModel.ticketPriorities.first?.id
                selectedCustomerId = ticketViewModel.currentUser?.id
            }
            .alert(isPresented: $showingAlert) {
                Alert(title: Text("error".localized()), message: Text(alertMessage), dismissButton: .default(Text("ok".localized())))
            }
            .sheet(isPresented: $isShowingCustomerSearch) {
                CustomerSearchView(selectedCustomerId: $selectedCustomerId, viewModel: ticketViewModel)
            }
        }
    }

    private var selectedCustomerName: String {
        if let customerId = selectedCustomerId {
            return ticketViewModel.userName(for: customerId)
        } else {
            return "select_customer".localized()
        }
    }
    
    private func createTicket() {
        guard let customerId = selectedCustomerId,
              let groupId = selectedGroupId,
              let stateId = selectedStateId,
              let priorityId = selectedPriorityId else {
            alertMessage = "please_fill_all_required_fields".localized()
            showingAlert = true
            return
        }
        
        Task {
            do {
                try await ticketViewModel.createTicket(
                    title: title,
                    groupId: groupId,
                    customerId: customerId,
                    stateId: stateId,
                    priorityId: priorityId,
                    ownerId: selectedAgentId,
                    tags: tags.isEmpty ? nil : tags,
                    articleBody: articleBody,
                    articleType: articleType
                )
                dismiss()
            } catch {
                alertMessage = "failed_to_create_ticket".localized() + ": \(error.localizedDescription)"
                showingAlert = true
            }
        }
    }
}

// A simple SearchBar view to be used within the Picker
struct SearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
            TextField("search".localized(), text: $text)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
            if !text.isEmpty {
                Button(action: { self.text = "" }) {
                    Image(systemName: "xmark.circle.fill")
                }
            }
        }
        .padding(.horizontal)
    }
}
