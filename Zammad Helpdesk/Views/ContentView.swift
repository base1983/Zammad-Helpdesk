import SwiftUI

struct ContentView: View {
    @AppStorage("is_setup_complete") private var isSetupComplete: Bool = false
    @AppStorage("color_scheme_option") private var colorSchemeOption: String = SettingsManager.shared.loadTheme().rawValue
    
    @State private var showAnimation = true
    
    @StateObject private var viewModel = TicketViewModel()
    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.scenePhase) var scenePhase
    
    // Navigatie status
    @State private var ticketToShow: Ticket? = nil
    @State private var showDeepLinkedTicket = false
    
    // NIEUW: Om te laten zien dat we bezig zijn met openen
    @State private var isProcessingDeepLink = false
    
    var body: some View {
        ZStack {
            // 1. The Global Background Image
            GeometryReader { geo in
                Image("Background")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
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
            
            // NIEUW: Een laad-overlay die verschijnt als we een ticket aan het openen zijn
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
                // 2. DE OPLOSSING: Open het ticket direct hier als een pop-up (sheet)
                                .sheet(isPresented: $showDeepLinkedTicket) {
                                    // CRUCIAAL: We wikkelen de view in een NavigationView.
                                    // Hierdoor worden de .toolbar knoppen in TicketDetailView zichtbaar en actief.
                                    NavigationView {
                                        if let ticket = ticketToShow {
                                            // We geven het ID door, precies zoals TicketDetailView verwacht
                                            TicketDetailView(ticketID: ticket.id, viewModel: viewModel)
                                        } else {
                                            // Fallback laadscherm
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
            if isSetupComplete { authManager.authenticate() }
            
            // Aggressive Window transparency fix
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .forEach { windowScene in
                    windowScene.windows.forEach { window in
                        window.backgroundColor = .clear
                    }
                }
            
            // Global fix for List and NavigationStack transparency
            UITableView.appearance().backgroundColor = .clear
            UITableViewCell.appearance().backgroundColor = .clear
            UICollectionView.appearance().backgroundColor = .clear
            
            // Target the navigation container area specifically
            UINavigationBar.appearance().backgroundColor = .clear
            UINavigationBar.appearance().setBackgroundImage(UIImage(), for: .default)
            UINavigationBar.appearance().shadowImage = UIImage()
        }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .active:
                if !authManager.isUnlocked { authManager.authenticate() }
                else if let id = DeepLinkManager.shared.pendingTicketID {
                    handleDeepLinkInView(ticketID: id)
                }
            case .inactive, .background:
                authManager.lock()
            @unknown default: break
            }
        }
        .onChange(of: authManager.isUnlocked) { _, isUnlocked in
            if isUnlocked, let ticketID = DeepLinkManager.shared.pendingTicketID {
                handleDeepLinkInView(ticketID: ticketID)
            }
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
        
        // Zet de laad-overlay AAN
        withAnimation { isProcessingDeepLink = true }
        
        Task {
            // STAP 1: Cache verversen (zodat je lijst up-to-date is)
            await viewModel.refreshAllData()
            
            // STAP 2: Specifiek ticket ophalen
            if let ticket = await viewModel.handleDeepLink(ticketID: ticketID) {
                await MainActor.run {
                    self.ticketToShow = ticket
                    self.showDeepLinkedTicket = true
                    
                    // Reset ID en zet laad-overlay UIT
                    DeepLinkManager.shared.pendingTicketID = nil
                    withAnimation { isProcessingDeepLink = false }
                }
            } else {
                print("DEBUG: Ticket niet gevonden.")
                // Ook bij falen de overlay uitzetten
                await MainActor.run {
                    DeepLinkManager.shared.pendingTicketID = nil
                    withAnimation { isProcessingDeepLink = false }
                }
            }
        }
    }
    
    private func getPreferredColorScheme() -> ColorScheme? {
        switch ColorSchemeOption(rawValue: colorSchemeOption) {
        case .light: return .light
        case .dark: return .dark
        default: return nil
        }
    }
}
