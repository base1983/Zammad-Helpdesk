import SwiftUI

struct TicketRowView: View {
    let ticket: Ticket
    let customerName: String
    let stateName: String
    let priorityName: String
    let statusColor: Color
    let priorityColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(ticket.title)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
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
                
                Spacer()
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
    }
}

