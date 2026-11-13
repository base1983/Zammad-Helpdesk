import SwiftUI

struct TicketRowView: View {
    let ticket: Ticket
    let customerName: String
    let stateName: String
    let priorityName: String
    let statusColor: Color
    let priorityColor: Color
    @ObservedObject var viewModel: TicketViewModel
    @ObservedObject private var drafts = DraftManager.shared
    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    /// SLA information is a Premium feature.
    @AppStorage("are_ads_removed", store: Self.groupDefaults) private var isPremium: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if ReadStatusManager.shared.isUnread(ticket: ticket, currentUser: viewModel.currentUser) {
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 8, height: 8)
                }
                Text(ticket.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                if drafts.hasDraft(for: ticket.id) {
                    Image(systemName: "square.and.pencil")
                        .font(.caption)
                        .foregroundColor(.accentColor)
                        .accessibilityLabel("draft_indicator".localized())
                }
                Text("#\(ticket.number)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Text(customerName)
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack {
                Text(stateName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(statusColor) // Use solid color background
                    .foregroundColor(.black) // Use white text for high contrast
                    .clipShape(Capsule())
                
                Text(priorityName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(priorityColor) // Use solid color background
                    .foregroundColor(.black) // Use white text for high contrast
                    .clipShape(Capsule())

                // SLA: time to (or past) the nearest deadline. Only tickets
                // that fall under an SLA carry one, and only Premium sees it.
                if isPremium, let sla = ticket.slaStatus() {
                    Label(sla.shortText, systemImage: sla.symbolName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(sla.color)
                        .foregroundColor(.white)
                        .clipShape(Capsule())
                        .accessibilityLabel(sla.text)
                }

                Spacer()
            }
        }
        .padding()
        // Material, not Liquid Glass: every visible row would otherwise be
        // its own glass pass, and the HIG reserves glass for the control layer.
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
    }
}

