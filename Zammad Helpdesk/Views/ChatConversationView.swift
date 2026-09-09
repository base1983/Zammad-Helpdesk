import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/// Message thread with a colleague or a group. Polls the proxy for new
/// messages every minute while the view is visible, caches history
/// on-device (pruned to the configured retention window) and supports
/// @mentions, #ticket references and encrypted photo/file attachments.
struct ChatConversationView: View {
    let target: ChatTarget
    @ObservedObject var viewModel: TicketViewModel
    @StateObject private var chatService = ChatService.shared

    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    @AppStorage("chat_theme_light", store: Self.groupDefaults) private var lightThemeID: String = ChatTheme.defaultLight.rawValue
    @AppStorage("chat_theme_dark", store: Self.groupDefaults) private var darkThemeID: String = ChatTheme.defaultDark.rawValue
    @Environment(\.colorScheme) private var colorScheme

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var lastPollDate = Date()
    @State private var blockCandidate: BlockCandidate?
    @Environment(\.dismiss) private var moderationDismiss

    // #ticket reference
    @State private var isShowingTicketSearch = false
    @State private var pendingTicket: Ticket?

    // Attachments
    @State private var photoPickerItem: PhotosPickerItem?
    @State private var isShowingFileImporter = false
    @State private var pendingAttachment: PendingChatAttachment?
    @State private var previewURL: URL?

    private let pollInterval: UInt64 = 60_000_000_000 // 60 seconds

    /// The color scheme environment already reflects the in-app theme override.
    private var theme: ChatTheme {
        if colorScheme == .dark {
            return ChatTheme(rawValue: darkThemeID) ?? .defaultDark
        } else {
            return ChatTheme(rawValue: lightThemeID) ?? .defaultLight
        }
    }

    /// People that can be @mentioned in this conversation.
    private var mentionCandidates: [ChatUser] {
        switch target {
        case .direct(let partner): [partner]
        case .group(let group): (group.members ?? []).filter { $0.id != chatService.myChatUserId }
        }
    }

    /// Active "@…" token at the end of the draft, if any.
    private var mentionQuery: String? {
        guard let atIndex = draft.lastIndex(of: "@") else { return nil }
        let token = String(draft[draft.index(after: atIndex)...])
        guard !token.contains("\n") else { return nil }
        return token
    }

    private var mentionSuggestions: [ChatUser] {
        guard let query = mentionQuery else { return [] }
        if query.isEmpty { return mentionCandidates }
        return mentionCandidates.filter { $0.name.lowercased().hasPrefix(query.lowercased()) }
    }

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

