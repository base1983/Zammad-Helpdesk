import SwiftUI

struct TicketDetailView: View {
    let ticketID: Int
    @ObservedObject var viewModel: TicketViewModel
    
    @State private var ticket: Ticket?
    @State private var articles: [TicketArticle] = []
    @State private var timeAccountings: [TimeAccounting] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var isShowingEditSheet = false
    @State private var isShowingReplySheet = false
    @State private var isShowingTimeSheet = false
    @State private var isShowingCustomerSearch = false
    @State private var optionalCustomerId: Int? = nil
    @State private var showPendingTimePicker = false
    @State private var pendingTime = Date()
    
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Group {
            if isLoading && ticket == nil {
                ProgressView("loading_ticket_details".localized())
            } else if let errorMessage = errorMessage {
                VStack {
                    Text(errorMessage).foregroundColor(.red)
                    Button("try_again".localized(), action: { Task { await loadDetails() } })
                }
            } else if let ticket = ticket {
                ticketContent(ticket)
            }
        }
        .task { await loadDetails() }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    Image(systemName: "chevron.left.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.primary, .thinMaterial)
                        .font(.title2)
                }
            }
            ToolbarItem(placement: .principal) {
                Text(ticket?.title ?? "").lineLimit(1).truncationMode(.tail)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    if viewModel.isTimeAccountingEnabled {
                        Button(action: { isShowingTimeSheet = true }) { Image(systemName: "clock") }
                    }
                    Button(action: { isShowingEditSheet = true }) { Image(systemName: "square.and.pencil") }
                    Button(action: { isShowingReplySheet = true }) { Image(systemName: "arrowshape.turn.up.left") }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let ticketBinding = Binding($ticket) {
                TicketEditView(viewModel: viewModel, ticket: ticketBinding)
            }
        }
        .sheet(isPresented: $isShowingReplySheet) {
            if let ticket = ticket {
                let mostRecentArticle = articles.max { $0.created_at < $1.created_at }
                TicketReplyView(viewModel: viewModel, ticket: ticket, articleToReplyTo: mostRecentArticle)
            }
        }
        .sheet(isPresented: $isShowingTimeSheet) {
            if let ticket = ticket {
                TimeAccountingEditView(viewModel: viewModel, ticket: ticket)
            }
        }
        .sheet(isPresented: $isShowingCustomerSearch, onDismiss: {
            if let customerId = optionalCustomerId, ticket?.customer_id != customerId {
                ticket?.customer_id = customerId
                Task { _ = await saveChanges() }
            }
        }) {
            CustomerSearchView(selectedCustomerId: $optionalCustomerId, viewModel: viewModel)
        }
        .sheet(isPresented: $showPendingTimePicker) {
            pendingTimePickerView
        }
    }
    
    @ViewBuilder
    private func ticketContent(_ ticket: Ticket) -> some View {
        List {
            Section(header: Text("details_section_header".localized()).font(.headline)) {
                detailRow(label: "ticket_number".localized(), value: "#\(ticket.number)")
                Button(action: {
                    optionalCustomerId = ticket.customer_id
                    isShowingCustomerSearch = true
                }) {
                    detailRow(label: "customer".localized(), value: viewModel.userName(for: ticket.customer_id))
                }
                .buttonStyle(.plain)
                
                NavigationLink {
                    if let ticketBinding = Binding($ticket) {
                        PickerEditView(
                            title: "status".localized(),
                            selection: ticketBinding.state_id,
                            items: viewModel.ticketStates,
                            displayName: { state in viewModel.localizedStatusName(for: state.name) },
                            onSave: { await saveChanges() }
                        )
                    }
                } label: {
                    detailRow(label: "status".localized(), value: viewModel.localizedStatusName(for: viewModel.stateName(for: ticket.state_id)))
                }
                
                NavigationLink {
                    if let ticketBinding = Binding($ticket) {
                        PickerEditView(
                            title: "priority".localized(),
                            selection: ticketBinding.priority_id,
                            items: viewModel.ticketPriorities,
                            displayName: { $0.name },
                            onSave: { await saveChanges() }
                        )
                    }
                } label: {
                    detailRow(label: "priority".localized(), value: viewModel.priorityName(for: ticket.priority_id))
                }
                
                NavigationLink {
                    if let ticketBinding = Binding($ticket) {
                        let owners = [User(id: 1, organization_id: nil, login: "", firstname: "unassigned".localized(), lastname: "", email: "", web: nil, phone: nil, fax: nil, mobile: nil, department: nil, street: nil, zip: nil, city: nil, country: nil, address: nil, vip: false, verified: false, active: true, note: nil, last_login: nil, source: nil, login_failed: 0, out_of_office: false, out_of_office_start_at: nil, out_of_office_end_at: nil, out_of_office_replacement_id: nil, preferences: UserPreferences(), role_ids: nil, organization_ids: nil, authorization_ids: nil, group_ids: nil, updated_by_id: 0, created_by_id: 0, created_at: Date(), updated_at: Date())] + viewModel.agentUsers
                        PickerEditView(
                            title: "owner".localized(),
                            selection: ticketBinding.owner_id,
                            items: owners,
                            displayName: { $0.fullname },
                            onSave: { await saveChanges() }
                        )
                    }
                } label: {
                    detailRow(label: "owner".localized(), value: viewModel.userName(for: ticket.owner_id))
                }
                
                if viewModel.isTimeAccountingEnabled {
                    detailRow(label: "time_spent".localized(), value: totalTimeSpent)
                }
                
                detailRow(label: "created_at".localized(), value: ticket.created_at.formatted())
            }
            
            Section(header: Text("communication_history".localized()).font(.headline)) {
                ForEach(articles.sorted(by: { $0.created_at > $1.created_at })) { article in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(viewModel.userName(for: article.created_by_id)).fontWeight(.semibold)
                            Spacer()
                            Text(article.created_at.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundColor(.secondary)
                        }
                        Text(article.body.strippingHTML()).padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var totalTimeSpent: String {
        let total = timeAccountings.reduce(0.0) { $0 + (Double($1.time_unit) ?? 0.0) }
        return "\(total) \("hours".localized())"
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).fontWeight(.semibold)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
    
    @ViewBuilder
    private var pendingTimePickerView: some View {
        NavigationStack {
            VStack {
                DatePicker("select_pending_time".localized(), selection: $pendingTime, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
            }
            .navigationTitle("pending_time_title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized(), action: {
                        showPendingTimePicker = false
                        Task { await loadDetails() }
                    })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("done".localized(), action: {
                        showPendingTimePicker = false
                        Task { _ = await saveChanges(pendingTime: pendingTime) }
                    })
                }
            }
        }
    }
    
    private func saveChanges(pendingTime: Date? = nil) async -> Bool {
        guard let ticketToUpdate = ticket else { return false }
        do {
            let needsPendingTime = try await viewModel.updateTicket(ticketToUpdate, pendingTime: pendingTime)
            if needsPendingTime {
                self.showPendingTimePicker = true
                return true // Keep PickerEditView open
            } else {
                await viewModel.refreshAllData()
                await loadDetails()
                return false // Dismiss PickerEditView
            }
        } catch {
            self.errorMessage = error.localizedDescription
            await loadDetails()
            return false // Dismiss PickerEditView
        }
    }
    
    private func loadDetails() async {
        if ticket == nil { isLoading = true }
        self.errorMessage = nil
        do {
            async let ticketTask = ZammadAPIService.shared.fetchTicket(id: ticketID)
            async let articlesTask = ZammadAPIService.shared.fetchArticles(for: ticketID)
            async let timeAccountingsTask = ZammadAPIService.shared.fetchTimeAccountingsGracefully(for: ticketID)
            
            let (ticketResult, articlesResult, timeAccountingsResult) = await (try ticketTask, try articlesTask, try timeAccountingsTask)
            
            self.ticket = ticketResult
            self.articles = articlesResult
            self.timeAccountings = timeAccountingsResult
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

