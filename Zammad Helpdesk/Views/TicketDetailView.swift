import SwiftUI

struct TicketDetailView: View {
    let ticketID: Int
    @ObservedObject var viewModel: TicketViewModel
    
    @State private var ticket: Ticket?
    @State private var articles: [TicketArticle] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    
    @State private var isShowingEditSheet = false
    @State private var isShowingReplySheet = false
    
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Group {
            if isLoading {
                ProgressView("loading_ticket_details".localized())
                    .padding(30)
                    .background(.thinMaterial)
                    .cornerRadius(12)
            } else if let errorMessage = errorMessage {
                Text(errorMessage)
                    .padding(30)
                    .background(.thinMaterial)
                    .cornerRadius(12)
            } else if let ticket = ticket {
                ticketContent(ticket)
            }
        }
        .background(
            Image("background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        )
        .task { await loadDetails() }
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { dismiss() }) {
                    HStack {
                        Image(systemName: "chevron.left")
                    }
                }
                .toolbarButtonStyle()
            }
            ToolbarItem(placement: .principal) {
                Text(ticket?.title ?? "ticket_details_title".localized())
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { isShowingEditSheet = true }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .toolbarButtonStyle()
                    
                    Button(action: { isShowingReplySheet = true }) {
                        Image(systemName: "arrowshape.turn.up.left")
                    }
                    .toolbarButtonStyle()
                }
            }
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if self.ticket != nil {
                TicketEditView(viewModel: viewModel, ticket: Binding(
                    get: { self.ticket! },
                    set: { self.ticket = $0 }
                ))
            }
        }
        .sheet(isPresented: $isShowingReplySheet) {
            if let ticket = ticket {
                let mostRecentArticle = articles.max { $0.created_at < $1.created_at }
                TicketReplyView(viewModel: viewModel, ticket: ticket, articleToReplyTo: mostRecentArticle)
            }
        }
    }
    
    @ViewBuilder
    private func ticketContent(_ ticket: Ticket) -> some View {
        // We use a List to get the standard iOS grouped appearance.
        List {
            Section(header: Text("details_section_header".localized()).font(.headline)) {
                detailRow(label: "ticket_number".localized(), value: "#\(ticket.number)")
                detailRow(label: "customer".localized(), value: viewModel.userName(for: ticket.customer_id))
                
                // Status is now an interactive NavigationLink.
                NavigationLink {
                    if self.ticket != nil {
                        PickerEditView(
                            title: "status".localized(),
                            selection: Binding(get: { self.ticket!.state_id }, set: { self.ticket!.state_id = $0 }),
                            items: viewModel.ticketStates,
                            displayName: { state in viewModel.localizedStatusName(for: state.name) },
                            onSave: { saveChanges() }
                        )
                    }
                } label: {
                    detailRow(label: "status".localized(), value: viewModel.localizedStatusName(for: viewModel.stateName(for: ticket.state_id)))
                }
                
                // Priority is now an interactive NavigationLink.
                NavigationLink {
                    if self.ticket != nil {
                        PickerEditView(
                            title: "priority".localized(),
                            selection: Binding(get: { self.ticket!.priority_id }, set: { self.ticket!.priority_id = $0 }),
                            items: viewModel.ticketPriorities,
                            displayName: { $0.name },
                            onSave: { saveChanges() }
                        )
                    }
                } label: {
                    detailRow(label: "priority".localized(), value: viewModel.priorityName(for: ticket.priority_id))
                }
                
                // Owner is now an interactive NavigationLink.
                NavigationLink {
                    if self.ticket != nil {
                        // Create a temporary list for the picker that includes "Unassigned".
                        let owners = [User(id: 1, organization_id: nil, login: "", firstname: "unassigned".localized(), lastname: "", email: "", web: nil, phone: nil, fax: nil, mobile: nil, department: nil, street: nil, zip: nil, city: nil, country: nil, address: nil, vip: false, verified: false, active: true, note: nil, last_login: nil, source: nil, login_failed: 0, out_of_office: false, out_of_office_start_at: nil, out_of_office_end_at: nil, out_of_office_replacement_id: nil, preferences: UserPreferences(), role_ids: nil, organization_ids: nil, authorization_ids: nil, group_ids: nil, updated_by_id: 0, created_by_id: 0, created_at: Date(), updated_at: Date())] + viewModel.agentUsers
                        
                        PickerEditView(
                            title: "owner".localized(),
                            selection: Binding(get: { self.ticket!.owner_id }, set: { self.ticket!.owner_id = $0 }),
                            items: owners,
                            displayName: { $0.fullname },
                            onSave: { saveChanges() }
                        )
                    }
                } label: {
                    detailRow(label: "owner".localized(), value: viewModel.userName(for: ticket.owner_id))
                }
                
                detailRow(label: "created_at".localized(), value: ticket.created_at.formatted())
            }
            
            Section(header: Text("communication_history".localized()).font(.headline)) {
                ForEach(articles.sorted(by: { $0.created_at > $1.created_at })) { article in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(viewModel.userName(for: article.created_by_id))
                                .fontWeight(.semibold)
                            Spacer()
                            Text(article.created_at.formatted(date: .numeric, time: .shortened))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Text(article.body.strippingHTML())
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .listStyle(.insetGrouped)
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).fontWeight(.semibold)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }
    
    private func saveChanges() {
        Task {
            if let ticketToSave = ticket {
                try? await viewModel.updateTicket(ticketToSave)
            }
        }
    }
    
    private func loadDetails() async {
        isLoading = true
        do {
            let fetchedTicket = try await ZammadAPIService.shared.fetchTicket(id: ticketID)
            let fetchedArticles = try await ZammadAPIService.shared.fetchArticles(for: ticketID)
            
            self.ticket = fetchedTicket
            self.articles = fetchedArticles
            self.errorMessage = nil
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

