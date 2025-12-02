import SwiftUI

struct TimeAccountingEditView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: TicketViewModel // Use ObservedObject if passed in, or keep StateObject if owning it
    let ticket: Ticket
    
    @State private var time: String = ""
    @State private var selectedTypeId: Int?
    // We remove manualTypeId because users cannot guess an ID integer.
    
    private var isSaveButtonDisabled: Bool {
        // Disable if no time is entered OR if we have types but none is selected
        if time.isEmpty { return true }
        if !viewModel.timeAccountingTypes.isEmpty && selectedTypeId == nil { return true }
        return false
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("time_accounting".localized())) {
                    
                    if viewModel.timeAccountingTypes.isEmpty {
                        // Better User Feedback than a text field
                        if viewModel.isLoading {
                            HStack {
                                Text("loading_activities".localized())
                                Spacer()
                                ProgressView()
                            }
                        } else {
                            Text("no_activities_found_check_admin".localized())
                                .foregroundColor(.red)
                                .font(.caption)
                        }
                    } else {
                        Picker("activity".localized(), selection: $selectedTypeId) {
                            // Add a placeholder if nothing is selected
                            if selectedTypeId == nil {
                                Text("select_activity".localized()).tag(nil as Int?)
                            }
                            ForEach(viewModel.timeAccountingTypes) { type in
                                Text(type.name).tag(type.id as Int?)
                            }
                        }
                    }
                    
                    TextField("time_in_hours".localized(), text: $time)
                        .keyboardType(.decimalPad)
                }
            }
            .navigationTitle("add_spent_time".localized())
            .navigationBarItems(leading: Button("cancel".localized(), action: { dismiss() }),
                                trailing: Button("save".localized(), action: save).disabled(isSaveButtonDisabled))
            // FIX: Watch for data changes if the API loads after the view appears
            .onAppear {
                setInitialType()
            }
            .onChange(of: viewModel.timeAccountingTypes) { _, _ in
                setInitialType()
            }
        }
    }
    
    private func setInitialType() {
        if selectedTypeId == nil, let first = viewModel.timeAccountingTypes.first {
            selectedTypeId = first.id
        }
    }
    
    private func save() {
        guard let typeId = selectedTypeId else { return }
        
        // FIX: Force comma to dot conversion for API compatibility
        let formattedTime = time.replacingOccurrences(of: ",", with: ".")
        
        Task {
            do {
                try await viewModel.addSpentTime(for: ticket, time: formattedTime, typeId: typeId)
                dismiss()
            } catch {
                print("Failed to add spent time: \(error.localizedDescription)")
            }
        }
    }
}
