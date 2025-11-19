import SwiftUI

struct SetupWizardView: View {
    @State private var currentStep = 0
    
    @State private var serverURL = ""
    @State private var apiToken = ""
    @State private var enableBiometrics = false
    @State private var enableNotifications = false
    
    @AppStorage("is_setup_complete") private var isSetupComplete: Bool = false
    
    @State private var isTestingConnection = false
    @State private var connectionTestResult: String?
    
    let totalSteps = 2

    var body: some View {
        VStack {
            TabView(selection: $currentStep) {
                serverStep.tag(0)
                permissionsStep.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            pageControl
        }
        .background(Color.black.ignoresSafeArea())
        .foregroundColor(.white)
    }
    
    var serverStep: some View {
        VStack(spacing: 20) {
            Text("server_config_title".localized()).font(.largeTitle).bold()
            Text("server_config_message".localized()).multilineTextAlignment(.center)
            
            StyledSection(title: "server_url".localized()) {
                TextField("zammad_instance_url".localized(), text: $serverURL)
                    .keyboardType(.URL).autocapitalization(.none)
            }
            
            StyledSection(title: "api_token".localized()) {
                TextField("paste_api_token".localized(), text: $apiToken)
            }
            
            if isTestingConnection {
                ProgressView()
            } else if let result = connectionTestResult {
                Text(result)
                    .foregroundColor(result == "connection_successful".localized() ? .green : .red)
            }
            
            Spacer()
        }
        .padding()
    }
    
    var permissionsStep: some View {
        VStack(spacing: 20) {
            Text("permissions_title".localized()).font(.largeTitle).bold()
            Text("permissions_message".localized()).multilineTextAlignment(.center)
            
            StyledSection(title: "") {
                Toggle("enable_face_id".localized(), isOn: $enableBiometrics)
            }
            
            StyledSection(title: "") {
                Toggle("enable_notifications".localized(), isOn: $enableNotifications)
            }
            
            Spacer()
        }
        .padding()
    }
    
    var pageControl: some View {
        HStack {
            if currentStep > 0 {
                Button("previous_step".localized()) { withAnimation { currentStep -= 1 } }
            }
            Spacer()
            
            if currentStep == totalSteps - 1 {
                Button("finish_setup".localized()) { finishSetup() }
            } else {
                Button("next_step".localized()) {
                    if currentStep == 0 { testAndProceed() }
                    else { withAnimation { currentStep += 1 } }
                }
            }
        }
        .padding()
    }

    private func testAndProceed() {
        isTestingConnection = true
        connectionTestResult = nil
        Task {
            let success = await ZammadAPIService.shared.testConnection(url: serverURL, token: apiToken)
            if success {
                connectionTestResult = "connection_successful".localized()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    withAnimation { currentStep += 1 }
                }
            } else {
                connectionTestResult = "connection_failed".localized()
            }
            isTestingConnection = false
        }
    }

    private func finishSetup() {
            // 1. Sla server gegevens op
            SettingsManager.shared.save(serverURL: serverURL)
            SettingsManager.shared.save(token: apiToken)
            
            // 2. Sla beveiligingsvoorkeur op
            SettingsManager.shared.save(isLockEnabled: enableBiometrics)
            
            // 3. Sla notificatie voorkeur op
            SettingsManager.shared.save(areRealtimeNotificationsEnabled: enableNotifications)
            
            // 4. Als notificaties aan staan, start direct het registratieproces
            if enableNotifications {
                // HIER ZAT DE FOUT: Gebruik nu de nieuwe NotificationSetupManager
                NotificationSetupManager.shared.enableNotifications()
            }
            
            // 5. Klaar!
            isSetupComplete = true
        }
}

private extension String {
    static var permissions_title: String { "Permissions".localized() }
    static var permissions_message: String { "Grant permissions to enhance your app experience.".localized() }
    static var previous_step: String { "Previous".localized() }
}

