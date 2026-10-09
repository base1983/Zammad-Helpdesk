import SwiftUI
@preconcurrency import WebKit

extension TicketArticle {
    /// Whether the body is HTML (by content type, or by the look of it when
    /// Zammad labels an HTML mail as plain text). HTML articles render in a
    /// web view on a light card; everything else is native text.
    var isHTMLBody: Bool {
        content_type.lowercased().contains("html") || body.looksLikeHTML
    }
}

struct RichArticleBodyView: View {
    let article: TicketArticle
    let ticketId: Int

    @State private var renderedHTML: String?
    @State private var height: CGFloat = 40
    @State private var isExpanded = false

    /// Tallest an HTML message is shown at before it is cut off behind
    /// "More". Long mails and quoted threads otherwise bury the next article.
    private static let collapsedHeight: CGFloat = 260
    /// Only collapse when there is clearly more to gain than the button costs.
    private static let collapseSlack: CGFloat = 60
    /// Plain-text line limit before "More" appears.
    private static let collapsedLineLimit = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if article.isHTMLBody {
                htmlBody
            } else {
                plainBody
            }
            if needsCollapse {
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Label(
                        (isExpanded ? "show_less" : "show_more").localized(),
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderless)
            }
        }
        .task(id: article.id) {
            guard article.isHTMLBody, renderedHTML == nil else { return }
            await prepareHTML()
        }
    }

    // MARK: - Bodies

    @ViewBuilder
    private var htmlBody: some View {
        if let html = renderedHTML {
            HTMLWebView(html: html, height: $height)
                .frame(height: isExpanded || !needsCollapse ? height : Self.collapsedHeight, alignment: .top)
                .clipped()
        } else {
            Text(article.body.strippingHTML())
                .textSelection(.enabled)
                .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
        }
    }

    private var plainBody: some View {
        Text(article.body.decodingHTMLEntities())
            .textSelection(.enabled)
            .lineLimit(isExpanded ? nil : Self.collapsedLineLimit)
    }

    /// HTML: decided by the measured document height. Plain text: by a rough
    /// size heuristic, since SwiftUI does not report whether `lineLimit` cut
    /// anything off.
    private var needsCollapse: Bool {
        if article.isHTMLBody, renderedHTML != nil {
            return height > Self.collapsedHeight + Self.collapseSlack
        }
        let text = article.isHTMLBody ? article.body.strippingHTML() : article.body
        return text.count > 600 || text.filter { $0 == "\n" }.count >= Self.collapsedLineLimit
    }

    // MARK: - HTML preparation

    private func prepareHTML() async {
        var html = article.body
        let inlineAttachments = (article.attachments ?? []).filter { $0.isInline }

        for attachment in inlineAttachments {
            guard let cid = attachment.contentIDValue else { continue }
            do {
                let fileURL = try await ZammadAPIService.shared.downloadAttachment(
                    ticketId: ticketId,
                    articleId: article.id,
                    attachment: attachment
                )
                let data = try Data(contentsOf: fileURL)
                let dataURL = "data:\(attachment.resolvedMimeType);base64,\(data.base64EncodedString())"
                html = replaceCID(in: html, cid: cid, with: dataURL)
            } catch {
                print("Inline attachment \(attachment.filename) (\(cid)) failed: \(error)")
            }
        }

        let wrapped = wrapInTemplate(html)
        await MainActor.run { renderedHTML = wrapped }
    }

    private func replaceCID(in html: String, cid: String, with replacement: String) -> String {
        var result = html
        let escaped = NSRegularExpression.escapedPattern(for: cid)
        let patterns = [
            "src=\"cid:\(escaped)\"",
            "src='cid:\(escaped)'",
            "src=cid:\(escaped)",
        ]
        for pattern in patterns {
            result = result.replacingOccurrences(
                of: pattern,
                with: "src=\"\(replacement)\"",
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    /// Always light, like Mail does for messages that bring their own colours:
    /// HTML mail is designed for a white page, and a dark colour scheme would
    /// turn unspecified text white on the mail's own white background.
    private func wrapInTemplate(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <style>
            :root { color-scheme: light; }
            html, body {
                margin: 0;
                padding: 0;
                font: -apple-system-body;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                line-height: 1.5;
                color: #1c1c1e;
                background: transparent;
                word-wrap: break-word;
                -webkit-text-size-adjust: 100%;
            }
            img { max-width: 100%; height: auto; }
            a { color: #0a60ff; }
            blockquote {
                border-left: 3px solid rgba(60,60,67,0.3);
                margin: 8px 0;
                padding: 4px 0 4px 10px;
                color: #3c3c43;
            }
            pre, code {
                background: rgba(120,120,128,0.12);
                border-radius: 4px;
                padding: 2px 4px;
                font-family: ui-monospace, monospace;
            }
            pre { padding: 8px; overflow-x: auto; }
            table { border-collapse: collapse; max-width: 100%; }
            td, th { padding: 4px 8px; border: 1px solid rgba(60,60,67,0.25); }
        </style>
        </head>
        <body>\(body)</body>
        </html>
        """
    }
}

// MARK: - WKWebView with dynamic height

private struct HTMLWebView: UIViewRepresentable {
    let html: String
    @Binding var height: CGFloat

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Mail content has no business running scripts. The app's own height
        // measurement still works: evaluateJavaScript is not content script.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        if context.coordinator.lastLoadedHTML != html {
            context.coordinator.lastLoadedHTML = html
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(height: $height)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let height: Binding<CGFloat>
        var lastLoadedHTML: String?

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Wait briefly for images to settle, then measure
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                webView.evaluateJavaScript("Math.ceil(document.body.scrollHeight)") { result, _ in
                    if let h = result as? CGFloat, h > 0 {
                        DispatchQueue.main.async {
                            if abs(self.height.wrappedValue - h) > 1 {
                                self.height.wrappedValue = h
                            }
                        }
                    }
                }
            }
        }

        // External links open in Safari
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated, let url = navigationAction.request.url {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
                return
            }
            decisionHandler(.allow)
        }
    }
}
