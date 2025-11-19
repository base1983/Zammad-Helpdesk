import SwiftUI

struct WebhookGuideView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text("webhook_guide_intro".localized())
                    
                    guideStep(title: "webhook_guide_step1_title".localized(), body: "webhook_guide_step1_body".localized())
                    guideStep(title: "webhook_guide_step2_title".localized(), body: "webhook_guide_step2_body".localized())
                    guideStep(title: "webhook_guide_step3_title".localized(), body: "webhook_guide_step3_body".localized())
                    guideStep(title: "webhook_guide_step4_title".localized(), body: "webhook_guide_step4_body".localized())
                }
                .padding()
            }
            .navigationTitle("webhook_guide_title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "checkmark")
                    }
                    .toolbarButtonStyle()
                }
            }
        }
    }
    
    private func guideStep(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            Text(body)
                .foregroundColor(.secondary)
        }
    }
}

