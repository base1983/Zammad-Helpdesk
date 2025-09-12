import SwiftUI
import StoreKit

// Dit bestand bevat nu ALLE herbruikbare-, detail- en sheet-views om alle compiler-fouten op te lossen.

// MARK: - Hoofd Views
struct TicketDetailView: View {
    let ticket: Ticket
    @ObservedObject var viewModel: TicketViewModel
    @Environment(\.dismiss) var dismiss // Added to control the view's presentation

    @State private var articles: [TicketArticle] = []
    @State private var isLoadingArticles = false
    @State private var articleError: String?
    @State private var isShowingEditView = false
    @State private var isShowingReplyView = false

    private let apiService = ZammadAPIService.shared

    var body: some View {
        // De view is nu opgesplitst om de compiler te helpen.
        contentView
            .toolbar { toolbarContent }
            .navigationBarBackButtonHidden(true) // Hides the default text-based back button
            .task { await loadArticles() }
            .sheet(isPresented: $isShowingEditView) {
                EditTicketView(ticket: ticket, viewModel: viewModel) { Task { await viewModel.refreshAllData() } }
            }
            .sheet(isPresented: $isShowingReplyView) {
                ReplyView(
                    ticket: ticket,
                    customer: viewModel.allUsers.first { $0.id == ticket.customer_id },
                    onReply: { Task { await loadArticles() } }
                )
            }
    }

    private func loadArticles() async {
        isLoadingArticles = true; articleError = nil
        do {
            articles = try await apiService.fetchArticles(for: ticket.id)
        } catch {
            articleError = (error as? LocalizedError)?.errorDescription ?? "unknown_error".localized()
        }
        isLoadingArticles = false
    }

    // MARK: - Subviews (voor betere leesbaarheid en compiler-prestaties)
    private var contentView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                detailsSection
                statusSection
                messagesSection
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
        .refreshable { await loadArticles() }
    }

    private var detailsSection: some View {
        StyledSection(title: "ticket_details".localized()) {
            DetailRow(label: "ticket_number".localized(), value: ticket.number)
            Divider()
            DetailRow(label: "title".localized(), value: ticket.title)
            Divider()
            DetailRow(label: "created_at".localized(), value: ticket.formattedCreationDate)
            Divider()
            DetailRow(label: "owner".localized(), value: viewModel.userName(for: ticket.owner_id))
        }
    }

    private var statusSection: some View {
        StyledSection(title: "status".localized()) {
            DetailRow(label: "current_status".localized(), value: viewModel.localizedStatusName(for: viewModel.stateName(for: ticket.state_id)))
            Divider()
            DetailRow(label: "priority".localized(), value: viewModel.priorityName(for: ticket.priority_id))
        }
    }

    private var messagesSection: some View {
        VStack(alignment: .leading) {
            Text("messages".localized()).font(.headline).foregroundColor(.secondary).padding(.horizontal)

            if isLoadingArticles { ProgressView().frame(maxWidth: .infinity) }
            else if let articleError { Text(String(format: "error_loading_messages".localized(), articleError)).foregroundColor(.red) }
            else if articles.isEmpty { Text("no_messages_found".localized()).foregroundColor(.secondary).padding() }
            else {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(articles) { article in
                        ArticleView(article: article)
                    }
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // This is the new custom back button icon
        ToolbarItem(placement: .navigationBarLeading) {
            Button(action: { dismiss() }) {
                Image(systemName: "chevron.left.circle")
                    .imageScale(.large)
                    .foregroundColor(.primary)
            }
        }
        
        ToolbarItem(placement: .principal) {
            Text("Ticket #\(ticket.number)")
                .fontWeight(.bold)
        }
        
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button(action: { isShowingReplyView = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrowshape.turn.up.left.circle")
                        Text("reply".localized())
                    }
                }
                .buttonStyle(.plain) // Ensures the icon color is not the accent color

                Button(action: { isShowingEditView = true }) {
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.circle")
                        Text("edit".localized())
                    }
                }
                .buttonStyle(.plain) // Ensures the icon color is not the accent color
            } label: {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.primary)
            }
        }
    }
}

// MARK: - Herbruikbare Componenten
struct StyledSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).foregroundColor(.secondary).padding([.leading, .top])
            
            VStack(alignment: .leading) {
                content
            }
            .padding()
            .background(.thinMaterial)
            .cornerRadius(12)
        }
    }
}

