import SwiftUI
import StoreKit

struct TicketListContainerView: View {
    @Binding var ticketToShow: Ticket?
    @Binding var showDeepLinkedTicket: Bool
    
    @ObservedObject var viewModel: TicketViewModel
    @ObservedObject private var readStatusManager = ReadStatusManager.shared
    @ObservedObject private var chatService = ChatService.shared
    @ObservedObject private var adConsent = AdConsentManager.shared
    @State private var isAdLoaded = false
    /// Slots (1 = after the 10th ticket, 2 = after the 20th, …) whose in-list
    /// banner has actually received an ad; the others take no room.
    @State private var loadedListAdSlots: Set<Int> = []

    /// Drives the split view: the selected ticket fills the detail column in
    /// regular width (iPad, unfolded iPhone Duo) and is pushed in compact.
    @State private var selectedTicketID: Int?
    /// Portrait split layout only: whether the list is slid in over the ticket.
    @State private var isListOverlayShown = false
    /// Height of the status bar in this window, for the overlay's top inset.
    @State private var statusBarHeight: CGFloat = 0
    /// Hinge posture on foldable devices like iPhone Duo.
    /// When partially open, the screen splits 50/50 across the hinge.
    /// When fully open, the ticket list becomes smaller (~30%) and ticket details wider (~70%).
    @State private var isPartiallyOpen = false
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.requestReview) private var requestReview

    @State private var isShowingCreateTicket = false
    @State private var isShowingSettings = false
    @State private var isShowingChat = false
    @State private var isShowingPremiumPrompt = false
    @State private var ticketPendingSpam: Ticket?
    @State private var spamError: String?
    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    @AppStorage("are_ads_removed", store: Self.groupDefaults) private var areAdsRemoved: Bool = false
    
    @State private var searchText = ""
    @State private var isSearchActive = false
    @FocusState private var isSearchFieldFocused: Bool
    
    var deepLinkManager = DeepLinkManager.shared
    // Live banner unit. Debug builds keep Google's test unit: clicking your own
    // live ads is an AdMob policy violation, and test ads are what Google tells
    // you to develop against.
    #if DEBUG
    private let adUnitID = "ca-app-pub-3940256099942544/2934735716"
    #else
    private let adUnitID = "ca-app-pub-7428603098298858/7003691655"
    #endif
    /// Banner between tickets, one after every `ticketsPerAd` rows. Shares the
    /// unit with the bottom banner; give it its own AdMob unit if you want
    /// separate reporting for the two placements.
    private var listAdUnitID: String { adUnitID }
    private static let ticketsPerAd = 10

    /// Whether this user gets ads at all: not Premium, and UMP consent settled.
    private var showsAds: Bool { !areAdsRemoved && adConsent.canShowAds }

    /// One row of the ticket list: a ticket, or an ad slot between two groups
    /// of tickets. Ad slots have their own stable ids so a refresh that shifts
    /// tickets around does not tear the banners down and request them again.
    private enum ListEntry: Identifiable {
        case ticket(Ticket)
        case ad(slot: Int)

        var id: String {
            switch self {
            case .ticket(let ticket): return "ticket-\(ticket.id)"
            case .ad(let slot): return "ad-\(slot)"
            }
        }
    }

    /// Tickets with an ad slot after every tenth one — strictly *between*
    /// tickets, so a list of exactly ten (or twenty, …) does not end on an ad.
    private var listEntries: [ListEntry] {
        let tickets = viewModel.displayTickets
        guard showsAds else { return tickets.map { .ticket($0) } }
        var entries: [ListEntry] = []
        entries.reserveCapacity(tickets.count + tickets.count / Self.ticketsPerAd)
        for (index, ticket) in tickets.enumerated() {
            entries.append(.ticket(ticket))
            let position = index + 1
            if position.isMultiple(of: Self.ticketsPerAd) && position < tickets.count {
                entries.append(.ad(slot: position / Self.ticketsPerAd))
            }
        }
        return entries
    }

    init(viewModel: TicketViewModel, ticketToShow: Binding<Ticket?>, showDeepLinkedTicket: Binding<Bool>) {
        self.viewModel = viewModel
        self._ticketToShow = ticketToShow
        self._showDeepLinkedTicket = showDeepLinkedTicket
    }

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                // Two layouts, chosen by size class so an iPhone Duo switches
                // when folded or unfolded, not by device or orientation:
                // regular width puts list and ticket side by side (or, in
                // portrait, the ticket alone with the list sliding in on
                // demand), compact width pushes the ticket over the list.
                // Built by hand rather than with NavigationSplitView, which
                // caps its sidebar at roughly 44 % whatever width is
                // requested, paints its own panel over the wallpaper, and
                // adds a sidebar toggle.
                if horizontalSizeClass == .regular {
                    splitLayout(metrics: SplitMetrics(geometry: geometry, isPartiallyOpen: isPartiallyOpen))
                } else {
                    stackLayout(geometry: geometry)
                }

                // No banner until UMP consent is settled — requesting an ad
                // before that is exactly what Google's consent policy forbids.
                // The banner stays in the hierarchy so the SDK keeps trying,
                // but takes no room until an ad has actually arrived — an
                // empty strip is worse than no strip.
                if !areAdsRemoved && adConsent.canShowAds {
                    AdBannerView(adUnitID: adUnitID, width: geometry.size.width, isLoaded: $isAdLoaded)
                        .frame(height: isAdLoaded ? 50 : 0)
                        .clipped()
                }
            }
            .background(ClearBackgroundView())
        }
        // Outside the geometry reader on purpose: any sibling of the detail's
        // NavigationStack inherits its navigation bar as a top inset, which
        // pushed the overlay's header 80 pt down. The reader's own frame has
        // no such inset.
        .overlay(alignment: .leading) { listOverlay }
        .trackHingePosture(isPartiallyOpen: $isPartiallyOpen)
        .background(ClearBackgroundView())
        .tint(.accentColor)
        .onAppear {
            if deepLinkManager.pendingTicketID == nil {
                Task { await viewModel.refreshAllData() }
            }
            Task { await chatService.refreshUnreadCount() }
        }
        .onChange(of: showsAds, initial: true) { _, showsAds in
            // Have the Settings interstitial ready before the user asks for
            // it; the manager keeps one loaded from here on.
            if showsAds { InterstitialAdManager.shared.preload() }
        }
        .onReceive(DeepLinkManager.shared.$pendingChatPartnerID) { partnerID in
            // A chat push was tapped: open the chat screen; ChatListView picks
            // up the pending partner and opens the conversation.
            if partnerID != nil { isShowingChat = true }
        }
        .onChange(of: selectedTicketID) { oldValue, newValue in
            // Picking a ticket while the chat fills the detail column swaps
            // the chat out for the ticket, and in portrait the list slides
            // back out of the way.
            if newValue != nil {
                isShowingChat = false
                setListOverlay(false)
            }
            // Leaving a ticket (back, another ticket, or the chat) is the
            // moment to ask for a review, if enough tickets have been read,
            // or failing that to suggest Premium to a non-Premium user.
            // Never both at once.
            if oldValue != nil, !requestReviewIfEarned() {
                suggestPremiumIfDue()
            }
        }
        .sheet(isPresented: $isShowingPremiumPrompt) {
            PremiumPromptView()
        }
        .onChange(of: searchText) { _, newValue in
            if newValue.isEmpty && isSearchActive {
                viewModel.clearSearch()
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView(
                onSave: { Task { await viewModel.refreshAllData() } },
                onDisconnect: { viewModel.reset() }
            )
        }
        .sheet(isPresented: $isShowingCreateTicket, onDismiss: {
            Task { await viewModel.refreshAllData() }
        }) {
            TicketCreateView(ticketViewModel: viewModel)
        }
    }
    
    // MARK: - Layouts

    /// Regular width: two independent navigation stacks, the list on the
    /// left and the ticket (or chat, or placeholder) on the right, each
    /// exactly half of the available width.
    /// Sizes for the regular-width layout, derived from the *window*: the
    /// geometry proxy reports the safe-area-inset size, and the divider must
    /// sit at half of the window, so the insets are added back.
    private struct SplitMetrics {
        let fullWidth: CGFloat
        /// Taller than wide (iPad or unfolded Duo held upright): the ticket
        /// fills the window and the list slides in over it on demand.
        let isPortrait: Bool
        let listWidth: CGFloat

        init(geometry: GeometryProxy, isPartiallyOpen: Bool) {
            fullWidth = geometry.size.width + geometry.safeAreaInsets.leading + geometry.safeAreaInsets.trailing
            let fullHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            isPortrait = fullHeight > fullWidth
            // Landscape:
            // When partially open on an iPhone Duo, the hinge runs down the middle
            // of the device, so the left screen is the ticket list (50%) and the
            // right screen is the ticket details (50%).
            // When opened fully, the ticket list becomes smaller (~30%) and the
            // ticket details become wider (~70%).
            if isPortrait {
                listWidth = min(fullWidth * 0.6, 440)
            } else if isPartiallyOpen {
                listWidth = fullWidth * 0.5
            } else {
                listWidth = fullWidth * 0.3
            }
        }
    }

    /// Portrait split layout: the list slides in over the ticket from the
    /// left, as Mail does on iPad, over a dimmed backdrop that closes it.
    private var listOverlay: some View {
        GeometryReader { geometry in
            let metrics = SplitMetrics(geometry: geometry, isPartiallyOpen: isPartiallyOpen)
            if horizontalSizeClass == .regular && metrics.isPortrait && isListOverlayShown {
                ZStack(alignment: .leading) {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { setListOverlay(false) }
                        .transition(.opacity)

                    // The content safe area here starts below the detail's
                    // navigation bar, but iOS 26 draws that bar's buttons in
                    // the status-bar row. Mail's slide-in list aligns its
                    // header with that row, so inset by the status bar alone.
                    listColumn(width: metrics.listWidth)
                        .padding(.top, statusBarHeight)
                        .frame(width: metrics.listWidth)
                        .frame(maxHeight: .infinity)
                        .background { Rectangle().fill(.regularMaterial).ignoresSafeArea() }
                        .ignoresSafeArea(.container, edges: .top)
                        .shadow(color: .black.opacity(0.25), radius: 12, x: 4, y: 0)
                        .transition(.move(edge: .leading))
                }
                .ignoresSafeArea(.container, edges: .horizontal)
            }
        }
        .background(StatusBarHeightReader(height: $statusBarHeight))
        // The reader fills the screen; it must not swallow taps while hidden.
        .allowsHitTesting(isListOverlayShown)
    }

    private func splitLayout(metrics: SplitMetrics) -> some View {
        HStack(spacing: 0) {
            if !metrics.isPortrait {
                listColumn(width: metrics.listWidth)
                    .frame(width: metrics.listWidth)
            }

            NavigationStack {
                ticketDetailColumn(showsListButton: metrics.isPortrait)
            }
            .frame(maxWidth: .infinity)
            .background(ClearBackgroundView())
        }
        .background(ClearBackgroundView())
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: metrics.listWidth)
        .onChange(of: metrics.isPortrait, initial: true) { _, isPortrait in
            // Coming up in portrait with nothing to show on the right, offer
            // the list straight away instead of an empty placeholder.
            if isPortrait && selectedTicketID == nil && !isShowingChat {
                isListOverlayShown = true
            } else if !isPortrait {
                isListOverlayShown = false
            }
        }
    }

    /// The list with its header row. No NavigationStack: nothing is pushed
    /// here in the split layout, and SwiftUI gave a stack's toolbar items in
    /// this position a 48 pt floating strip that stacked them vertically. An
    /// explicit header row is deterministic.
    private func listColumn(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            splitListHeader(width: width)
            ZStack {
                ticketList(width: width)
                    .background(ClearBackgroundView())
                statusOverlay
            }
        }
        .background(ClearBackgroundView())
    }

    private func setListOverlay(_ shown: Bool) {
        withAnimation(.easeInOut(duration: 0.25)) { isListOverlayShown = shown }
    }

    /// Header of the list column in the split layout: the same controls as
    /// the compact toolbar (settings, filter name, actions, search), drawn
    /// as Liquid Glass buttons in a plain row.
    private func splitListHeader(width: CGFloat) -> some View {
        HStack(spacing: 12) {
            if isSearchActive {
                searchField(width: width * 0.6)
                Spacer(minLength: 0)
                Button(action: closeSearch) { Image(systemName: "xmark") }
                    .roundGlassButtonStyle()
            } else {
                Button(action: openSettings) { Image(systemName: "gearshape") }
                    .roundGlassButtonStyle()
                // Two lines rather than an ellipsis: the slide-in panel is
                // too narrow for the longer filter names on one line.
                Text(viewModel.activeFilter.displayName)
                    .font(.headline)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: 4) {
                    // Toolbar items are left unstyled for the system bar;
                    // in this hand-built header give them a fixed hit size.
                    Group { listActionButtons }
                        .frame(width: 36, height: 36)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .glassOrMaterialCapsule()
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 8)
    }

    /// The search field shown in place of the title while searching.
    private func searchField(width: CGFloat) -> some View {
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
        .frame(width: width)
    }

    private func closeSearch() {
        withAnimation {
            searchText = ""; viewModel.clearSearch(); isSearchActive = false; isSearchFieldFocused = false
        }
    }

    /// Chat (with unread badge), new ticket, search and filter. Shared by the
    /// compact toolbar and the split layout's header.
    @ViewBuilder
    private var listActionButtons: some View {
        // Unread messages show a red dot in the top right corner of the chat icon.
        Button(action: openChat) {
            Image(systemName: "bubble.left.and.bubble.right")
                .redDotBadge(isPresented: chatService.totalUnread > 0)
                .accessibilityLabel(chatService.totalUnread > 0
                    ? "\("chat".localized()) (\(chatService.totalUnread))"
                    : "chat".localized())
        }
        Button(action: { isShowingCreateTicket = true }) { Image(systemName: "plus.circle") }
        Button(action: { withAnimation { isSearchActive = true; isSearchFieldFocused = true } }) { Image(systemName: "magnifyingglass") }
        filterMenu
    }

    /// Compact width: one stack; the selected ticket and the chat are pushed
    /// over the list. Both pops clear the shared state, so a later switch to
    /// the split layout starts from the same selection.
    private func stackLayout(geometry: GeometryProxy) -> some View {
        NavigationStack {
            ticketListColumn(width: geometry.size.width, trailingInset: geometry.safeAreaInsets.trailing)
                .navigationDestination(isPresented: $isShowingChat) {
                    ChatListView(viewModel: viewModel, onClose: { isShowingChat = false })
                        .background(ClearBackgroundView())
                }
                .navigationDestination(item: $selectedTicketID) { ticketID in
                    TicketDetailView(
                        ticketID: ticketID,
                        viewModel: viewModel,
                        onBack: { selectedTicketID = nil }
                    )
                    .background(ClearBackgroundView())
                }
        }
        .background(ClearBackgroundView())
    }

    /// Compact width: the ticket list with its status overlay and a standard
    /// toolbar. The toolbar items are separate items on purpose: iOS keeps
    /// them in the top bar on an ordinary iPhone, and on the folded iPhone
    /// Duo it moves them into the strip beside the display, exactly as it
    /// does for the ticket detail's toolbar. A single item holding several
    /// buttons would not be split that way.
    private func ticketListColumn(width: CGFloat, trailingInset: CGFloat) -> some View {
        // The folded Duo's cover display has a strip along one edge, outside
        // the safe area, where iOS puts the toolbar buttons. The list's scroll
        // view runs under that strip, which parks the scroll indicator at the
        // far edge beyond the buttons.
        let hasSideStrip = trailingInset >= 44
        return ZStack {
            ticketList(width: width)
                // Measured on the device: with no margin UIKit ignores the
                // strip; with any non-zero margin it adds the strip's inset on
                // top. So this is only the gap from the strip's edge, and it
                // lands the indicator between the cards and the buttons.
                .contentMargins(.trailing, hasSideStrip ? 4 : 0, for: .scrollIndicators)
                .background(ClearBackgroundView())
            statusOverlay
        }
        .background(ClearBackgroundView())
        .navigationTitle(isSearchActive ? "" : viewModel.activeFilter.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { navigationToolbar(width: width) }
        .toolbarBackground(.hidden, for: .navigationBar)
    }

    /// Right-hand column of the split layout: the chat when it is open, else
    /// the selected ticket, else a placeholder. `id` forces a fresh detail
    /// view per ticket so its loading state does not leak between tickets.
    @ViewBuilder
    private func ticketDetailColumn(showsListButton: Bool) -> some View {
        Group {
            if isShowingChat {
                ChatListView(viewModel: viewModel, onClose: { isShowingChat = false }, closeSymbol: "xmark")
                    .background(ClearBackgroundView())
            } else if let selectedTicketID {
                TicketDetailView(
                    ticketID: selectedTicketID,
                    viewModel: viewModel,
                    showsBackButton: false
                )
                .id(selectedTicketID)
                .background(ClearBackgroundView())
            } else {
                ContentUnavailableView("no_ticket_selected".localized(), systemImage: "ticket")
                    // Centre on the whole column, not the safe-area box: the
                    // iPhone Duo's inner display insets one edge by 84 pt,
                    // which pushed the placeholder visibly off-centre.
                    .ignoresSafeArea(.container, edges: .horizontal)
                    // Hidden while the list covers it, otherwise a clipped
                    // tail of the text peeks out beside the panel.
                    .opacity(isListOverlayShown ? 0 : 1)
                    .background(ClearBackgroundView())
                    .toolbarBackground(.hidden, for: .navigationBar)
            }
        }
        .toolbar {
            // Portrait: the list is hidden, so every right-hand screen gets
            // the button that slides it in.
            if showsListButton {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { setListOverlay(true) }) {
                        Image(systemName: "sidebar.left")
                    }
                    .accessibilityLabel("show_ticket_list".localized())
                }
            }
        }
    }

    private func ticketList(width: CGFloat) -> some View {
        List {
            ForEach(listEntries) { entry in
                switch entry {
                case .ticket(let ticket):
                    ticketRow(for: ticket)
                case .ad(let slot):
                    listAdRow(slot: slot, width: width)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color.clear)
        .refreshable { await viewModel.refreshAllData() }
        .confirmationDialog(
            "close_as_spam_confirm_title".localized(),
            isPresented: Binding(
                get: { ticketPendingSpam != nil },
                set: { if !$0 { ticketPendingSpam = nil } }
            ),
            titleVisibility: .visible,
            presenting: ticketPendingSpam
        ) { ticket in
            Button("close_as_spam".localized(), role: .destructive) {
                Task {
                    do {
                        try await viewModel.closeAsSpam(ticket)
                    } catch {
                        spamError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    }
                }
            }
            Button("cancel".localized(), role: .cancel) {}
        } message: { ticket in
            Text("#\(ticket.number) · \(ticket.title)\n\("close_as_spam_confirm_message".localized())")
        }
        .alert("close_as_spam_failed".localized(), isPresented: Binding(
            get: { spamError != nil },
            set: { if !$0 { spamError = nil } }
        )) {
            Button("ok".localized(), role: .cancel) {}
        } message: {
            Text(spamError ?? "")
        }
    }

    private func ticketRow(for ticket: Ticket) -> some View {
        // A plain button, not a NavigationLink: tapping sets the shared
        // selection, which the split layout shows on the right and the stack
        // layout pushes. No chevron, no reserved space.
        Button {
            selectedTicketID = ticket.id
        } label: {
            TicketRowView(
                ticket: ticket,
                customerName: viewModel.userName(for: ticket.customer_id),
                stateName: viewModel.localizedStatusName(for: viewModel.stateName(for: ticket.state_id)),
                priorityName: viewModel.priorityName(for: ticket.priority_id),
                statusColor: viewModel.colorForStatus(named: viewModel.stateName(for: ticket.state_id)),
                priorityColor: viewModel.colorForPriority(named: viewModel.priorityName(for: ticket.priority_id)),
                viewModel: viewModel
            )
            .overlay {
                // Mark the open ticket when both columns are visible.
                if horizontalSizeClass == .regular && selectedTicketID == ticket.id {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            swipeActions(for: ticket)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            // Explicit tint: the list's accent tint is white in dark
            // mode, which would hide the white glyph.
            Button(role: .destructive) {
                ticketPendingSpam = ticket
            } label: {
                Label("spam".localized(), systemImage: "xmark.bin.fill")
            }
            .tint(.red)
        }
    }

    /// Screen-wide banner between two groups of tickets. Like the bottom
    /// banner it stays mounted so the SDK keeps trying, but collapses to
    /// nothing (no height, no insets) until an ad has actually arrived.
    private func listAdRow(slot: Int, width: CGFloat) -> some View {
        let bannerWidth = max(width, 0)
        let isLoaded = loadedListAdSlots.contains(slot)
        return AdBannerView(
            adUnitID: listAdUnitID,
            width: bannerWidth,
            isLoaded: Binding(
                get: { loadedListAdSlots.contains(slot) },
                set: { loaded in
                    if loaded { loadedListAdSlots.insert(slot) } else { loadedListAdSlots.remove(slot) }
                }
            )
        )
        .frame(height: isLoaded ? AdBannerView.height(forWidth: bannerWidth) : 0)
        .clipped()
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: isLoaded ? 8 : 0, leading: 0, bottom: isLoaded ? 8 : 0, trailing: 0))
    }

    /// Asks StoreKit for a rating once the user has opened and left enough
    /// tickets in this version, a moment after the pop animation so the
    /// request never lands mid-transition. StoreKit may still decide not to
    /// show anything; that is by design.
    @discardableResult
    private func requestReviewIfEarned() -> Bool {
        guard ReviewRequestManager.shared.consumeRequestIfEarned() else { return false }
        Task {
            try? await Task.sleep(for: .seconds(1))
            requestReview()
        }
        return true
    }

    /// Shows the Premium sheet to a non-Premium user every so many tickets,
    /// a moment after the pop animation. Premium users are never asked.
    private func suggestPremiumIfDue() {
        guard !areAdsRemoved, PremiumPromptManager.shared.consumePromptIfDue() else { return }
        Task {
            try? await Task.sleep(for: .seconds(1))
            isShowingPremiumPrompt = true
        }
    }

    /// Shows the chat: pushed in compact width, in the detail column in
    /// regular width. Clears the ticket selection so the list does not keep
    /// highlighting a ticket the detail column no longer shows.
    private func openChat() {
        selectedTicketID = nil
        isShowingChat = true
        setListOverlay(false)
    }

    /// Opens Settings, behind a full-screen interstitial for non-Premium users.
    /// The manager calls back immediately when no ad is ready, so Settings is
    /// never held hostage by a missing ad.
    private func openSettings() {
        guard showsAds else {
            isShowingSettings = true
            return
        }
        InterstitialAdManager.shared.present { isShowingSettings = true }
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
                searchField(width: width * 0.7)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: closeSearch) { Image(systemName: "xmark") }.toolbarButtonStyle()
            }
        } else {
            // Separate items, no HStack: see ticketListColumn. The title is
            // the navigation title, so the bar lays everything out itself.
            ToolbarItem(placement: .topBarLeading) {
                Button(action: openSettings) { Image(systemName: "gearshape") }
            }
            ToolbarItemGroup(placement: .topBarTrailing) {
                listActionButtons
            }
        }
    }
    
    private var filterMenu: some View {
        Menu {
            Button("my_assigned_tickets".localized()) { Task { await viewModel.applyFilter(.myTickets) } }
            Button("unassigned_tickets".localized()) { Task { await viewModel.applyFilter(.unassigned) } }
            Button("all_open_tickets".localized()) { Task { await viewModel.applyFilter(.allOpen) } }
            // SLA is Premium: the filter shows for everyone with a crown, and
            // for non-Premium users it opens the Premium sheet instead.
            Button {
                if areAdsRemoved {
                    Task { await viewModel.applyFilter(.escalated) }
                } else {
                    isShowingPremiumPrompt = true
                }
            } label: {
                if areAdsRemoved {
                    // "Escalated tickets (3)" while there are any.
                    Text(viewModel.escalatedCount > 0
                         ? "\("filter_escalated".localized()) (\(viewModel.escalatedCount))"
                         : "filter_escalated".localized())
                } else {
                    Label("filter_escalated".localized(), systemImage: "crown.fill")
                }
            }
            if !viewModel.ticketStates.isEmpty {
                Divider()
                Text("filter_by_status".localized())
                ForEach(viewModel.ticketStates) { state in
                    Button(viewModel.localizedStatusName(for: state.name)) { Task { await viewModel.applyFilter(.byStatus(id: state.id, name: state.name)) } }
                }
            }
        } label: {
            // Escalated tickets show a red dot in the top right corner of the filter icon.
            Image(systemName: "line.3.horizontal.decrease.circle")
                .redDotBadge(isPresented: areAdsRemoved && viewModel.escalatedCount > 0)
                .accessibilityLabel(areAdsRemoved && viewModel.escalatedCount > 0
                    ? "\("filter_escalated".localized()) (\(viewModel.escalatedCount))"
                    : "filter".localized())
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if viewModel.isLoading && viewModel.searchedTickets == nil {
            ProgressView("loading_data".localized()).padding(30).glassOrMaterial(cornerRadius: 12).frame(maxWidth: .infinity, maxHeight: .infinity)
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
            }.padding(30).glassOrMaterial(cornerRadius: 12).frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.displayTickets.isEmpty {
            VStack {
                Image(systemName: searchText.isEmpty ? "ticket" : "magnifyingglass").font(.largeTitle)
                Text(searchText.isEmpty ? "no_tickets_in_view".localized() : "no_search_results".localized())
            }.foregroundColor(.secondary).padding(30).glassOrMaterial(cornerRadius: 12)
        }
    }
}

