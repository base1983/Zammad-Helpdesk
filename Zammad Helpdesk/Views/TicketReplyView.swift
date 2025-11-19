import SwiftUI

struct TicketReplyView: View {
    @ObservedObject var viewModel: TicketViewModel
    let ticket: Ticket
    let articleToReplyTo: TicketArticle?
        
    @State private var replyBody: String = ""
    @State private var isInternalNote = false
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            VStack {
                TextEditor(text: $replyBody)
                    .padding()
                    .border(Color.gray, width: 1)
                
                Toggle("internal_note_toggle".localized(), isOn: $isInternalNote)
                    .padding()
            }
            .navigationTitle("reply_to_ticket".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                    .toolbarButtonStyle()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: sendMessage) {
                        Image(systemName: "paperplane.fill")
                    }
                    .toolbarButtonStyle()
                }
            }
            .onAppear(perform: setupInitialReply)
        }
    }
    
    private func setupInitialReply() {
        guard let article = articleToReplyTo else { return }
        let quoteHeader = "\n\n--- \("on".localized()) \(article.created_at.formatted(date: .abbreviated, time: .shortened)) \(viewModel.userName(for: article.created_by_id)) \("wrote".localized()):\n>"
        let quotedBody = article.body.strippingHTML().replacingOccurrences(of: "\n", with: "\n> ")
        replyBody = quoteHeader + quotedBody
    }
    
    private func sendMessage() {
        Task {
            do {
                if isInternalNote {
                    try await viewModel.addInternalNote(for: ticket, with: replyBody)
                } else {
                    let recipient = viewModel.userName(for: ticket.customer_id)
                    try await viewModel.sendReply(for: ticket, with: replyBody, subject: ticket.title, recipient: recipient, articleToReplyTo: articleToReplyTo)
                }
                dismiss()
            } catch {
                print("Failed to send reply: \(error.localizedDescription)")
            }
        }
    }
}

