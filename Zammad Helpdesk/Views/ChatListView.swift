import SwiftUI

/// Standalone chat: list of conversations with other engineers on the same
/// Zammad instance, delivered via the notification proxy.
struct ChatListView: View {
    @ObservedObject var viewModel: TicketViewModel
    @StateObject private var chatService = ChatService.shared

    @State private var conversations: [ChatConversation] = []
    @State private var engineers: [ChatUser] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingNewChat = false
    @State private var selectedPartner: ChatUser?

    var body: some View {
        Group {
            if isLoading && conversations.isEmpty {
                ProgressView()
            } else if let errorMessage, conversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.exclamationmark.bubble.right")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("try_again".localized()) { Task { await load() } }
                        .buttonStyle(.bordered)
                }
                .padding(30)
            } else if conversations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("chat_no_conversations".localized())
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(30)
            } else {
                conversationList
            }
        }
        .navigationTitle("chat".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { isShowingNewChat = true }) {
                    Image(systemName: "square.and.pencil")
                }
                .disabled(engineers.isEmpty)
            }
        }
        .confirmationDialog("chat_new_message".localized(), isPresented: $isShowingNewChat, titleVisibility: .visible) {
            ForEach(engineers) { engineer in
                Button(engineer.name) { selectedPartner = engineer }
            }
        }
        .navigationDestination(item: $selectedPartner) { partner in
            ChatConversationView(partner: partner, viewModel: viewModel)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var conversationList: some View {
        List(conversations) { conversation in
            Button {
                selectedPartner = conversation.partner
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "person.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.partner.name)
                            .font(.headline)
                        if let last = conversation.lastMessage {
                            Text(last.body)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        if let last = conversation.lastMessage {
                            Text(last.createdAt.formatted(date: .omitted, time: .shortened))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        if conversation.unreadCount > 0 {
                            Text("\(conversation.unreadCount)")
                                .font(.caption2.bold())
                                .foregroundColor(.white)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Circle().fill(Color.red))
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func load() async {
        errorMessage = nil
        do {
            guard let currentUser = viewModel.currentUser else { throw ChatError.notRegistered }
            try await chatService.register(currentUser: currentUser)
            async let conversationsTask = chatService.fetchConversations()
            async let engineersTask = chatService.fetchEngineers()
            conversations = try await conversationsTask
            engineers = try await engineersTask
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }
}