            if !mentionSuggestions.isEmpty {
                mentionBar
            }
            if pendingTicket != nil || pendingAttachment != nil {
                pendingItemsBar
            }
            inputBar
        }
        .background(theme.background.ignoresSafeArea())
        .confirmationDialog(
            blockCandidate.map { String(format: "chat_block_user".localized(), $0.name) } ?? "",
            isPresented: Binding(get: { blockCandidate != nil }, set: { if !$0 { blockCandidate = nil } }),
            titleVisibility: .visible,
            presenting: blockCandidate
        ) { candidate in
            Button("chat_block".localized(), role: .destructive) { block(candidate) }
        } message: { candidate in
            Text(String(format: "chat_block_confirm".localized(), candidate.name))
        }
        .navigationTitle(target.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await loadInitial()
            await pollLoop()
        }
        .sheet(isPresented: $isShowingTicketSearch) {
            ChatTicketSearchSheet { ticket in
                // Remove the trailing '#' that triggered the search.
                if draft.hasSuffix("#") { draft.removeLast() }
                pendingTicket = ticket
            }
        }
        .onChange(of: draft) { _, newValue in
            if newValue.hasSuffix("#") {
                isShowingTicketSearch = true
            }
        }
        .onChange(of: photoPickerItem) { _, item in
            guard let item else { return }
            Task { await loadPhoto(item) }
        }
        .fileImporter(isPresented: $isShowingFileImporter, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { loadFile(url) }
        }
        .quickLookPreview($previewURL)
    }

    // MARK: - Subviews

    private func messageBubble(_ message: ChatMessage) -> some View {
        let isMine = message.fromUserId == chatService.myChatUserId
        return VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            // Sender name for group messages from others.
            if case .group = target, !isMine, let name = message.fromUserName {
                Text(name)
                    .font(.caption.bold())
                    .foregroundColor(theme.metaText)
            }
            if message.deleted == true {
                // Tombstone: neutral grey bubble, no ticket/attachment chips.
                Text("🗑 " + "chat_message_deleted".localized())
                    .font(.subheadline.italic())
                    .padding(10)
                    .background(Color(.systemGray5).opacity(0.85))
                    .foregroundColor(.secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
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
                if message.attachmentId != nil {
                    ChatAttachmentView(
                        message: message,
                        filename: message.attachmentName ?? "attachment",
                        mimeType: message.attachmentMime ?? "application/octet-stream",
                        target: target,
                        previewURL: $previewURL
                    )
                }
                if !message.body.isEmpty {
                    Text(attributedBody(message))
                        .padding(10)
                        .background(isMine ? theme.myBubble : theme.partnerBubble)
                        .foregroundColor(isMine ? theme.myText : theme.partnerText)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            HStack(spacing: 4) {
                Image(systemName: message.isEncrypted ? "lock.fill" : "lock.open.fill")
                    .foregroundColor(message.isEncrypted ? theme.metaText : .orange)
                    .accessibilityLabel((message.isEncrypted ? "chat_encrypted_label" : "chat_unencrypted_label").localized())
                if !message.isEncrypted {
                    Text("chat_unencrypted_label".localized())
                        .foregroundColor(.orange)
                }
                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
                    .foregroundColor(theme.metaText)
                if isMine && message.deleted != true {
                    DeliveryTicks(status: message.deliveryStatus, neutral: theme.metaText)
                }
            }
            .font(.caption2)
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .contextMenu {
            if message.deleted != true {
                if isMine {
                    Button(role: .destructive) {
                        deleteForEveryone(message)
                    } label: {
                        Label("chat_delete_message".localized(), systemImage: "trash")
                    }
                } else {
                    Button(role: .destructive) {
                        deleteForMe(message)
                    } label: {
                        Label("chat_delete_for_me".localized(), systemImage: "trash")
                    }
                    // Guideline 1.2: report objectionable content, block its author.
                    Button {
                        report(message)
                    } label: {
                        Label("chat_report_message".localized(), systemImage: "exclamationmark.bubble")
                    }
                    Button(role: .destructive) {
                        blockCandidate = BlockCandidate(id: message.fromUserId, name: senderName(of: message), email: nil)
                    } label: {
                        Label(String(format: "chat_block_user".localized(), senderName(of: message)), systemImage: "hand.raised")
                    }
                }
            }
        }
    }

    // MARK: - Moderation

    private struct BlockCandidate: Identifiable {
        let id: Int
        let name: String
        let email: String?
    }

    private func senderName(of message: ChatMessage) -> String {
        if case .direct(let partner) = target { return partner.name }
        return message.fromUserName ?? String(message.fromUserId)
    }

    /// Hands the message to the mail composer, pre-filled. Falls back to
    /// showing the address when the device has no mail account.
    private func report(_ message: ChatMessage) {
        let url = ChatReporter.reportURL(for: message, in: target, reporterName: viewModel.currentUser?.fullname)
        if !ChatReporter.open(url) {
            errorMessage = String(format: "chat_report_mail_unavailable".localized(), ChatReporter.address)
        }
    }

    /// Blocks the author. In a direct conversation that ends the conversation
    /// (the list no longer shows it); in a group their messages just vanish.
    private func block(_ candidate: BlockCandidate) {
        var email = candidate.email
        if case .direct(let partner) = target { email = partner.email }
        ChatBlockList.shared.block(id: candidate.id, name: candidate.name, email: email)
        switch target {
        case .direct:
            moderationDismiss()
        case .group:
            messages.removeAll { $0.fromUserId == candidate.id }
        }
    }

    // MARK: - Deletion

    /// Deletes one of our own messages on the proxy (tombstoned for everyone).
    /// Locally the bubble becomes the same grey tombstone the receiver sees.
    private func deleteForEveryone(_ message: ChatMessage) {
        Task {
            do {
                try await chatService.deleteMessage(id: message.id)
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    var tombstone = messages[index]
                    tombstone.deleted = true
                    tombstone.body = "chat_message_deleted".localized()
                    tombstone.isEncrypted = true
                    messages[index] = tombstone
                    ChatHistoryStore.shared.merge([tombstone], key: target.id)
                }
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    /// Removes a received message from this device only.
    private func deleteForMe(_ message: ChatMessage) {
        ChatHistoryStore.shared.remove(id: message.id, key: target.id)
        messages.removeAll { $0.id == message.id }
    }

    /// Bolds @mentions of conversation members (and ourselves) in the body.
    private func attributedBody(_ message: ChatMessage) -> AttributedString {
        var attributed = AttributedString(message.body)
        var names = mentionCandidates.map(\.name)
        if let me = viewModel.currentUser?.fullname { names.append(me) }
        for name in names {
            var searchStart = attributed.startIndex
            while searchStart < attributed.endIndex,
                  let range = attributed[searchStart...].range(of: "@" + name) {
                attributed[range].font = .body.bold()
                searchStart = range.upperBound
            }
        }
        return attributed
    }

    private var mentionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(mentionSuggestions) { user in
                    Button {
                        insertMention(user)
                    } label: {
                        Text("@\(user.name)")
                            .font(.callout.bold())
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.thinMaterial, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
        }
        .background(.ultraThinMaterial)
    }

    private func insertMention(_ user: ChatUser) {
        guard let atIndex = draft.lastIndex(of: "@") else { return }
        draft = String(draft[..<atIndex]) + "@\(user.name) "
    }

    private var pendingItemsBar: some View {
        HStack(spacing: 8) {
            if let ticket = pendingTicket {
                HStack(spacing: 4) {
                    Image(systemName: "ticket")
                    Text(String(format: "chat_ticket_reference".localized(), ticket.number))
                        .lineLimit(1)
                    Button(action: { pendingTicket = nil }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .font(.caption)
                .padding(8)
                .background(.thinMaterial, in: Capsule())
            }
            if let attachment = pendingAttachment {
                HStack(spacing: 4) {
                    Image(systemName: attachment.isImage ? "photo" : "doc")
                    Text(attachment.filename)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button(action: { pendingAttachment = nil }) {
                        Image(systemName: "xmark.circle.fill")
                    }
                }
                .font(.caption)
                .padding(8)
                .background(.thinMaterial, in: Capsule())
            }
            Spacer()
        }
        .padding(.horizontal)
        .padding(.vertical, 4)
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            Menu {
                Button(action: { isShowingTicketSearch = true }) {
                    Label("chat_search_ticket".localized(), systemImage: "ticket")
                }
                Button(action: { isShowingFileImporter = true }) {
                    Label("chat_attach_file".localized(), systemImage: "doc")
                }
            } label: {
                Image(systemName: "paperclip")
                    .font(.title3)
            }

            PhotosPicker(selection: $photoPickerItem, matching: .images) {
                Image(systemName: "photo")
                    .font(.title3)
            }

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
            .disabled(isSending || (draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pendingAttachment == nil))
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    // MARK: - Attachments (outgoing)

    private func loadPhoto(_ item: PhotosPickerItem) async {
        defer { photoPickerItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        // Downscale for transfer: max 2048px, JPEG.
        let maxDimension: CGFloat = 2048
        let scale = min(1, maxDimension / max(image.size.width, image.size.height))
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: targetSize)) }
        guard let jpeg = resized.jpegData(compressionQuality: 0.8) else { return }
        guard jpeg.count <= PendingChatAttachment.maxBytes else {
            errorMessage = "chat_attachment_too_large".localized()
            return
        }
        pendingAttachment = PendingChatAttachment(data: jpeg, filename: "photo-\(Int(Date().timeIntervalSince1970)).jpg", mimeType: "image/jpeg")
    }

    private func loadFile(_ url: URL) {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        guard data.count <= PendingChatAttachment.maxBytes else {
            errorMessage = "chat_attachment_too_large".localized()
            return
        }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        pendingAttachment = PendingChatAttachment(data: data, filename: url.lastPathComponent, mimeType: mime)
    }

    // MARK: - Data

    private func loadInitial() async {
        // Show cached history immediately, then top up from the server.
        let cached = ChatHistoryStore.shared.load(key: target.id)
        if !cached.isEmpty { messages = cached }
        do {
            let new = try await chatService.fetchMessages(for: target, since: cached.last?.id)
            messages = ChatHistoryStore.shared.merge(new, key: target.id)
            await chatService.markRead(target: target)
        } catch {
            if messages.isEmpty {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: pollInterval)
            guard !Task.isCancelled else { return }
            // Timestamp taken before the request so a deletion racing with the
            // fetch is picked up by the next poll rather than lost.
            let pollStart = Date()
            if let new = try? await chatService.fetchMessages(for: target, since: messages.last?.id, deletedAfter: lastPollDate) {
                lastPollDate = pollStart
                if !new.isEmpty {
                    // Tombstones in `new` replace their originals via merge-by-id,
                    // so deletions disappear live from the open conversation.
                    messages = ChatHistoryStore.shared.merge(new, key: target.id)
                    await chatService.markRead(target: target)
                }
            }
        }
    }

    private func send() {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty || pendingAttachment != nil else { return }
        isSending = true
        errorMessage = nil
        let ticket = pendingTicket
        let attachment = pendingAttachment
        Task {
            do {
                let message = try await chatService.send(to: target, body: body, ticket: ticket, attachment: attachment)
                messages = ChatHistoryStore.shared.merge([message], key: target.id)
                draft = ""
                pendingTicket = nil
                pendingAttachment = nil
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isSending = false
        }
    }
}

// MARK: - Delivery ticks

/// WhatsApp-style status ticks for own messages: one grey check = sent,
/// two grey checks = delivered, two blue checks = read.
private struct DeliveryTicks: View {
    let status: ChatMessageStatus
    let neutral: Color

    private var color: Color {
        status == .read ? Color(red: 0.20, green: 0.60, blue: 1.0) : neutral
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Image(systemName: "checkmark")
            if status != .sent {
                Image(systemName: "checkmark")
                    .offset(x: 4)
            }
        }
        .font(.caption2.weight(.bold))
        .foregroundColor(color)
        .padding(.trailing, status == .sent ? 0 : 4)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        switch status {
        case .sent: "chat_status_sent".localized()
        case .delivered: "chat_status_delivered".localized()
        case .read: "chat_status_read".localized()
        }
    }
}

// MARK: - Attachment bubble

/// Renders an encrypted chat attachment: inline thumbnail for images, a
/// document chip for other files. Tapping opens a Quick Look preview.
private struct ChatAttachmentView: View {
    // The whole message, not just the attachment id: an attachment is sealed
    // with its message's content key, which only the message carries.
    let message: ChatMessage
    let filename: String
    let mimeType: String
    let target: ChatTarget
    @Binding var previewURL: URL?

    @State private var image: UIImage?
    @State private var isLoading = false

    private var isImage: Bool { mimeType.hasPrefix("image/") }

    var body: some View {
        Group {
            if isImage {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: 220, maxHeight: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .onTapGesture { Task { await preview() } }
                } else {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(.systemGray5).opacity(0.6))
                        .frame(width: 220, height: 160)
                        .overlay(ProgressView())
                        .task { await loadImage() }
                }
            } else {
                Button {
                    Task { await preview() }
                } label: {
                    HStack(spacing: 6) {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "doc.fill")
                        }
                        Text(filename)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.caption.bold())
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func loadImage() async {
        guard let data = try? await ChatService.shared.downloadAttachment(for: message, in: target) else { return }
        image = UIImage(data: data)
    }

    private func preview() async {
        isLoading = true
        defer { isLoading = false }
        guard let data = try? await ChatService.shared.downloadAttachment(for: message, in: target) else { return }
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("chat_attachments", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("\(message.attachmentId ?? 0)_\(filename)")
        try? data.write(to: fileURL, options: .atomic)
        previewURL = fileURL
    }
}

// MARK: - Ticket search sheet (# trigger)

/// Search tickets and pick one to attach to the outgoing chat message.
private struct ChatTicketSearchSheet: View {
    let onSelect: (Ticket) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Ticket] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List(results) { ticket in
                Button {
                    onSelect(ticket)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(ticket.title)
                            .font(.headline)
                            .lineLimit(1)
                        Text("#\(ticket.number)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty && !query.isEmpty {
                    Text("no_search_results".localized())
                        .foregroundColor(.secondary)
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
            .onSubmit(of: .search) { search() }
            .onChange(of: query) { _, _ in search() }
            .navigationTitle("chat_search_ticket".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) { dismiss() }
                }
            }
        }
    }

    private func search() {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        isSearching = true
        Task {
            let found = (try? await ZammadAPIService.shared.searchTickets(query: trimmed)) ?? []
            await MainActor.run {
                results = found
                isSearching = false
            }
        }
    }
}
