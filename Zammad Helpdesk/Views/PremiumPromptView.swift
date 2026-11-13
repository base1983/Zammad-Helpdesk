import SwiftUI

/// Sheet that suggests Premium to a non-Premium user: what it brings, then
/// the same purchase section as in Settings, so there is one paywall.
struct PremiumPromptView: View {
    @Environment(\.dismiss) private var dismiss
    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    @AppStorage("are_ads_removed", store: Self.groupDefaults) private var areAdsRemoved: Bool = false

    private struct Benefit: Identifiable {
        let symbol: String
        let titleKey: String
        var id: String { titleKey }
    }

    private let benefits = [
        Benefit(symbol: "rectangle.slash", titleKey: "premium_benefit_no_ads"),
        Benefit(symbol: "bell.badge", titleKey: "premium_benefit_notifications"),
        Benefit(symbol: "app.badge", titleKey: "premium_benefit_badge"),
        Benefit(symbol: "clock.badge.exclamationmark", titleKey: "premium_benefit_sla"),
        Benefit(symbol: "heart", titleKey: "premium_benefit_support"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "crown.fill")
                                .font(.title)
                                .foregroundStyle(.yellow)
                            Text("premium_step_title".localized())
                                .font(.title2.bold())
                        }
                        Text("premium_prompt_message".localized())
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        ForEach(benefits) { benefit in
                            Label(benefit.titleKey.localized(), systemImage: benefit.symbol)
                                .font(.body)
                        }
                    }
                    .padding(.vertical, 6)
                }

                InAppPurchaseView()
            }
            .navigationTitle("premium_step_title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("not_now".localized()) { dismiss() }
                }
            }
            .onChange(of: areAdsRemoved) { _, isPremium in
                // Purchase or restore succeeded: the sheet has done its job.
                if isPremium { dismiss() }
            }
        }
    }
}
