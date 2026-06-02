import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct TicketReplyView: View {
    @ObservedObject var viewModel: TicketViewModel
    let ticket: Ticket
    let articleToReplyTo: TicketArticle?

    @State private var replyBody: String = ""
    @State private var isInternalNote = false
    @State private var attachments: [AttachmentDraft] = []
    @State private var photoSelections: [PhotosPickerItem] = []
    @State private var isShowingFileImporter = false
    @State private var attachmentError: String?
    @State private var isSending = false
    @State private var restoredDraftDate: Date?
    @State private var saveTask: Task<Void, Never>?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let restoredDraftDate {
                    draftBanner(savedAt: restoredDraftDate)
                }

                TextEditor(text: $replyBody)
                    .padding(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                    )
                    .padding(.horizontal)
                    .padding(.top)
                    .onChange(of: replyBody) { _, _ in scheduleSave() }
                    .onChange(of: isInternalNote) { _, _ in scheduleSave() }

                if !attachments.isEmpty {
                    attachmentsList
                }

                if let attachmentError {
                    Text(attachmentError)
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                }

                Toggle("internal_note_toggle".localized(), isOn: $isInternalNote)
                    .padding(.horizontal)
                    .padding(.top, 8)

                attachmentBar
            }
            .navigationTitle("reply_to_ticket".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: sendMessage) {
                        if isSending {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .disabled(isSending)
                }
            }
            .onAppear(perform: setupInitialReply)
            .onDisappear { saveTask?.cancel() }
            .onChange(of: photoSelections) { _, newItems in
                Task { await loadPhotoSelections(newItems) }
            }
            .fileImporter(
                isPresented: $isShowingFileImporter,
                allowedContentTypes: [.item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImporter(result)
            }
        }
    }

    @ViewBuilder
    private var attachmentsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(attachments) { attachment in
                HStack(spacing: 10) {
                    Image(systemName: attachment.systemIconName)
                        .foregroundColor(.accentColor)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(attachment.filename)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(attachment.sizeFormatted)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button {
                        attachments.removeAll { $0.id == attachment.id }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.gray.opacity(0.12))
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var attachmentBar: some View {
        HStack(spacing: 12) {
            PhotosPicker(
                selection: $photoSelections,
                maxSelectionCount: 10,
                matching: .any(of: [.images, .videos])
            ) {
                Label("add_photo".localized(), systemImage: "photo.on.rectangle")
            }
            .buttonStyle(.bordered)

            Button {
                isShowingFileImporter = true
            } label: {
                Label("add_file".localized(), systemImage: "paperclip")
            }
            .buttonStyle(.bordered)

            Spacer()
        }
        .padding()
    }

    private func setupInitialReply() {
        if let draft = DraftManager.shared.draft(for: ticket.id) {
            replyBody = draft.body
            isInternalNote = draft.isInternalNote
            restoredDraftDate = draft.updatedAt
            return
        }
        guard let article = articleToReplyTo else { return }
        let quoteHeader = "\n\n--- \("on".localized()) \(article.created_at.formatted(date: .abbreviated, time: .shortened)) \(viewModel.userName(for: article.created_by_id)) \("wrote".localized()):\n>"
        let quotedBody = article.body.strippingHTML().replacingOccurrences(of: "\n", with: "\n> ")
        replyBody = quoteHeader + quotedBody
    }

    @ViewBuilder
    private func draftBanner(savedAt: Date) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.text.fill")
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("draft_restored".localized())
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(savedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                discardDraft()
            } label: {
                Text("discard_draft".localized())
                    .font(.caption)
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let body = replyBody
        let isInternal = isInternalNote
        let ticketId = ticket.id
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                DraftManager.shared.save(ticketId: ticketId, body: body, isInternalNote: isInternal)
            }
        }
    }

    private func discardDraft() {
        DraftManager.shared.delete(for: ticket.id)
        saveTask?.cancel()
        restoredDraftDate = nil
        replyBody = ""
        isInternalNote = false
        // Re-seed quote if there's an article to reply to
        if let article = articleToReplyTo {
            let quoteHeader = "\n\n--- \("on".localized()) \(article.created_at.formatted(date: .abbreviated, time: .shortened)) \(viewModel.userName(for: article.created_by_id)) \("wrote".localized()):\n>"
            let quotedBody = article.body.strippingHTML().replacingOccurrences(of: "\n", with: "\n> ")
            replyBody = quoteHeader + quotedBody
        }
    }

    private func loadPhotoSelections(_ items: [PhotosPickerItem]) async {
        guard !items.isEmpty else { return }
        for item in items {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                let mimeType = item.supportedContentTypes.first?.preferredMIMEType ?? "image/jpeg"
                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "jpg"
                let filename = "image-\(Int(Date().timeIntervalSince1970)).\(ext)"
                let draft = AttachmentDraft(filename: filename, data: data, mimeType: mimeType)
                await MainActor.run { attachments.append(draft) }
            } catch {
                await MainActor.run { attachmentError = error.localizedDescription }
            }
        }
        await MainActor.run { photoSelections.removeAll() }
    }

    private func handleFileImporter(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            for url in urls {
                let needsScope = url.startAccessingSecurityScopedResource()
                defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
                do {
                    let data = try Data(contentsOf: url)
                    let mimeType = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType
                        ?? "application/octet-stream"
                    let draft = AttachmentDraft(filename: url.lastPathComponent, data: data, mimeType: mimeType)
                    attachments.append(draft)
                } catch {
                    attachmentError = error.localizedDescription
                }
            }
        case .failure(let error):
            attachmentError = error.localizedDescription
        }
    }

    private func sendMessage() {
        isSending = true
        Task {
            defer { Task { @MainActor in isSending = false } }
            do {
                if isInternalNote {
                    try await viewModel.addInternalNote(for: ticket, with: replyBody, attachments: attachments)
                } else {
                    guard let recipient = viewModel.userEmail(for: ticket.customer_id) else {
                        print("Failed to send reply: Customer email not found.")
                        return
                    }
                    try await viewModel.sendReply(
                        for: ticket,
                        with: replyBody,
                        subject: ticket.title,
                        recipient: recipient,
                        articleToReplyTo: articleToReplyTo,
                        attachments: attachments
                    )
                }
                saveTask?.cancel()
                DraftManager.shared.delete(for: ticket.id)
                await MainActor.run { dismiss() }
            } catch {
                print("Failed to send reply: \(error.localizedDescription)")
                await MainActor.run { attachmentError = error.localizedDescription }
            }
        }
    }
}
