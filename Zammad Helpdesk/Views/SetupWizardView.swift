import SwiftUI

enum AuthMethod: String, CaseIterable, Identifiable {
    case sso, password, token
    var id: Self { self }

    var label: String {
        switch self {
        case .sso: "auth_method_sso".localized()
        case .password: "auth_method_password".localized()
        case .token: "auth_method_token".localized()
        }
    }
}

struct SetupWizardView: View {
    @State private var currentStep = 0

    @State private var serverURL = ""
    @State private var apiToken = ""
    @State private var authMethod: AuthMethod = .sso
    @State private var username = ""
    @State private var password = ""
    @State private var isShowingSSOSheet = false
    @State private var enableBiometrics = false
    @State private var enableNotifications = false

    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    @AppStorage("is_setup_complete", store: Self.groupDefaults) private var isSetupComplete: Bool = false

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
        .background(.ultraThinMaterial, ignoresSafeAreaEdges: .all)
        .foregroundColor(.white)
        .sheet(isPresented: $isShowingSSOSheet) {
            SSOLoginView(serverURL: serverURL) { newToken in
                apiToken = newToken
                connectionTestResult = "connection_successful".localized()
            }
        }
    }

    var serverStep: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("server_config_title".localized()).font(.largeTitle).bold()
                Text("server_config_message".localized()).multilineTextAlignment(.center)

                StyledSection(title: "server_url".localized()) {
                    TextField("zammad_instance_url".localized(), text: $serverURL)
                        .keyboardType(.URL).autocapitalization(.none)
                }

                Picker("auth_method".localized(), selection: $authMethod) {
                    ForEach(AuthMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)

                switch authMethod {
                case .sso:
                    VStack(spacing: 12) {
                        Text("sso_explainer".localized())
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button {
                            isShowingSSOSheet = true
                        } label: {
                            Label("login_with_sso".localized(), systemImage: "globe")
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.blue)
                        .disabled(serverURL.isEmpty)

                        if !apiToken.isEmpty {
                            Label("sso_token_ready".localized(), systemImage: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal)
                case .password:
                    StyledSection(title: "username".localized()) {
                        TextField("username_placeholder".localized(), text: $username)
                            .autocapitalization(.none)
                            .textContentType(.username)
                    }
                    StyledSection(title: "password".localized()) {
                        SecureField("password_placeholder".localized(), text: $password)
                            .textContentType(.password)
                    }
                case .token:
                    StyledSection(title: "api_token".localized()) {
                        SecureField("paste_api_token".localized(), text: $apiToken)
                    }
                }

                if isTestingConnection {
                    ProgressView()
                } else if let result = connectionTestResult {
                    Text(result)
                        .multilineTextAlignment(.center)
                        .foregroundColor(result == "connection_successful".localized() ? .green : .red)
                        .padding(.horizontal)
                }

                Spacer(minLength: 20)
            }
            .padding()
        }
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
                .disabled(isTestingConnection)
            }
        }
        .padding()
    }

    private func testAndProceed() {
        if authMethod == .sso && apiToken.isEmpty {
            isShowingSSOSheet = true
            return
        }

        isTestingConnection = true
        connectionTestResult = nil
        Task {
            do {
                let tokenToTest: String
                switch authMethod {
                case .password:
                    guard !username.isEmpty, !password.isEmpty else {
                        await MainActor.run {
                            connectionTestResult = "please_fill_credentials".localized()
                            isTestingConnection = false
                        }
                        return
                    }
                    let tokenName = "iOS Helpdesk – \(UIDevice.current.name)"
                    let token = try await ZammadAPIService.shared.createAccessToken(
                        url: serverURL,
                        username: username,
                        password: password,
                        tokenName: tokenName
                    )
                    apiToken = token
                    tokenToTest = token
                case .token, .sso:
                    tokenToTest = apiToken
                }

                let success = await ZammadAPIService.shared.testConnection(url: serverURL, token: tokenToTest)
                await MainActor.run {
                    if success {
                        connectionTestResult = "connection_successful".localized()
                        password = ""
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                            withAnimation { currentStep += 1 }
                        }
                    } else {
                        connectionTestResult = "connection_failed".localized()
                    }
                    isTestingConnection = false
                }
            } catch APIError.authenticationFailed {
                await MainActor.run {
                    connectionTestResult = "login_failed".localized()
                    isTestingConnection = false
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isTestingConnection = false
                }
            }
        }
    }

    private func finishSetup() {
            SettingsManager.shared.save(serverURL: serverURL)
            SettingsManager.shared.save(token: apiToken)
            SettingsManager.shared.save(isLockEnabled: enableBiometrics)
            SettingsManager.shared.save(areRealtimeNotificationsEnabled: enableNotifications)

            if enableNotifications {
                NotificationSetupManager.shared.enableNotifications()
            }

            WatchConnectivityManager.shared.sendCredentialsToWatch()

            isSetupComplete = true
        }
}

private extension String {
    static var permissions_title: String { "Permissions".localized() }
    static var permissions_message: String { "Grant permissions to enhance your app experience.".localized() }
    static var previous_step: String { "Previous".localized() }
}
