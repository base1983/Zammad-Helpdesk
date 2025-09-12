import SwiftUI

struct ContentView: View {
    @AppStorage("is_setup_complete") private var isSetupComplete: Bool = false
    
    @State private var showAnimation = true
    
    @StateObject private var viewModel = TicketViewModel()
    @StateObject private var authManager = AuthenticationManager()
    @Environment(\.scenePhase) var scenePhase
    
    @AppStorage("color_scheme_option") private var colorSchemeOption: String = SettingsManager.shared.loadTheme().rawValue
    
    var body: some View {
        ZStack {
            if isSetupComplete {
                mainAppView
                    .preferredColorScheme(getPreferredColorScheme())
            } else {
                setupFlowView
                    .preferredColorScheme(.dark)
            }
        }
    }
    
    @ViewBuilder
    private var mainAppView: some View {
        ZStack {
            if authManager.isUnlocked {
                TicketListView(viewModel: viewModel)
            } else {
                LockedView(onUnlock: { authManager.authenticate() })
            }
        }
        .onAppear {
            if isSetupComplete {
                authManager.authenticate()
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .inactive || newPhase == .background {
                authManager.lock()
            }
        }
        .onLongPressGesture {
            print("Resetting setup flow...")
            isSetupComplete = false
        }
    }
    
    @ViewBuilder
    private var setupFlowView: some View {
        ZStack {
            SetupWizardView()

            if showAnimation {
                SplashAnimationView {
                    withAnimation(.easeInOut(duration: 0.7)) {
                        showAnimation = false
                    }
                }
                .transition(.asymmetric(insertion: .identity, removal: .move(edge: .leading)))
            }
        }
    }
    
    private func getPreferredColorScheme() -> ColorScheme? {
        switch ColorSchemeOption(rawValue: colorSchemeOption) {
        case .light: .light
        case .dark: .dark
        default: nil
        }
    }
}

