import SwiftUI

struct TicketListContainerView: View {
    @Binding var ticketToShow: Ticket?
    @Binding var showDeepLinkedTicket: Bool
    
    @ObservedObject var viewModel: TicketViewModel
    @ObservedObject private var readStatusManager = ReadStatusManager.shared
    
    @State private var isShowingCreateTicket = false
    @State private var isShowingSettings = false
    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    @AppStorage("are_ads_removed", store: Self.groupDefaults) private var areAdsRemoved: Bool = false
    
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool
    
    var deepLinkManager = DeepLinkManager.shared
    private let adUnitID = "ca-app-pub-3940256099942544/2934735716"

    init(viewModel: TicketViewModel, ticketToShow: Binding<Ticket?>, showDeepLinkedTicket: Binding<Bool>) {
        self.viewModel = viewModel
        self._ticketToShow = ticketToShow
        self._showDeepLinkedTicket = showDeepLinkedTicket
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                NavigationStack {
                    ZStack {
                        ticketList
                            .background(ClearBackgroundView())
                        statusOverlay
                    }
                    .background(ClearBackgroundView())
                    .navigationBarTitleDisplayMode(.inline)
                    .navigationDestination(for: Ticket.self) { ticket in
                        TicketDetailView(ticketID: ticket.id, viewModel: viewModel)
                    }
                    .toolbar { navigationToolbar(width: geometry.size.width) }
                    .toolbarBackground(.hidden, for: .navigationBar)
                }
                .background(ClearBackgroundView())
                
                if !areAdsRemoved {
                    AdBannerView(adUnitID: adUnitID, width: geometry.size.width)
                        .frame(height: 50)
                }
            }
            .background(ClearBackgroundView())
        }
        .background(ClearBackgroundView())
        .tint(.accentColor)
        .onAppear {
            if deepLinkManager.pendingTicketID == nil {
                Task { await viewModel.refreshAllData() }
            }
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty && isSearchActive {
                viewModel.clearSearch()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(onSave: { Task { await viewModel.refreshAllData() } })
        }
        .sheet(isPresented: $isShowingCreateTicket, onDismiss: {
            Task { await viewModel.refreshAllData() }
        }) {
            TicketCreateView(ticketViewModel: viewModel)
        }
    }
    
    private var ticketList: some View {
        List {
            ForEach(viewModel.displayTickets) { ticket in
                NavigationLink(value: ticket) {
                    TicketRowView(
                        ticket: ticket,
                        customerName: viewModel.userName(for: ticket.customer_id),
                        stateName: viewModel.localizedStatusName(for: viewModel.stateName(for: ticket.state_id)),
                        priorityName: viewModel.priorityName(for: ticket.priority_id),
                        statusColor: viewModel.colorForStatus(named: viewModel.stateName(for: ticket.state_id)),
                        priorityColor: viewModel.colorForPriority(named: viewModel.priorityName(for: ticket.priority_id)),
                        viewModel: viewModel
                    )
                }
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    swipeActions(for: ticket)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .refreshable { await viewModel.refreshAllData() }
    }
    
    @ViewBuilder
    private func swipeActions(for ticket: Ticket) -> some View {
        if readStatusManager.isUnread(ticket: ticket, currentUser: viewModel.currentUser) {
            Button(action: {
                readStatusManager.markAsRead(ticket: ticket)
                Task {
                    await viewModel.refreshAllData()
                    viewModel.updateApplicationBadge()
                }
            }) {
                Label("mark_read".localized(), systemImage: "envelope.open.fill")
            }
            .tint(.blue)
        } else {
            Button(action: {
                readStatusManager.markAsUnread(ticket: ticket)
                Task {
                    await viewModel.refreshAllData()
                    viewModel.updateApplicationBadge()
                }
            }) {
                Label("mark_unread".localized(), systemImage: "envelope.fill")
            }
            .tint(.orange)
        }
    }

    @ToolbarContentBuilder
    private func navigationToolbar(width: CGFloat) -> some ToolbarContent {
        if isSearchActive {
            ToolbarItem(placement: .principal) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                    TextField("search_placeholder".localized(), text: $searchText)
                        .focused($isSearchFieldFocused)
                        .onSubmit { Task { await viewModel.performSearch(query: searchText) } }
                    
                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(8).background(Color(.systemGray6)).cornerRadius(10)
                .frame(width: width * 0.7)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    withAnimation {
                        searchText = ""; viewModel.clearSearch(); isSearchActive = false; isSearchFieldFocused = false
                    }
                }) { Image(systemName: "xmark") }.toolbarButtonStyle()
            }
        } else {
            ToolbarItem(placement: .principal) {
                Text(viewModel.activeFilter.displayName).font(.title2).fontWeight(.bold).foregroundColor(.primary)
            }
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: { isShowingSettings = true }) { Image(systemName: "gearshape") }.toolbarButtonStyle()
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { isShowingCreateTicket = true }) { Image(systemName: "plus.circle") }.toolbarButtonStyle()
                    Button(action: { withAnimation { isSearchActive = true; isSearchFieldFocused = true } }) { Image(systemName: "magnifyingglass") }.toolbarButtonStyle()
                    filterMenu
                }
            }
        }
    }
    
    private var filterMenu: some View {
        Menu {
            Button("my_assigned_tickets".localized()) { Task { await viewModel.applyFilter(.myTickets) } }
            Button("unassigned_tickets".localized()) { Task { await viewModel.applyFilter(.unassigned) } }
            Button("all_open_tickets".localized()) { Task { await viewModel.applyFilter(.allOpen) } }
            if !viewModel.ticketStates.isEmpty {
                Divider()
                Text("filter_by_status".localized())
                ForEach(viewModel.ticketStates) { state in
                    Button(viewModel.localizedStatusName(for: state.name)) { Task { await viewModel.applyFilter(.byStatus(id: state.id, name: state.name)) } }
                }
            }
        } label: { Image(systemName: "line.3.horizontal.decrease.circle").toolbarButtonStyle() }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isLoading && viewModel.searchedTickets == nil {
            ProgressView("loading_data".localized()).padding(30).background(.thinMaterial).cornerRadius(12).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let errorMessage = viewModel.errorMessage {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.red)
                Text("error".localized()).font(.headline)
                Text(errorMessage).multilineTextAlignment(.center).padding(.horizontal)
                Button(errorMessage == APIError.tokenNotSet.errorDescription ? "open_settings".localized() : "try_again".localized()) {
                    if errorMessage == APIError.tokenNotSet.errorDescription { isShowingSettings = true }
                    else { Task { await viewModel.refreshAllData() } }
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
                .foregroundStyle(.white)
                .padding(.top)
            }.padding(30).background(.thinMaterial).cornerRadius(12).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.displayTickets.isEmpty {
            VStack {
                Image(systemName: searchText.isEmpty ? "ticket" : "magnifyingglass").font(.largeTitle)
                Text(searchText.isEmpty ? "no_tickets_in_view".localized() : "no_search_results".localized())
            }.foregroundColor(.secondary).padding(30).background(.thinMaterial).cornerRadius(12)
        }
    }
}
