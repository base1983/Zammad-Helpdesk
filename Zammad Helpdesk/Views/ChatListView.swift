import SwiftUI

/// Standalone chat: list of direct and group conversations with other
/// engineers on the same Zammad instance, delivered via the notification proxy.
struct ChatListView: View {
    @ObservedObject var viewModel: TicketViewModel
    @StateObject private var chatService = ChatService.shared

    @State private var conversations: [ChatConversation] = []
    @State private var engineers: [ChatUser] = []
    @State private var groups: [ChatGroup] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isShowingNewChat = false
    @State private var isShowingNoEngineersAlert = false
    @State private var isShowingNewGroup = false
    @State private var selectedTarget: ChatTarget?

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
                Button(action: {
                    if engineers.isEmpty {
                        isShowingNoEngineersAlert = true
                    } else {
                        isShowingNewChat = true
                    }
                }) {
                    Image(systemName: "square.and.pencil")
                }
            }
        }
        .confirmationDialog("chat_new_message".localized(), isPresented: $isShowingNewChat, titleVisibility: .visible) {
            ForEach(engineers) { engineer in
                Button(engineer.name) { selectedTarget = .direct(engineer) }
            }
            Button("chat_new_group".localized()) { isShowingNewGroup = true }
        }
        .alert("chat".localized(), isPresented: $isShowingNoEngineersAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("chat_no_engineers".localized())
        }
        .sheet(isPresented: $isShowingNewGroup) {
            NewGroupChatView(engineers: engineers, viewModel: viewModel) { group in
                selectedTarget = .group(group)
                Task { await load() }
            }
        }
        .navigationDestination(item: $selectedTarget) { target in
            ChatConversationView(target: target, viewModel: viewModel)
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private var conversationList: some View {
        List(conversations) { conversation in
            Button {
                if let target = conversation.target { selectedTarget = target }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: conversation.group != nil ? "person.3.fill" : "person.circle.fill")
                        .font(conversation.group != nil ? .title2 : .largeTitle)
                        .foregroundStyle(.secondary)
                        .frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(conversation.partner?.name ?? conversation.group?.name ?? "")
                            .font(.headline)
                        if let last = conversation.lastMessage {
                            Text(previewText(for: last))
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

    private func previewText(for message: ChatMessage) -> String {
        if message.attachmentId != nil && message.body.isEmpty {
            return "📎 \(message.attachmentName ?? "chat_attachment".localized())"
        }
        if let name = message.fromUserName, message.groupId != nil {
            return "\(name): \(message.body)"
        }
        return message.body
    }

    private func load() async {
        errorMessage = nil
        do {
            guard let currentUser = viewModel.currentUser else { throw ChatError.notRegistered }
            try await chatService.register(currentUser: currentUser)
            async let conversationsTask = chatService.fetchConversations()
            async let engineersTask = chatService.fetchEngineers()
            async let groupsTask = chatService.fetchGroups()
            conversations = try await conversationsTask
            engineers = try await engineersTask
            groups = (try? await groupsTask) ?? []
            openPendingConversationIfNeeded()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// When we were opened from a tapped chat push, jump straight into the
    /// conversation with the sender (or the group).
    private func openPendingConversationIfNeeded() {
        if let groupID = DeepLinkManager.shared.pendingChatGroupID {
            DeepLinkManager.shared.pendingChatGroupID = nil
            if let group = groups.first(where: { $0.id == groupID })
                ?? conversations.compactMap(\.group).first(where: { $0.id == groupID }) {
                selectedTarget = .group(group)
                return
            }
        }
        guard let partnerID = DeepLinkManager.shared.pendingChatPartnerID else { return }
        DeepLinkManager.shared.pendingChatPartnerID = nil
        if let partner = conversations.compactMap(\.partner).first(where: { $0.id == partnerID })
            ?? engineers.first(where: { $0.id == partnerID }) {
            selectedTarget = .direct(partner)
        }
    }
}

// MARK: - New group sheet

/// Create a group chat: name it and pick members. Members without a published
/// encryption key can't be added (the group key must be wrapped for everyone).
struct NewGroupChatView: View {
    let engineers: [ChatUser]
    @ObservedObject var viewModel: TicketViewModel
    let onCreated: (ChatGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selectedMemberIDs: Set<Int> = []
    @State private var isCreating = false
    @State private var errorMessage: String?

    private var selectableEngineers: [ChatUser] {
        engineers.filter { !($0.publicKey ?? "").isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("chat_group_name".localized())) {
                    TextField("chat_group_name".localized(), text: $name)
                }

                Section(
                    header: Text("chat_group_members".localized()),
                    footer: Text("chat_group_encryption_footer".localized())
                ) {
                    ForEach(selectableEngineers) { engineer in
                        Button {
                            if selectedMemberIDs.contains(engineer.id) {
                                selectedMemberIDs.remove(engineer.id)
                            } else {
                                selectedMemberIDs.insert(engineer.id)
                            }
                        } label: {
                            HStack {
                                Text(engineer.name)
                                    .foregroundColor(.primary)
                                Spacer()
                                if selectedMemberIDs.contains(engineer.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button(action: create) {
                        HStack {
                            if isCreating { ProgressView().padding(.trailing, 4) }
                            Text("chat_create_group".localized())
                        }
                    }
                    .disabled(isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty || selectedMemberIDs.isEmpty)
                }
            }
            .navigationTitle("chat_new_group".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) { dismiss() }
                }
            }
        }
    }

    private func create() {
        isCreating = true
        errorMessage = nil
        Task {
            do {
                let members = selectableEngineers.filter { selectedMemberIDs.contains($0.id) }
                guard let myChatUserId = ChatService.shared.myChatUserId else { throw ChatError.notRegistered }
                // Our own directory entry (needed to wrap the group key for ourselves).
                let me = ChatUser(
                    id: myChatUserId,
                    zammadUserId: viewModel.currentUser?.id ?? 0,
                    name: viewModel.currentUser?.fullname ?? "",
                    email: viewModel.currentUser?.email,
                    publicKey: ChatCrypto.publicKeyBase64
                )
                let group = try await ChatService.shared.createGroup(
                    name: name.trimmingCharacters(in: .whitespaces),
                    members: members,
                    me: me
                )
                onCreated(group)
                dismiss()
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isCreating = false
        }
    }
}
