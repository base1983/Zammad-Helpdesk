import SwiftUI

struct ContentView: View {
    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    @AppStorage("is_setup_complete", store: Self.groupDefaults) private var isSetupComplete: Bool = false
    @AppStorage("color_scheme_option", store: Self.groupDefaults) private var colorSchemeOption: String = SettingsManager.shared.loadTheme().rawValue
    @AppStorage("background_light_option", store: Self.groupDefaults) private var lightBackgroundOption: String = BackgroundOption.flowers.rawValue
    @AppStorage("background_dark_option", store: Self.groupDefaults) private var darkBackgroundOption: String = BackgroundOption.pebbles.rawValue
    @Environment(\.colorScheme) private var systemColorScheme
    @ObservedObject private var customWallpapers = CustomWallpaperStore.shared
    @ObservedObject private var adConsent = AdConsentManager.shared
    @AppStorage("are_ads_removed", store: Self.groupDefaults) private var areAdsRemoved: Bool = false

    @State private var showAnimation = true
    
    @StateObject private var viewModel = TicketViewModel()
    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.scenePhase) var scenePhase
    
    // Navigatie status
    @State private var ticketToShow: Ticket? = nil
    @State private var showDeepLinkedTicket = false
    @State private var isProcessingDeepLink = false
    
    var body: some View {
        ZStack {
            // 1. The Global Background (wallpaper image or solid color)
            GeometryReader { geo in
                switch resolvedBackgroundStyle {
                case .image(let name):
                    Image(name)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .clipped()
                case .color(let color):
                    color
                case .custom(let mode):
                    // Only reached when the photo exists; see resolvedBackgroundStyle.
                    if let image = customWallpapers.image(for: mode) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .clipped()
                    }
                }
            }
            .ignoresSafeArea()

            // 2. De basis app
            if isSetupComplete {
                mainAppView
                    .preferredColorScheme(getPreferredColorScheme())
                    .background(ClearBackgroundView())
            } else {
                setupFlowView
                    .preferredColorScheme(.dark)
                    .background(ClearBackgroundView())
            }
            
            // Laad-overlay tijdens het verwerken van een deep link
            if isProcessingDeepLink {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .tint(.white)
                    Text("Ticket ophalen...")
                        .font(.headline)
                        .foregroundColor(.white)
                }
                .padding(30)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.systemGray6).opacity(0.9)))
            }
        }
        // Luister naar het ticket ID
        .onReceive(DeepLinkManager.shared.$pendingTicketID) { newTicketID in
            if let ticketID = newTicketID, authManager.isUnlocked {
                handleDeepLinkInView(ticketID: ticketID)
            }
        }
    }
    
    @ViewBuilder
    private var mainAppView: some View {
        ZStack {
            if authManager.isUnlocked {
                TicketListContainerView(
                    viewModel: viewModel,
                    ticketToShow: $ticketToShow,
                    showDeepLinkedTicket: $showDeepLinkedTicket
                )
                .background(ClearBackgroundView())
                .sheet(isPresented: $showDeepLinkedTicket) {
                    NavigationView {
                        if let ticket = ticketToShow {
                            TicketDetailView(ticketID: ticket.id, viewModel: viewModel)
                        } else {
                            ProgressView("Ticket laden...")
                        }
                    }
                    .background(ClearBackgroundView())
                }
            } else {
                LockedView(onUnlock: { authManager.authenticate() })
            }
        }
        .onAppear {
            if isSetupComplete { 
                authManager.authenticate()
                configureAppearance()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if !authManager.isUnlocked {
                    authManager.authenticate()
                } else if let id = DeepLinkManager.shared.pendingTicketID {
                    handleDeepLinkInView(ticketID: id)
                } else {
                    showAppOpenAdIfAllowed()
                }
            case .inactive, .background:
                authManager.lock()
            @unknown default:
                break
            }
        }
        .onChange(of: authManager.isUnlocked) { _, isUnlocked in
            if isUnlocked, let ticketID = DeepLinkManager.shared.pendingTicketID {
                handleDeepLinkInView(ticketID: ticketID)
            } else if isUnlocked {
                // With the biometric lock on, "the app is open" only once
                // Face ID has let the user through.
                showAppOpenAdIfAllowed()
            }
        }
        .onChange(of: showsAds, initial: true) { _, showsAds in
            // Consent settled (or Premium lapsed): fetch the app open ad so it
            // is ready for the cold start and the next foreground.
            guard showsAds else { return }
            AppOpenAdManager.shared.preload()
            showAppOpenAdIfAllowed()
        }
    }

    /// Non-Premium users with settled consent get ads at all.
    private var showsAds: Bool { !areAdsRemoved && adConsent.canShowAds }

    /// Shows the app open ad on launch and on return to the foreground, but
    /// never over the lock screen, the setup wizard, or a ticket being opened
    /// from a push notification. The closure is re-evaluated by the manager
    /// when the ad lands a moment later on a cold start.
    private func showAppOpenAdIfAllowed() {
        let authManager = self.authManager
        AppOpenAdManager.shared.presentIfReady {
            (Self.groupDefaults?.bool(forKey: "is_setup_complete") ?? false)
                && !SettingsManager.shared.isPremium()
                && AdConsentManager.shared.canShowAds
                && authManager.isUnlocked
                && DeepLinkManager.shared.pendingTicketID == nil
        }
    }
    
    @ViewBuilder
    private var setupFlowView: some View {
        ZStack {
            SetupWizardView()
            if showAnimation {
                SplashAnimationView {
                    withAnimation(.easeInOut(duration: 0.7)) { showAnimation = false }
                }
                .transition(.asymmetric(insertion: .identity, removal: .move(edge: .leading)))
            }
        }
    }
    
    // De functie die de volgorde bepaalt: Laden -> Verversen -> Openen
    private func handleDeepLinkInView(ticketID: Int) {
        print("DEBUG: Start verwerking ticket \(ticketID)")
        
        withAnimation { isProcessingDeepLink = true }
        
        Task {
            await viewModel.refreshAllData()
            
            if let ticket = await viewModel.handleDeepLink(ticketID: ticketID) {
                await MainActor.run {
                    self.ticketToShow = ticket
                    self.showDeepLinkedTicket = true
                    DeepLinkManager.shared.pendingTicketID = nil
                    withAnimation { isProcessingDeepLink = false }
                }
            } else {
                print("DEBUG: Ticket niet gevonden.")
                await MainActor.run {
                    DeepLinkManager.shared.pendingTicketID = nil
                    withAnimation { isProcessingDeepLink = false }
                }
            }
        }
    }
    
    /// Resolves the background for the effective color scheme: the in-app theme
    /// override if one is set, otherwise the system appearance.
    private var backgroundOption: BackgroundOption {
        let effectiveScheme = getPreferredColorScheme() ?? systemColorScheme
        if effectiveScheme == .dark {
            return BackgroundOption(rawValue: darkBackgroundOption) ?? .pebbles
        } else {
            return BackgroundOption(rawValue: lightBackgroundOption) ?? .flowers
        }
    }

    /// The option's style, except that a custom photo whose file is missing
    /// (removed, restored from a backup without the container, …) falls back
    /// to the mode's default wallpaper instead of a blank screen.
    private var resolvedBackgroundStyle: BackgroundOption.Style {
        if case .custom(let mode) = backgroundOption.style, !customWallpapers.hasImage(for: mode) {
            return BackgroundOption.defaultOption(for: mode).style
        }
        return backgroundOption.style
    }

    private func getPreferredColorScheme() -> ColorScheme? {
        switch ColorSchemeOption(rawValue: colorSchemeOption) {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }
    
    private func configureAppearance() {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .forEach { windowScene in
                windowScene.windows.forEach { window in
                    window.backgroundColor = .clear
                }
            }
        
        UITableView.appearance().backgroundColor = .clear
        UITableViewCell.appearance().backgroundColor = .clear
        UICollectionView.appearance().backgroundColor = .clear
        UINavigationBar.appearance().backgroundColor = .clear
        UINavigationBar.appearance().setBackgroundImage(UIImage(), for: .default)
        UINavigationBar.appearance().shadowImage = UIImage()
    }
}
