import SwiftUI
import QuickLook

struct TicketDetailView: View {
    let ticketID: Int
    @ObservedObject var viewModel: TicketViewModel
    /// False when shown side by side with the list (split view, regular
    /// width): there is nothing to go back to.
    var showsBackButton: Bool = true
    /// What the back button does. The split view clears its selection; a
    /// pushed or sheet-presented detail falls back to `dismiss`.
    var onBack: (() -> Void)? = nil

    @State private var ticket: Ticket?
    @State private var articles: [TicketArticle] = []
    @State private var timeAccountings: [TimeAccounting] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Whether this visit has been counted towards the review request.
    @State private var hasCountedAsOpened = false
    @State private var isShowingPremiumPrompt = false
    private static let groupDefaults = UserDefaults(suiteName: "group.com.World-ICT.Zammad-Helpdesk")
    /// SLA information is a Premium feature.
    @AppStorage("are_ads_removed", store: Self.groupDefaults) private var isPremium: Bool = false

    @State private var isShowingEditSheet = false
    @State private var isShowingReplySheet = false
    @State private var isShowingTimeSheet = false
    @State private var isShowingHandoffSheet = false
    @State private var isConfirmingSpam = false
    @State private var isClosingAsSpam = false
    @State private var spamError: String?
    @State private var isShowingCustomerSearch = false
    @State private var optionalCustomerId: Int? = nil
    @State private var showPendingTimePicker = false
    @State private var pendingTime = Date()

    @State private var previewURL: URL?
    @State private var downloadingAttachmentId: Int?
    @State private var attachmentError: String?
    