struct TicketRowView: View {
    let ticket: Ticket
    let stateName: String
    let priorityName: String
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(ticket.title).font(.headline).lineLimit(2)
                Text("#\(ticket.number) • \(ticket.formattedCreationDate)").font(.subheadline).foregroundColor(.secondary)
            }
            .foregroundColor(.primary)
            Spacer()
            VStack(alignment: .trailing) {
                Text(stateName).font(.caption.bold()).padding(5)
                    .background(statusColor(for: stateName)).foregroundColor(.white).cornerRadius(5)
                Text(priorityName).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial)
        .cornerRadius(12)
    }
    
    private func statusColor(for status: String) -> Color {
        switch status.lowercased() {
        case "new", "nieuw": .blue; case "open": .green; case "pending reminder", "wacht op klant reactie": .orange; case "closed", "gesloten": .gray; default: .purple
        }
    }
}

struct ArticleView: View {
    let article: TicketArticle
    @State private var attributedBody: AttributedString?
    @Environment(\.colorScheme) var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(article.from).font(.headline)
                Spacer()
                Text(article.formattedCreationDate).font(.caption)
            }
            .foregroundColor(.primary)
            
            if let attributedBody { Text(attributedBody) }
            else { Text(article.body.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)) }
        }
        .padding()
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .cornerRadius(15)
        .listRowInsets(EdgeInsets())
        .task(id: colorScheme) { // Re-run when color scheme changes
            // Determine text color based on the current color scheme
            let textColor = (colorScheme == .dark) ? "white" : "black"
            // Prepend CSS to the HTML body to set the default text color
            let styledHtml = """
            <style>
                body {
                    color: \(textColor);
                }
            </style>
            \(article.body)
            """

            if let nsAttributedString = HTMLParser.attributedString(from: styledHtml) {
                self.attributedBody = AttributedString(nsAttributedString)
            }
        }
    }
}

struct LockedView: View {
    var onUnlock: () -> Void
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.shield.fill").font(.system(size: 60)).foregroundColor(.secondary)
            Text("app_locked".localized()).font(.title)
            Button("unlock".localized(), action: onUnlock)
                .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .background(.thinMaterial)
        .cornerRadius(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Image("AppBackground").resizable().scaledToFill().opacity(0.3).offset(x: -150).ignoresSafeArea())
    }
}

struct DetailRow: View {
    let label: String, value: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value)
        }
        .foregroundColor(.primary)
    }
}

