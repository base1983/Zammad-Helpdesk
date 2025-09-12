import SwiftUI
import StoreKit

struct SetupWizardView: View {
    @AppStorage("is_setup_complete") private var isSetupComplete: Bool = false
    
    @State private var selection = 0
    
    @State private var serverURL = ""
    @State private var apiToken = ""
    @State private var isLockEnabled = false
    @State private var colorSchemeOption: ColorSchemeOption = .system
    @State private var notificationsEnabled = true
    @State private var newTicketNotificationsEnabled = true
    @State private var assignmentNotificationsEnabled = true
    @State private var replyNotificationsEnabled = true

    var body: some View {
        VStack {
            TabView(selection: $selection) {
                ServerStepView(serverURL: $serverURL, apiToken: $apiToken, selection: $selection).tag(0)
                AppearanceStepView(isLockEnabled: $isLockEnabled, colorSchemeOption: $colorSchemeOption, selection: $selection).tag(1)
                NotificationStepView(
                    notificationsEnabled: $notificationsEnabled,
                    newTicketNotificationsEnabled: $newTicketNotificationsEnabled,
                    assignmentNotificationsEnabled: $assignmentNotificationsEnabled,
                    replyNotificationsEnabled: $replyNotificationsEnabled,
                    selection: $selection
                ).tag(2)
                ProStepView(selection: $selection).tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .background(Color.black.ignoresSafeArea())
            .padding(.bottom, 40)

            
            if selection == 3 {
                Button("finish_setup".localized()) {
                    saveSettingsAndFinish()
                }
                .buttonStyle(.borderedProminent)
                .padding([.horizontal, .bottom])
            }
        }
        .tint(.glassAccent)
    }
    
    private func saveSettingsAndFinish() {
        SettingsManager.shared.save(serverURL: serverURL)
        SettingsManager.shared.save(token: apiToken)
        SettingsManager.shared.save(isLockEnabled: isLockEnabled)
        SettingsManager.shared.save(theme: colorSchemeOption)
        SettingsManager.shared.save(notificationsEnabled: notificationsEnabled)
        SettingsManager.shared.save(newTicketNotificationsEnabled: newTicketNotificationsEnabled)
        SettingsManager.shared.save(assignmentNotificationsEnabled: assignmentNotificationsEnabled)
        SettingsManager.shared.save(replyNotificationsEnabled: replyNotificationsEnabled)
        isSetupComplete = true
    }
}

private struct ServerStepView: View {
    @Binding var serverURL: String
    @Binding var apiToken: String
    @Binding var selection: Int
    var body: some View {
        VStack {
            Text("server_setup_title".localized()).font(.largeTitle).fontWeight(.bold).padding(.bottom)
            StyledSection(title: "server_configuration".localized()) {
                TextField("zammad_url".localized(), text: $serverURL, axis: .vertical)
                    .keyboardType(.URL)
                    .autocapitalization(.none)
                    .autocorrectionDisabled(true)
            }
            StyledSection(title: "api_configuration".localized()) {
                TextField("personal_access_token".localized(), text: $apiToken, axis: .vertical)
            }
            Spacer()
            Button("next_step".localized()) {
                withAnimation { selection = 1 }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 60)
        }.padding()
    }
}

private struct AppearanceStepView: View {
    @Binding var isLockEnabled: Bool
    @Binding var colorSchemeOption: ColorSchemeOption
    @Binding var selection: Int
    var body: some View {
        VStack {
            Text("security_and_appearance".localized()).font(.largeTitle).fontWeight(.bold).padding(.bottom)
            StyledSection(title: "security".localized()) {
                Toggle("secure_with_faceid".localized(), isOn: $isLockEnabled)
            }
            StyledSection(title: "appearance".localized()) {
                Picker("theme".localized(), selection: $colorSchemeOption) {
                    ForEach(ColorSchemeOption.allCases) { Text($0.rawValue.localized()).tag($0) }
                }.pickerStyle(.segmented)
            }
            Spacer()
            Button("next_step".localized()) {
                withAnimation { selection = 2 }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 60)
        }.padding()
    }
}

private struct NotificationStepView: View {
    @Binding var notificationsEnabled: Bool
    @Binding var newTicketNotificationsEnabled: Bool
    @Binding var assignmentNotificationsEnabled: Bool
    @Binding var replyNotificationsEnabled: Bool
    @Binding var selection: Int
    var body: some View {
        VStack {
            Text("notifications".localized()).font(.largeTitle).fontWeight(.bold).padding(.bottom)
            StyledSection(title: "fallback_notifications_title".localized()) {
                Toggle("enable_notifications".localized(), isOn: $notificationsEnabled)
                if notificationsEnabled {
                    Divider()
                    Toggle("new_tickets".localized(), isOn: $newTicketNotificationsEnabled)
                    Toggle("new_assignments".localized(), isOn: $assignmentNotificationsEnabled)
                    Toggle("customer_replies".localized(), isOn: $replyNotificationsEnabled)
                }
            }
            Spacer()
            Button("next_step".localized()) {
                withAnimation { selection = 3 }
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 60)
        }.padding()
    }
}

private struct ProStepView: View {
    @Binding var selection: Int
    @StateObject private var storeManager = StoreManager()
    var body: some View {
        VStack {
            Text("pro_subscription".localized()).font(.largeTitle).fontWeight(.bold).padding(.bottom)
            StyledSection(title: "remove_ads_and_support".localized()) {
                switch storeManager.subscriptionGroupStatus {
                case .subscribed, .inGracePeriod: Text("pro_subscriber_thanks".localized())
                default: purchaseButtons
                }
            }
            Spacer()
        }.padding()
    }
    
    @ViewBuilder
    private var purchaseButtons: some View {
        if storeManager.isLoadingProducts || storeManager.isTransactionInProgress {
            ProgressView().padding()
        } else if storeManager.monthlyProduct != nil || storeManager.yearlyProduct != nil {
            if let monthly = storeManager.monthlyProduct {
                Button("\(monthly.displayName) - \(monthly.displayPrice)/\("month".localized())") { Task { await storeManager.purchase(monthly) } }
                    .buttonStyle(.borderedProminent)
            }
            if let yearly = storeManager.yearlyProduct {
                Button("\(yearly.displayName) - \(yearly.displayPrice)/\("year".localized())") { Task { await storeManager.purchase(yearly) } }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            Text("could_not_load_subscriptions".localized()).foregroundColor(.secondary).padding()
        }
    }
}
