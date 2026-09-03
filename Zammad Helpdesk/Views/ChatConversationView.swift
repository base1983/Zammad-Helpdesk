import SwiftUI

/// One-on-one message thread with another engineer. Polls the proxy for new
/// messages every few seconds while the view is visible.
struct ChatConversationView: View {
    let partner: ChatUser
    @ObservedObject var viewModel: TicketViewModel
    @StateObject private var chatService = ChatService.shared

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?

    private let pollInterval: UInt64 = 5_000_000_000 // 5 seconds

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            messageBubble(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastID = messages.last?.id {
                        withAnimation { proxy.scrollTo(lastID, anchor: .bottom) }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            inputBar
        }
        .navigationTitle(partner.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitial()
            await pollLoop()
        }
    }

    // MARK: - Subviews

    private func messageBubble(_ message: ChatMessage) -> some View {
        let isMine = message.fromUserId == chatService.myChatUserId
        return VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            if let ticketId = message.ticketId {
                Button {
                    // Reuse the existing deep-link pipeline to open the ticket.
                    DeepLinkManager.shared.pendingTicketID = ticketId
                } label: {
                    Label(String(format: "chat_ticket_reference".localized(), message.ticketNumber ?? String(ticketId)), systemImage: "ticket")
                        .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Text(message.body)
                .padding(10)
                .background(isMine ? Color.accentColor.opacity(0.85) : Color(.systemGray5).opacity(0.9))
                .foregroundColor(isMine ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField("chat_message_placeholder".localized(), text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .padding(10)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))

            Button(action: send) {
                if isSending {
                    ProgressView()
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title)
                }
            }
            .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Data

    private func loadInitial() async {
        do {
            messages = try await chatService.fetchMessages(with: partner.id)
            await chatService.markRead(partnerId: partner.id)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollInterval)
            guard !Task.isCancelled else { return }
            if let new = try? await chatService.fetchMessages(with: partner.id, since: messages.last?.id), !new.isEmpty {
                messages.append(contentsOf: new)
                await chatService.markRead(partnerId: partner.id)
            }
        }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        errorMessage = nil
        Task {
            do {
                let message = try await chatService.send(to: partner.id, body: body)
                messages.append(message)
                draft = ""
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSending = false
        }
    }
}
