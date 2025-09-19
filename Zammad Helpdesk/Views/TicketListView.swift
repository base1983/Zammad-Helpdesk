import SwiftUI

struct TicketListView: View {
    @ObservedObject var viewModel: TicketViewModel
    @State private var isShowingSettings = false
    @AppStorage("are_ads_removed") private var areAdsRemoved: Bool = false
    @State private var navigationPath = NavigationPath()
    
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool
    
    @StateObject private var deepLinkManager = DeepLinkManager.shared
    
    private let adUnitID = "ca-app-pub-3940256099942544/2934735716"

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack(path: $navigationPath) {
                ScrollView {
                    LazyVStack(spacing: 16) {
                        ForEach(viewModel.displayTickets) { ticket in
                            NavigationLink(value: ticket) {
                                TicketRowView(
                                    ticket: ticket,
                                    stateName: viewModel.localizedStatusName(for: viewModel.stateName(for: ticket.state_id)),
                                    priorityName: viewModel.priorityName(for: ticket.priority_id)
                                )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding()
                }
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Ticket.self) { ticket in
                    TicketDetailView(ticketID: ticket.id, viewModel: viewModel)
                }
                .toolbar { navigationToolbar }
                .background(appBackground)
                .overlay(statusOverlay)
                .refreshable { await viewModel.refreshAllData() }
            }
            .tint(.glassAccent)
            .onAppear {
                if viewModel.currentUser == nil {
                    Task { await viewModel.refreshAllData() }
                }
            }
            .task(id: deepLinkManager.pendingTicketID) {
                // This task now handles the deep link when it changes.
                guard let ticketID = deepLinkManager.pendingTicketID else { return }
                // A small delay ensures the UI is ready before navigating.
                try? await Task.sleep(for: .milliseconds(250))
                handleDeepLink(for: ticketID)
                // Reset the pending ID so it doesn't trigger again.
                deepLinkManager.pendingTicketID = nil
            }
            .onChange(of: searchText) { _, newValue in
                if newValue.isEmpty {
                    viewModel.clearSearch()
                }
            }
            .sheet(isPresented: $isShowingSettings) {
                SettingsView { Task { await viewModel.refreshAllData() } }
            }
            
            if !areAdsRemoved {
                AdBannerView(adUnitID: adUnitID)
                    .frame(height: 50)
                    .background(.thinMaterial)
            }
        }
    }
    
    private func handleDeepLink(for ticketID: Int) {
        Task { [viewModel] in
            if let ticket = await viewModel.handleDeepLink(ticketID: ticketID) {
                // Ensure the navigation stack is clear before adding the new path.
                self.navigationPath.removeLast(self.navigationPath.count)
                self.navigationPath.append(ticket)
            }
        }
    }
    
    @ToolbarContentBuilder
    private var navigationToolbar: some ToolbarContent {
        if isSearchActive {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 10) {
                    settingsButton
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
                    
                    Button(action: {
                        withAnimation {
                            searchText = ""; viewModel.clearSearch(); isSearchActive = false; isSearchFieldFocused = false
                        }
                    }) {
                        Image(systemName: "xmark.circle").foregroundColor(.primary).imageScale(.large)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        } else {
            ToolbarItem(placement: .principal) {
                Text("helpdesk_tickets".localized())
                    .fontWeight(.bold)
            }
            ToolbarItem(placement: .navigationBarLeading) { settingsButton }
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    Button(action: { withAnimation { isSearchActive = true; isSearchFieldFocused = true } }) {
                        Image(systemName: "magnifyingglass").foregroundColor(.primary).imageScale(.large)
                    }
                    filterMenu
                }
            }
        }
    }
    
    private var appBackground: some View {
        Color(UIColor.systemGroupedBackground).ignoresSafeArea()
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
        } label: { Image(systemName: "line.3.horizontal.decrease.circle").foregroundColor(.primary).imageScale(.large) }
    }
    
    private var settingsButton: some View {
        Button(action: { isShowingSettings = true }) {
            Image(systemName: "gearshape").font(.system(size: 18, weight: .bold)).foregroundColor(.primary)
        }
    }
    
    private var loadingOverlay: some View {
        ZStack { Color(.systemBackground).opacity(0.8); ProgressView("loading_data".localized()).padding().background(Color(.secondarySystemBackground)).cornerRadius(10) }
    }
    
    private var emptyStateOverlay: some View {
        VStack { Image(systemName: "ticket").font(.largeTitle).foregroundColor(.secondary); Text("no_tickets_in_view".localized()).foregroundColor(.secondary) }
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