// MARK: - Sheet Views
struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var storeManager = StoreManager()
    @State private var serverURL = SettingsManager.shared.loadServerURL()
    @State private var apiToken = SettingsManager.shared.loadToken() ?? ""
    @State private var isLockEnabled = SettingsManager.shared.isLockEnabled()
    @AppStorage("color_scheme_option") private var colorSchemeOption: String = SettingsManager.shared.loadTheme().rawValue
    
    @State private var notificationsEnabled = SettingsManager.shared.areNotificationsEnabled()
    @State private var newTicketNotificationsEnabled = SettingsManager.shared.areNewTicketNotificationsEnabled()
    @State private var assignmentNotificationsEnabled = SettingsManager.shared.areAssignmentNotificationsEnabled()
    @State private var replyNotificationsEnabled = SettingsManager.shared.areReplyNotificationsEnabled()
    @State private var realtimeNotificationsEnabled = SettingsManager.shared.areRealtimeNotificationsEnabled()
    
    @State private var isShowingWebhookHelp = false

    var onSave: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    StyledSection(title: "server_configuration".localized()) {
                        TextField("zammad_url".localized(), text: $serverURL, axis: .vertical).keyboardType(.URL).autocapitalization(.none)
                    }
                    StyledSection(title: "api_configuration".localized()) {
                        TextField("personal_access_token".localized(), text: $apiToken, axis: .vertical)
                    }
                    StyledSection(title: "security".localized()) {
                        Toggle("secure_with_faceid".localized(), isOn: $isLockEnabled)
                    }
                    StyledSection(title: "appearance".localized()) {
                        Picker("theme".localized(), selection: $colorSchemeOption) {
                            ForEach(ColorSchemeOption.allCases) { Text($0.rawValue.localized()).tag($0.rawValue) }
                        }.pickerStyle(.segmented)
                    }
                    StyledSection(title: "notifications".localized()) {
                        VStack(alignment: .leading, spacing: 10) {
                            if realtimeNotificationsEnabled {
                                Text("fallback_notifications_disabled_info".localized()).font(.caption).foregroundColor(.secondary)
                            }
                            Toggle("enable_notifications".localized(), isOn: $notificationsEnabled)
                            if notificationsEnabled {
                                Toggle("new_tickets".localized(), isOn: $newTicketNotificationsEnabled)
                                Toggle("new_assignments".localized(), isOn: $assignmentNotificationsEnabled)
                                Toggle("customer_replies".localized(), isOn: $replyNotificationsEnabled)
                            }
                        }
                        .disabled(realtimeNotificationsEnabled)
                    }
                    StyledSection(title: "pro_subscription".localized()) {
                        switch storeManager.subscriptionGroupStatus {
                        case .subscribed, .inGracePeriod: Text("pro_subscriber_thanks".localized())
                        default: purchaseButtons
                        }
                    }
                    StyledSection(title: "advanced".localized()) {
                        DisclosureGroup("realtime_notifications_title".localized()) {
                            VStack(alignment: .leading, spacing: 15) {
                                Text("realtime_notifications_explanation".localized()).font(.caption).foregroundColor(.secondary)
                                Toggle("enable_realtime_notifications".localized(), isOn: $realtimeNotificationsEnabled)
                                    .onChange(of: realtimeNotificationsEnabled) { _, newValue in
                                        Task { await NotificationProxyService.shared.updateRegistration(isSubscribing: newValue) }
                                    }
                                if realtimeNotificationsEnabled {
                                    Text("webhook_url_label".localized()).fontWeight(.semibold)
                                    Text("\(NotificationProxyService.shared.getWebhookURL())")
                                        .font(.footnote).foregroundColor(.accentColor).textSelection(.enabled)
                                    Button("how_to_configure".localized()) {
                                        isShowingWebhookHelp = true
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                            .padding(.top)
                        }
                    }
                }.padding()
            }
            .background(Image("AppBackground").resizable().scaledToFill().opacity(0.3).offset(x: -150).ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("settings".localized()).fontWeight(.bold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: dismiss.callAsFunction) { Image(systemName: "xmark.circle").foregroundColor(.primary).imageScale(.large) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: saveSettings) { Image(systemName: "checkmark.circle").foregroundColor(.primary).imageScale(.large) }
                }
            }
        }
        .tint(.glassAccent)
        .sheet(isPresented: $isShowingWebhookHelp) {
            WebhookHelpView()
        }
    }
    
    private func saveSettings() {
        SettingsManager.shared.save(serverURL: serverURL)
        SettingsManager.shared.save(token: apiToken)
        SettingsManager.shared.save(isLockEnabled: isLockEnabled)
        SettingsManager.shared.save(notificationsEnabled: notificationsEnabled)
        SettingsManager.shared.save(newTicketNotificationsEnabled: newTicketNotificationsEnabled)
        SettingsManager.shared.save(assignmentNotificationsEnabled: assignmentNotificationsEnabled)
        SettingsManager.shared.save(replyNotificationsEnabled: replyNotificationsEnabled)
        SettingsManager.shared.save(realtimeNotificationsEnabled: realtimeNotificationsEnabled)
        onSave(); dismiss()
    }

    @ViewBuilder
    private var purchaseButtons: some View {
        if storeManager.isLoadingProducts || storeManager.isTransactionInProgress { ProgressView().padding() }
        else if storeManager.monthlyProduct != nil || storeManager.yearlyProduct != nil {
            if let monthly = storeManager.monthlyProduct {
                Button("\(monthly.displayName) - \(monthly.displayPrice)/\("month".localized())") { Task { await storeManager.purchase(monthly) } }.buttonStyle(.borderedProminent)
            }
            if let yearly = storeManager.yearlyProduct {
                Button("\(yearly.displayName) - \(yearly.displayPrice)/\("year".localized())") { Task { await storeManager.purchase(yearly) } }.buttonStyle(.borderedProminent)
            }
        } else {
            Text("could_not_load_subscriptions".localized()).foregroundColor(.secondary).padding()
        }
    }
}

struct WebhookHelpView: View {
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("webhook_guide_title".localized())
                        .font(.largeTitle).fontWeight(.bold)
                    
                    Text("webhook_guide_intro".localized())
                    
                    StyledSection(title: "webhook_guide_step1_title".localized()) {
                        Text("webhook_guide_step1_body".localized())
                    }
                    
                    StyledSection(title: "webhook_guide_step2_title".localized()) {
                        Text("webhook_guide_step2_body".localized())
                    }
                    