    // Programmatic navigation state to fix VStack List row issues
    @State private var isEditingStatus = false
    @State private var isEditingPriority = false
    @State private var isEditingOwner = false
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if isLoading && ticket == nil {
                ProgressView("loading_ticket_details".localized())
            } else if let errorMessage = errorMessage {
                VStack {
                    Text(errorMessage).foregroundColor(.red)
                    Button("try_again".localized(), action: { Task { await loadDetails() } })
                }
            } else if let ticket = ticket {
                ticketContent(ticket)
            }
        }
        .task { await loadDetails() }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            if showsBackButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    // Plain glyph: on iOS 26 the toolbar draws Liquid Glass
                    // around its items itself, so a hand-made material circle
                    // would be glass on glass.
                    Button(action: { if let onBack { onBack() } else { dismiss() } }) {
                        Image(systemName: "chevron.left")
                            .fontWeight(.semibold)
                    }
                }
            }
            ToolbarItem(placement: .principal) {
                Text(ticket?.title ?? "").lineLimit(1).truncationMode(.tail)
            }
            // One item per action, no bordered style: iOS 26 lays the group
            // out in a single glass pill itself. Bordered buttons stuffed into
            // one HStack item drew their own backgrounds inside that pill and
            // sat off the bar's baseline in the split view's detail column.
            ToolbarItemGroup(placement: .topBarTrailing) {
                if viewModel.isTimeAccountingEnabled {
                    Button(action: { isShowingTimeSheet = true }) { Image(systemName: "clock") }
                }
                Button(action: { isShowingHandoffSheet = true }) { Image(systemName: "person.2") }
                Button(action: { isShowingEditSheet = true }) { Image(systemName: "square.and.pencil") }
                Button(action: { isShowingReplySheet = true }) { Image(systemName: "arrowshape.turn.up.left") }
                Menu {
                    Button(role: .destructive) {
                        isConfirmingSpam = true
                    } label: {
                        Label("close_as_spam".localized(), systemImage: "xmark.bin")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .disabled(isClosingAsSpam)
            }
        }
        .confirmationDialog("close_as_spam_confirm_title".localized(), isPresented: $isConfirmingSpam, titleVisibility: .visible) {
            Button("close_as_spam".localized(), role: .destructive) {
                Task { await closeAsSpam() }
            }
            Button("cancel".localized(), role: .cancel) {}
        } message: {
            Text("close_as_spam_confirm_message".localized())
        }
        .alert("close_as_spam_failed".localized(), isPresented: Binding(
            get: { spamError != nil },
            set: { if !$0 { spamError = nil } }
        )) {
            Button("ok".localized(), role: .cancel) {}
        } message: {
            Text(spamError ?? "")
        }
        .sheet(isPresented: $isShowingEditSheet) {
            if let ticketBinding = Binding($ticket) {
                TicketEditView(viewModel: viewModel, ticket: ticketBinding)
            }
        }
        .sheet(isPresented: $isShowingPremiumPrompt) {
            PremiumPromptView()
        }
        .sheet(isPresented: $isShowingReplySheet) {
            if let ticket = ticket {
                let mostRecentArticle = articles.max { $0.created_at < $1.created_at }
                TicketReplyView(viewModel: viewModel, ticket: ticket, articleToReplyTo: mostRecentArticle)
            }
        }
        .sheet(isPresented: $isShowingTimeSheet) {
            if let ticket = ticket {
                TimeAccountingEditView(viewModel: viewModel, ticket: ticket)
            }
        }
        .sheet(isPresented: $isShowingHandoffSheet, onDismiss: {
            // Reload so the handoff note (and new owner) show up in the thread.
            Task { await loadDetails() }
        }) {
            if let ticketBinding = Binding($ticket) {
                TicketHandoffView(viewModel: viewModel, ticket: ticketBinding)
            }
        }
        .sheet(isPresented: $isShowingCustomerSearch, onDismiss: {
            if let customerId = optionalCustomerId, ticket?.customer_id != customerId {
                ticket?.customer_id = customerId
                Task { _ = await saveChanges() }
            }
        }) {
            CustomerSearchView(selectedCustomerId: $optionalCustomerId, viewModel: viewModel)
        }
        .sheet(isPresented: $showPendingTimePicker) {
            pendingTimePickerView
        }
        .quickLookPreview($previewURL)
        .navigationDestination(isPresented: $isEditingStatus) {
            if let ticketBinding = Binding($ticket) {
                PickerEditView(
                    title: "status".localized(),
                    selection: ticketBinding.state_id,
                    items: viewModel.ticketStates,
                    displayName: { state in viewModel.localizedStatusName(for: state.name) },
                    onSave: { await saveChanges() }
                )
            }
        }
        .navigationDestination(isPresented: $isEditingPriority) {
            if let ticketBinding = Binding($ticket) {
                PickerEditView(
                    title: "priority".localized(),
                    selection: ticketBinding.priority_id,
                    items: viewModel.ticketPriorities,
                    displayName: { $0.name },
                    onSave: { await saveChanges() }
                )
            }
        }
        .navigationDestination(isPresented: $isEditingOwner) {
            if let ticketBinding = Binding($ticket) {
                let owners = [User(id: 1, organization_id: nil, login: "", firstname: "unassigned".localized(), lastname: "", email: "", web: nil, phone: nil, fax: nil, mobile: nil, department: nil, street: nil, zip: nil, city: nil, country: nil, address: nil, vip: false, verified: false, active: true, note: nil, last_login: nil, source: nil, login_failed: 0, out_of_office: false, out_of_office_start_at: nil, out_of_office_end_at: nil, out_of_office_replacement_id: nil, preferences: UserPreferences(), role_ids: nil, organization_ids: nil, authorization_ids: nil, group_ids: nil, updated_by_id: 0, created_by_id: 0, created_at: Date(), updated_at: Date())] + viewModel.agentUsers
                PickerEditView(
                    title: "owner".localized(),
                    selection: ticketBinding.owner_id,
                    items: owners,
                    displayName: { $0.fullname },
                    onSave: { await saveChanges() }
                )
            }
        }
    }
    
    @ViewBuilder
        private func ticketContent(_ ticket: Ticket) -> some View {
            List {
                Section(header: Text("details_section_header".localized()).font(.headline)) {
                    VStack(spacing: 0) {
                        detailRow(label: "ticket_number".localized(), value: "#\(ticket.number)")
                            .padding(.vertical, 10)
                        
                        Divider()
                        
                        Button(action: {
                            optionalCustomerId = ticket.customer_id
                            isShowingCustomerSearch = true
                        }) {
                            HStack {
                                detailRow(label: "customer".localized(), value: viewModel.userName(for: ticket.customer_id))
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        
                        Divider()
                        
                        Button(action: { isEditingStatus = true }) {
                            HStack {
                                detailRow(label: "status".localized(), value: viewModel.localizedStatusName(for: viewModel.stateName(for: ticket.state_id)))
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        
                        Divider()
                        
                        Button(action: { isEditingPriority = true }) {
                            HStack {
                                detailRow(label: "priority".localized(), value: viewModel.priorityName(for: ticket.priority_id))
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        
                        Divider()
                        
                        Button(action: { isEditingOwner = true }) {
                            HStack {
                                detailRow(label: "owner".localized(), value: viewModel.userName(for: ticket.owner_id))
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 10)
                        
                        if viewModel.isTimeAccountingEnabled {
                            Divider()
                            detailRow(label: "time_spent".localized(), value: totalTimeSpent)
                                .padding(.vertical, 10)
                        }
                        
                        Divider()
                        
                        detailRow(label: "created_at".localized(), value: ticket.created_at.formatted())
                            .padding(.vertical, 10)
                    }
                }
                .listRowBackground(materialRowBackground)

                if ticket.hasSLA {
                    Section(header: Text("sla".localized()).font(.headline)) {
                        if isPremium {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(ticket.slaDeadlines.enumerated()), id: \.element.id) { index, deadline in
                                    if index > 0 { Divider() }
                                    slaRow(for: deadline)
                                        .padding(.vertical, 10)
                                }
                            }
                        } else {
                            // The ticket has an SLA, but the deadlines are a
                            // Premium feature: say so, and offer the upgrade.
                            Button(action: { isShowingPremiumPrompt = true }) {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "crown.fill").foregroundStyle(.yellow)
                                    Text("sla_premium_required".localized())
                                        .font(.callout)
                                        .foregroundColor(.primary)
                                        .multilineTextAlignment(.leading)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .listRowBackground(materialRowBackground)
                }

                Section(header: Text("communication_history".localized()).font(.headline)) {
                    ForEach(articles.sorted(by: { $0.created_at > $1.created_at })) { article in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(viewModel.userName(for: article.created_by_id)).fontWeight(.semibold)
                                Spacer()
                                Text(article.created_at.formatted(date: .numeric, time: .shortened)).font(.caption).foregroundColor(.secondary)
                            }
                            RichArticleBodyView(article: article, ticketId: ticketID)
                                .padding(.top, 4)

                            if let attachments = article.attachments?.filter({ !$0.isInline }), !attachments.isEmpty {
                                attachmentsView(for: article, attachments: attachments)
                            }
                        }
                        .padding(.vertical, 8)
                        // HTML mail is rendered light-on-white regardless of
                        // appearance (see RichArticleBodyView), so the header
                        // on that card must follow suit.
                        .environment(\.colorScheme, article.isHTMLBody ? .light : colorScheme)
                        .listRowBackground(articleRowBackground(for: article))
                        .listRowSeparator(.hidden)
                    }
                }
            }
            .listStyle(.insetGrouped)
            // Each article is its own glass card, so give them air instead of
            // the hairline separators that a shared blurred section used.
            .listRowSpacing(8)
            .scrollContentBackground(.hidden)
            .background(ClearBackgroundView())
            .onAppear {
                ReadStatusManager.shared.markAsRead(ticket: ticket)
                viewModel.updateApplicationBadge()
            }
        }

    @ViewBuilder
    private func attachmentsView(for article: TicketArticle, attachments: [Attachment]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("attachments".localized())
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.top, 4)
            ForEach(attachments) { attachment in
                Button {
                    Task { await downloadAndPreview(attachment: attachment, articleId: article.id) }
                } label: {
                    HStack(spacing: 10) {
                        if downloadingAttachmentId == attachment.id {
                            ProgressView().frame(width: 22)
                        } else {
                            Image(systemName: attachment.systemIconName)
                                .foregroundColor(.accentColor)
                                .frame(width: 22)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(attachment.filename)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if !attachment.sizeFormatted.isEmpty {
                                Text(attachment.sizeFormatted)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Image(systemName: "arrow.down.circle")
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.12))
                    )
                }
                .buttonStyle(.plain)
                .disabled(downloadingAttachmentId != nil)
            }
            if let attachmentError {
                Text(attachmentError)
                    .font(.caption2)
                    .foregroundColor(.red)
            }
        }
    }

    private func downloadAndPreview(attachment: Attachment, articleId: Int) async {
        guard downloadingAttachmentId == nil else { return }
        downloadingAttachmentId = attachment.id
        attachmentError = nil
        defer { downloadingAttachmentId = nil }
        do {
            let url = try await viewModel.downloadAttachment(attachment, articleId: articleId, ticketId: ticketID)
            previewURL = url
        } catch {
            attachmentError = error.localizedDescription
        }
    }

    private var totalTimeSpent: String {
        let total = timeAccountings.reduce(0.0) { $0 + (Double($1.time_unit) ?? 0.0) }
        return "\(total) \("hours".localized())"
    }

    /// Card behind the ticket-properties block and plain-text articles: the
    /// same regular material as the ticket list, so text sits on a steady,
    /// readable backdrop whatever the wallpaper.
    private var materialRowBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(.regularMaterial)
    }

    /// Article cards: an opaque light card for HTML mail (which brings its
    /// own colours and expects a white page), the material card otherwise.
    @ViewBuilder
    private func articleRowBackground(for article: TicketArticle) -> some View {
        if article.isHTMLBody {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.white)
        } else {
            materialRowBackground
        }
    }

    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label).fontWeight(.semibold)
            Spacer()
            Text(value).foregroundColor(.secondary)
        }
    }

    /// One SLA target: met (green check), overdue (red), or the deadline
    /// with the time left, coloured by how close it is.
    private func slaRow(for deadline: SLADeadline) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(deadline.kind.titleKey.localized()).fontWeight(.semibold)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                if let completedAt = deadline.completedAt {
                    Label("sla_met".localized(), systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text(completedAt.formatted(date: .numeric, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if let status = deadline.status(), let due = deadline.deadline {
                    Label(status.text, systemImage: status.symbolName)
                        .foregroundStyle(status.color)
                    Text(due.formatted(date: .numeric, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
    
    @ViewBuilder
    private var pendingTimePickerView: some View {
        NavigationStack {
            VStack {
                DatePicker("select_pending_time".localized(), selection: $pendingTime, displayedComponents: [.date, .hourAndMinute])
                    .datePickerStyle(.graphical)
                    .padding()
            }
            .navigationTitle("pending_time_title".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized(), action: {
                        showPendingTimePicker = false
                        Task { await loadDetails() }
                    })
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("done".localized(), action: {
                        showPendingTimePicker = false
                        Task { _ = await saveChanges(pendingTime: pendingTime) }
                    })
                }
            }
        }
    }
    
    private func saveChanges(pendingTime: Date? = nil) async -> Bool {
        guard let ticketToUpdate = ticket else { return false }
        do {
            let needsPendingTime = try await viewModel.updateTicket(ticketToUpdate, pendingTime: pendingTime)
            if needsPendingTime {
                self.showPendingTimePicker = true
                return true // Keep PickerEditView open
            } else {
                await viewModel.refreshAllData()
                await loadDetails()
                return false // Dismiss PickerEditView
            }
        } catch {
            self.errorMessage = error.localizedDescription
            await loadDetails()
            return false // Dismiss PickerEditView
        }
    }
    
    /// Tags the ticket as spam and closes it; on success the ticket has left
    /// the open queue, so leave the detail screen too.
    private func closeAsSpam() async {
        guard let ticket, !isClosingAsSpam else { return }
        isClosingAsSpam = true
        defer { isClosingAsSpam = false }
        do {
            try await viewModel.closeAsSpam(ticket)
            dismiss()
        } catch {
            spamError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            await loadDetails()
        }
    }

    private func loadDetails() async {
        if ticket == nil { isLoading = true }
        self.errorMessage = nil
        do {
            async let ticketTask = ZammadAPIService.shared.fetchTicket(id: ticketID)
            async let articlesTask = ZammadAPIService.shared.fetchArticles(for: ticketID)
            async let timeAccountingsTask = ZammadAPIService.shared.fetchTimeAccountingsGracefully(for: ticketID)
            
            let (ticketResult, articlesResult, timeAccountingsResult) = await (try ticketTask, try articlesTask, timeAccountingsTask)
            
            self.ticket = ticketResult
            self.articles = articlesResult
            self.timeAccountings = timeAccountingsResult

            // Count the ticket as opened once it has actually loaded, and
            // only once per visit: reloads after a reply or handoff do not
            // count again. The list container asks for the review when the
            // user leaves the ticket, since this view is gone by then.
            if !hasCountedAsOpened {
                hasCountedAsOpened = true
                ReviewRequestManager.shared.recordTicketOpened()
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

