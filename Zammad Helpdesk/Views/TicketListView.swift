import SwiftUI

struct TicketListContainerView: View {
    @ObservedObject var viewModel: TicketViewModel
    
    // 1. Accepteert de bindings van ContentView
    @Binding var ticketToShow: Ticket?
    @Binding var showDeepLinkedTicket: Bool
    
    @State private var isShowingSettings = false
    @AppStorage("are_ads_removed") private var areAdsRemoved: Bool = false
    
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool
    
    // Nodig voor de .onAppear check om dubbel laden te voorkomen
    @ObservedObject private var deepLinkManager = DeepLinkManager.shared
    
    private let adUnitID = "ca-app-pub-3940256099942544/2934735716"

    var body: some View {
        GeometryReader { geometry in
            NavigationStack {
                ZStack {
                    ticketList
                    statusOverlay
                }
                .navigationBarTitleDisplayMode(.inline)
                
                // 2. HERSTELDE DESTINATION (voor in-app lijst-tikken)
                // Deze vangt de 'NavigationLink(value: ticket)' op
                .navigationDestination(for: Ticket.self) { ticket in
                    TicketDetailView(ticketID: ticket.id, viewModel: viewModel)
                }
                
                // 3. NIEUWE DESTINATION (voor dieplink/push notificatie)
                // Deze luistert naar de binding van ContentView
                .navigationDestination(isPresented: $showDeepLinkedTicket) {
                    if let ticket = ticketToShow {
                        TicketDetailView(ticketID: ticket.id, viewModel: viewModel)
                    } else {
                        ProgressView()
                    }
                }
                .toolbar { navigationToolbar(width: geometry.size.width) }
                .toolbarBackground(.hidden, for: .navigationBar)
                .refreshable { await viewModel.refreshAllData() }
                .background {
                    Image("background")
                        .resizable()
                        .scaledToFill()
                        .ignoresSafeArea()
                }
                .overlay(alignment: .bottom) {
                    if !areAdsRemoved {
                        AdBannerView(adUnitID: adUnitID)
                            .frame(height: 50)
                            .background(.thinMaterial)
                    }
                }
            }
            .tint(.accentColor)
            .onAppear {
                // Deze logica is nog steeds correct om een raceconditie te voorkomen
                if deepLinkManager.pendingTicketID == nil && viewModel.currentUser == nil {
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
        }
    }
    
    private var ticketList: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.displayTickets) { ticket in
                    // Deze NavigationLink(value: ticket) vereist de .navigationDestination(for: Ticket.self)
                    NavigationLink(value: ticket) {
                        TicketRowView(
                            ticket: ticket,
                            customerName: viewModel.userName(for: ticket.customer_id),
                            stateName: viewModel.localizedStatusName(for: viewModel.stateName(for: ticket.state_id)),
                            priorityName: viewModel.priorityName(for: ticket.priority_id),
                            statusColor: viewModel.colorForStatus(named: viewModel.stateName(for: ticket.state_id)),
                            priorityColor: viewModel.colorForPriority(named: viewModel.priorityName(for: ticket.priority_id))
                        )
                        .foregroundColor(.primary)
                    }
                }
            }
            .padding()
        }
        .scrollContentBackground(.hidden)
    }
    
    // De 'handleDeepLink'-functie is hier correct verwijderd (wordt nu door ContentView gedaan)
    
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
                }) {
                    Image(systemName: "xmark")
                }
                .toolbarButtonStyle()
            }
        } else {
            ToolbarItem(placement: .principal) {
                Text(viewModel.activeFilter.displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
            }
            ToolbarItem(placement: .navigationBarLeading) { settingsButton }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { withAnimation { isSearchActive = true; isSearchFieldFocused = true } }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .toolbarButtonStyle()
                    
                    filterMenu
                }
            }
        }
    }
    
    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isLoading && viewModel.searchedTickets == nil {
            loadingOverlay
        } else if let errorMessage = viewModel.errorMessage {
            errorOverlay(message: errorMessage)
        } else if viewModel.displayTickets.isEmpty && !searchText.isEmpty {
             VStack {
                Image(systemName: "magnifyingglass").font(.largeTitle).foregroundColor(.secondary)
                Text("no_search_results".localized()).foregroundColor(.secondary)
            }
            .padding()
            .background(.thinMaterial)
            .cornerRadius(12)
        } else if viewModel.displayTickets.isEmpty {
            emptyStateOverlay
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
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .toolbarButtonStyle()
        }
    }
    
    private var settingsButton: some View {
        Button(action: { isShowingSettings = true }) {
            Image(systemName: "gearshape")
        }
        .toolbarButtonStyle()
    }
    
    private var loadingOverlay: some View {
        ZStack {
            ProgressView("loading_data".localized())
                .padding(30)
                .background(.thinMaterial)
                .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var emptyStateOverlay: some View {
        VStack {
            Image(systemName: "ticket").font(.largeTitle)
            Text("no_tickets_in_view".localized())
        }
        .foregroundColor(.secondary)
        .padding(30)
        .background(.thinMaterial)
        .cornerRadius(12)
    }
    
    private func errorOverlay(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundColor(.red)
            Text("error".localized()).font(.headline)
            Text(message).multilineTextAlignment(.center).padding(.horizontal)
            Button(message == APIError.tokenNotSet.errorDescription ? "open_settings".localized() : "try_again".localized()) {
                if message == APIError.tokenNotSet.errorDescription { isShowingSettings = true }
                else { Task { await viewModel.refreshAllData() } }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top)
        }
        .padding(30)
        .background(.thinMaterial)
        .cornerRadius(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