                    StyledSection(title: "webhook_guide_step3_title".localized()) {
                        Text("webhook_guide_step3_body".localized())
                    }
                    
                    StyledSection(title: "webhook_guide_step4_title".localized()) {
                        Text("webhook_guide_step4_body".localized())
                    }
                }
                .padding()
            }
            .background(Color.black.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("webhook_guide_title".localized()).fontWeight(.bold)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("done".localized(), action: dismiss.callAsFunction)
                        .tint(.glassAccent)
                }
            }
        }
    }
}

struct EditTicketView: View {
    @Environment(\.dismiss) var dismiss
    let ticket: Ticket
    @ObservedObject var viewModel: TicketViewModel
    var onUpdate: () -> Void
    @State private var selectedStateID: Int
    @State private var selectedPriorityID: Int
    @State private var selectedOwnerID: Int
    @State private var isSaving = false
    @State private var saveError: String?
    private let apiService = ZammadAPIService.shared

    init(ticket: Ticket, viewModel: TicketViewModel, onUpdate: @escaping () -> Void) {
        self.ticket = ticket; self.viewModel = viewModel; self.onUpdate = onUpdate
        _selectedStateID = State(initialValue: ticket.state_id)
        _selectedPriorityID = State(initialValue: ticket.priority_id)
        _selectedOwnerID = State(initialValue: ticket.owner_id)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("adjust_ticket".localized()) {
                    Picker("status".localized(), selection: $selectedStateID) { ForEach(viewModel.ticketStates) { Text(viewModel.localizedStatusName(for: $0.name)).tag($0.id) } }
                    Picker("priority".localized(), selection: $selectedPriorityID) { ForEach(viewModel.ticketPriorities) { Text($0.name).tag($0.id) } }
                    Picker("owner".localized(), selection: $selectedOwnerID) { ForEach(viewModel.agentUsers) { Text($0.fullname).tag($0.id) } }
                }
                if let saveError { Section { Text(String(format: "error_saving".localized(), saveError)).foregroundColor(.red) } }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("edit_ticket".localized()).fontWeight(.bold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: dismiss.callAsFunction) { Image(systemName: "xmark.circle").foregroundColor(.primary).imageScale(.large) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving { ProgressView() } else { Button(action: { Task { await saveChanges() } }) { Image(systemName: "checkmark.circle").foregroundColor(.primary).imageScale(.large) } }
                }
            }.tint(.glassAccent)
        }
    }

    private func saveChanges() async {
        isSaving = true; saveError = nil
        let payload = TicketUpdatePayload(state_id: selectedStateID, priority_id: selectedPriorityID, owner_id: selectedOwnerID)
        do {
            _ = try await apiService.updateTicket(id: ticket.id, payload: payload); onUpdate(); dismiss()
        } catch { saveError = (error as? LocalizedError)?.errorDescription ?? "unknown_error".localized() }
        isSaving = false
    }
}

struct ReplyView: View {
    @Environment(\.dismiss) var dismiss
    let ticket: Ticket, customer: User?
    var onReply: () -> Void
    @State private var messageBody = ""
    @State private var isSending = false
    @State private var sendError: String?
    private let apiService = ZammadAPIService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("reply_to_customer".localized()) { TextEditor(text: $messageBody).frame(minHeight: 200) }
                if let sendError { Section { Text(String(format: "error_sending".localized(), sendError)).foregroundColor(.red) } }
            }
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("new_reply".localized()).fontWeight(.bold)
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: dismiss.callAsFunction) { Image(systemName: "xmark.circle").foregroundColor(.primary).imageScale(.large) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSending { ProgressView() } else { Button(action: { Task { await sendReply() } }) { Image(systemName: "paperplane.circle").foregroundColor(.primary).imageScale(.large) }.disabled(messageBody.isEmpty || customer == nil) }
                }
            }.tint(.glassAccent)
        }
    }

    private func sendReply() async {
        guard let customer else { sendError = "customer_not_found".localized(); return }
        isSending = true; sendError = nil
        let payload = ArticleCreationPayload(
            ticket_id: ticket.id, subject: "Re: [Ticket#\(ticket.number)] \(ticket.title)",
            body: messageBody, to: "\(customer.fullname) <\(customer.email)>"
        )
        do {
            _ = try await apiService.createArticle(payload: payload); onReply(); dismiss()
        } catch { sendError = (error as? LocalizedError)?.errorDescription ?? "unknown_error".localized() }
        isSending = false
    }
}