/// Reports the height of the status bar in the window this view ends up in.
/// Read from the view's own window scene (not a global), and re-read on
/// layout so a rotation or a window resize is picked up.
private struct StatusBarHeightReader: UIViewRepresentable {
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> ReaderView {
        let view = ReaderView()
        view.onChange = { newHeight in
            if abs(height - newHeight) > 0.5 { height = newHeight }
        }
        return view
    }

    func updateUIView(_ uiView: ReaderView, context: Context) {}

    final class ReaderView: UIView {
        var onChange: ((CGFloat) -> Void)?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            report()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            report()
        }

        private func report() {
            guard let manager = window?.windowScene?.statusBarManager else { return }
            let newHeight = manager.statusBarFrame.height
            DispatchQueue.main.async { [onChange] in onChange?(newHeight) }
        }
    }
}


// MARK: - Hinge Observation

/// Observes hinge posture on foldable devices like iPhone Duo.
@available(iOS 27.1, *)
private struct HingeReader: UIViewRepresentable {
    @Binding var isPartiallyOpen: Bool

    func makeUIView(context: Context) -> HingeObservationView {
        let view = HingeObservationView()
        view.onPostureChange = { partiallyOpen in
            if isPartiallyOpen != partiallyOpen {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    isPartiallyOpen = partiallyOpen
                }
            }
        }
        return view
    }

    func updateUIView(_ uiView: HingeObservationView, context: Context) {}

    final class HingeObservationView: UIView {
        var onPostureChange: ((Bool) -> Void)?
        private var hingeInteraction: UIHingeInteraction?

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            let interaction = UIHingeInteraction { [weak self] _, update in
                let partiallyOpen = update.hinge?.status == .partiallyOpen
                DispatchQueue.main.async {
                    self?.onPostureChange?(partiallyOpen)
                }
            }
            addInteraction(interaction)
            self.hingeInteraction = interaction
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    }
}

private extension View {
    @ViewBuilder
    func trackHingePosture(isPartiallyOpen: Binding<Bool>) -> some View {
        if #available(iOS 27.1, *) {
            self
                .background(HingeReader(isPartiallyOpen: isPartiallyOpen))
                .onHingeChange { _, newContext in
                    let partiallyOpen = newContext.hinge?.status == .partiallyOpen
                    if isPartiallyOpen.wrappedValue != partiallyOpen {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            isPartiallyOpen.wrappedValue = partiallyOpen
                        }
                    }
                }
        } else {
            self
        }
    }
}


// MARK: - Red Dot Badge

/// Draws a small red notification dot in the top right corner of the view when presented.
private struct RedDotBadgeModifier: ViewModifier {
    let isPresented: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if isPresented {
                Circle()
                    .fill(Color.red)
                    .frame(width: 8, height: 8)
                    .offset(x: 2, y: -2)
                    .transition(.scale.combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
    }
}

private extension View {
    func redDotBadge(isPresented: Bool) -> some View {
        modifier(RedDotBadgeModifier(isPresented: isPresented))
    }
}
