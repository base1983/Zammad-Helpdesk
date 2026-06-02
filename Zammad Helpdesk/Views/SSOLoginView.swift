import SwiftUI
@preconcurrency import WebKit
import SafariServices

struct SSOLoginView: View {
    let serverURL: String
    let onTokenReceived: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var controller = SSOController()
    @State private var safariURL: URL?
    @State private var isShowingPasteSheet = false
    @State private var pastedToken = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar

                ZStack {
                    SSOWebView(serverURL: serverURL, controller: controller)
                        .ignoresSafeArea(edges: .bottom)

                    if controller.phase == .creating {
                        creatingOverlay
                    }
                }

                bottomBar
            }
            .navigationTitle("login_with_sso".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            openInSafari()
                        } label: {
                            Label("login_via_safari".localized(), systemImage: "safari")
                        }
                        Button {
                            isShowingPasteSheet = true
                        } label: {
                            Label("paste_token".localized(), systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(item: Binding(
                get: { safariURL.map(IdentifiableURL.init) },
                set: { url in
                    safariURL = url?.url
                    if url == nil {
                        // Sheet dismissed — assume the user made a token
                        isShowingPasteSheet = true
                    }
                }
            )) { item in
                SafariSheet(url: item.url).ignoresSafeArea()
            }
            .sheet(isPresented: $isShowingPasteSheet) {
                pasteTokenSheet
            }
            .alert("sso_failed_title".localized(), isPresented: failedBinding) {
                Button("retry".localized()) {
                    controller.retryAutoDetect()
                }
                Button("open_profile_page".localized()) {
                    controller.navigateToProfilePage()
                }
                Button("cancel".localized(), role: .cancel) {
                    controller.phase = .waitingForLogin
                }
            } message: {
                Text(controller.errorMessage ?? "sso_failed_message".localized())
            }
            .onAppear {
                controller.start(serverURL: serverURL) { token in
                    onTokenReceived(token)
                    dismiss()
                }
            }
            .onDisappear { controller.stop() }
        }
    }

    private var failedBinding: Binding<Bool> {
        Binding(
            get: { controller.phase == .failed },
            set: { if !$0 { controller.phase = .waitingForLogin } }
        )
    }

    @ViewBuilder
    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(controller.phase.label)
                    .font(.caption.bold())
                    .foregroundColor(controller.phase.color)
                Spacer()
                Text("\(controller.cookieCount) cookies · sessie: \(controller.hasSessionCookie ? "✓" : "—")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Text(controller.currentURL ?? "—")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
    }

    @ViewBuilder
    private var bottomBar: some View {
        HStack(spacing: 10) {
            Button {
                controller.attemptTokenCreation(reason: "manual")
            } label: {
                Label("im_logged_in".localized(), systemImage: "checkmark.shield")
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(controller.phase == .creating || controller.phase == .loading)

            Button {
                controller.navigateToProfilePage()
            } label: {
                Image(systemName: "person.crop.circle")
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(Color(.systemBackground))
    }

    private func openInSafari() {
        guard let base = controller.normalizedBaseURL(),
              let url = URL(string: base + "/#profile/token_access") else { return }
        safariURL = url
    }

    @ViewBuilder
    private var pasteTokenSheet: some View {
        NavigationStack {
            Form {
                Section {
                    Text("paste_token_explainer".localized())
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Section(header: Text("api_token".localized())) {
                    TextField("paste_api_token".localized(), text: $pastedToken, axis: .vertical)
                        .lineLimit(2...5)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                Section {
                    Button("save".localized()) {
                        let trimmed = pastedToken.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onTokenReceived(trimmed)
                        isShowingPasteSheet = false
                        dismiss()
                    }
                    .disabled(pastedToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("paste_token".localized())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("cancel".localized()) { isShowingPasteSheet = false }
                }
            }
        }
    }

    @ViewBuilder
    private var creatingOverlay: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
            VStack(spacing: 14) {
                ProgressView().scaleEffect(1.3).tint(.white)
                Text("creating_token".localized())
                    .foregroundColor(.white)
                    .font(.callout)
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

// MARK: - Controller

@MainActor
final class SSOController: NSObject, ObservableObject {
    @Published var phase: Phase = .loading
    @Published var currentURL: String?
    @Published var errorMessage: String?
    @Published var cookieCount: Int = 0
    @Published var hasSessionCookie: Bool = false

    private(set) var webView: WKWebView?
    private var serverURL: String = ""
    private var tokenCallback: ((String) -> Void)?
    private var pollTimer: Timer?
    private var urlObserver: NSKeyValueObservation?
    private var attemptedAutoDetect = false

    enum Phase: Equatable {
        case loading
        case waitingForLogin
        case creating
        case failed

        var label: String {
            switch self {
            case .loading: "sso_status_loading".localized()
            case .waitingForLogin: "sso_status_waiting".localized()
            case .creating: "sso_status_creating".localized()
            case .failed: "sso_status_failed".localized()
            }
        }

        var color: Color {
            switch self {
            case .loading: .secondary
            case .waitingForLogin: .blue
            case .creating: .orange
            case .failed: .red
            }
        }
    }

    func start(serverURL: String, onToken: @escaping (String) -> Void) {
        self.serverURL = serverURL
        self.tokenCallback = onToken
        startPolling()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        urlObserver?.invalidate()
        urlObserver = nil
    }

    func attach(webView: WKWebView) {
        self.webView = webView
        urlObserver = webView.observe(\.url, options: [.new, .initial]) { [weak self] _, _ in
            Task { @MainActor in
                self?.currentURL = webView.url?.absoluteString
                self?.checkAutoDetect()
            }
        }
    }

    func retryAutoDetect() {
        attemptedAutoDetect = false
        phase = .waitingForLogin
        checkAutoDetect()
    }

    func navigateToProfilePage() {
        guard let base = normalizedBaseURL(),
              let url = URL(string: base + "/#profile/token_access") else { return }
        webView?.load(URLRequest(url: url))
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAutoDetect() }
        }
    }

    private func checkAutoDetect() {
        guard let webView else { return }

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let zammadCookies = self.filterZammadCookies(cookies)
            let hasAnySessionCookie = zammadCookies.contains { $0.name.lowercased().contains("session") }

            Task { @MainActor in
                self.cookieCount = zammadCookies.count

                guard !self.attemptedAutoDetect,
                      self.phase == .waitingForLogin || self.phase == .loading else { return }

                if self.phase == .loading {
                    self.phase = .waitingForLogin
                }

                // Anonymous Zammad page already sets a session cookie before login,
                // so verify with the API before triggering token creation.
                guard hasAnySessionCookie else {
                    self.hasSessionCookie = false
                    return
                }

                let authenticated = await self.verifyAuthenticated(cookies: zammadCookies)
                self.hasSessionCookie = authenticated

                if authenticated {
                    self.attemptedAutoDetect = true
                    self.attemptTokenCreation(reason: "auto")
                }
            }
        }
    }

    private func verifyAuthenticated(cookies: [HTTPCookie]) async -> Bool {
        guard let base = normalizedBaseURL(),
              let url = URL(string: base + "/api/v1/users/me") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 10.0)
        let cookieHeader = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        let session = URLSession(configuration: config)

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200...299).contains(http.statusCode)
        } catch {
            return false
        }
    }

    func attemptTokenCreation(reason: String) {
        print("SSO: attemptTokenCreation reason=\(reason) phase=\(phase)")
        guard phase != .creating, let webView else {
            print("SSO: blocked — already creating or no webview")
            return
        }
        attemptedAutoDetect = true
        phase = .creating

        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self else { return }
            let zammadCookies = self.filterZammadCookies(cookies)
            print("SSO: \(zammadCookies.count) Zammad cookies, total \(cookies.count)")

            self.extractCSRFToken(webView: webView) { csrf in
                print("SSO: CSRF token \(csrf == nil ? "NOT found" : "found (length \(csrf!.count))")")
                Task { @MainActor in
                    await self.createToken(cookies: zammadCookies, csrfToken: csrf)
                }
            }
        }
    }

    private func extractCSRFToken(webView: WKWebView, completion: @escaping (String?) -> Void) {
        let js = """
        (function() {
            try {
                var meta = document.querySelector('meta[name="csrf-token"]');
                if (meta && meta.content) return meta.content;

                if (typeof App !== 'undefined' && App && App.Config && typeof App.Config.get === 'function') {
                    var t = App.Config.get('csrf_token') || App.Config.get('csrfToken');
                    if (t) return t;
                }

                var cookies = document.cookie.split(';');
                for (var i = 0; i < cookies.length; i++) {
                    var parts = cookies[i].trim().split('=');
                    var name = parts[0];
                    if (name === 'XSRF-TOKEN' || name === '_csrf_token' || name.toLowerCase().indexOf('csrf') !== -1) {
                        return decodeURIComponent(parts.slice(1).join('='));
                    }
                }
            } catch (e) {}
            return '';
        })()
        """
        webView.evaluateJavaScript(js) { result, _ in
            let token = (result as? String).flatMap { $0.isEmpty ? nil : $0 }
            completion(token)
        }
    }

    private func createToken(cookies: [HTTPCookie], csrfToken: String?) async {
        do {
            let tokenName = "iOS Helpdesk – \(UIDevice.current.name)"
            let token = try await ZammadAPIService.shared.createAccessTokenWithSession(
                url: serverURL,
                cookies: cookies,
                csrfToken: csrfToken,
                tokenName: tokenName
            )
            tokenCallback?(token)
        } catch {
            errorMessage = describe(error: error, csrfFound: csrfToken != nil, cookieCount: cookies.count)
            phase = .failed
            // Allow manual retry after failure
            attemptedAutoDetect = false
        }
    }

    private func describe(error: Error, csrfFound: Bool, cookieCount: Int) -> String {
        var parts: [String] = []
        if let api = error as? APIError {
            parts.append(api.errorDescription ?? "\(api)")
        } else {
            parts.append(error.localizedDescription)
        }
        parts.append("CSRF: \(csrfFound ? "OK" : "missing")")
        parts.append("Cookies: \(cookieCount)")
        return parts.joined(separator: " • ")
    }

    private func filterZammadCookies(_ cookies: [HTTPCookie]) -> [HTTPCookie] {
        let host = normalizedHost()
        return cookies.filter { cookie in
            let name = cookie.name.lowercased()
            // Accept any Zammad-typical cookie by name
            if name.hasPrefix("_zammad") || name.contains("zammad_session") || name == "xsrf-token" || name.contains("csrf") {
                return true
            }
            guard let host else { return false }
            let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return host == domain
                || host.hasSuffix("." + domain)
                || domain.hasSuffix("." + host)
                || host.hasSuffix(domain)
        }
    }

    private func normalizedHost() -> String? {
        var u = serverURL
        if !u.lowercased().hasPrefix("http") { u = "https://" + u }
        return URL(string: u)?.host?.lowercased()
    }

    func normalizedBaseURL() -> String? {
        var u = serverURL
        if !u.lowercased().hasPrefix("http") { u = "https://" + u }
        if u.hasSuffix("/") { u.removeLast() }
        return u
    }
}

// MARK: - Safari fallback helpers

private struct IdentifiableURL: Identifiable, Equatable {
    let url: URL
    var id: String { url.absoluteString }
}

private struct SafariSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// MARK: - WKWebView Wrapper

private struct SSOWebView: UIViewRepresentable {
    let serverURL: String
    @ObservedObject var controller: SSOController

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: config)
        // Pretend to be Safari to bypass Microsoft's "embedded webview" block on Azure AD logins
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

        if let url = loginURL() {
            print("SSO: loading initial URL \(url)")
            webView.load(URLRequest(url: url))
        } else {
            print("SSO: could not build login URL from serverURL=\(serverURL)")
        }

        Task { @MainActor in
            controller.attach(webView: webView)
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // If the URL never loaded (e.g. webview created before serverURL was set), retry once.
        if uiView.url == nil, let url = loginURL() {
            uiView.load(URLRequest(url: url))
        }
    }

    private func loginURL() -> URL? {
        var u = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !u.isEmpty else { return nil }
        if !u.lowercased().hasPrefix("http") { u = "https://" + u }
        if u.hasSuffix("/") { u.removeLast() }
        return URL(string: u + "/#login")
    }
}
