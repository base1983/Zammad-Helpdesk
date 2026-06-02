import SwiftUI
@preconcurrency import WebKit

struct RichArticleBodyView: View {
    let article: TicketArticle
    let ticketId: Int

    @State private var renderedHTML: String?
    @State private var height: CGFloat = 40

    private var isHTML: Bool {
        article.content_type.lowercased().contains("html") || article.body.looksLikeHTML
    }

    var body: some View {
        Group {
            if isHTML {
                if let html = renderedHTML {
                    HTMLWebView(html: html, height: $height)
                        .frame(height: height)
                } else {
                    Text(article.body.strippingHTML())
                        .textSelection(.enabled)
                }
            } else {
                Text(article.body.decodingHTMLEntities())
                    .textSelection(.enabled)
            }
        }
        .task(id: article.id) {
            guard isHTML, renderedHTML == nil else { return }
            await prepareHTML()
        }
    }

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

    private func wrapInTemplate(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
        <style>
            :root { color-scheme: light dark; }
            html, body {
                margin: 0;
                padding: 0;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                font-size: 16px;
                line-height: 1.4;
                background: transparent;
                word-wrap: break-word;
                -webkit-text-size-adjust: 100%;
            }
            img { max-width: 100%; height: auto; }
            a { color: -apple-system-blue; }
            blockquote {
                border-left: 3px solid rgba(127,127,127,0.4);
                margin: 8px 0;
                padding: 4px 0 4px 10px;
                opacity: 0.75;
            }
            pre, code {
                background: rgba(127,127,127,0.15);
                border-radius: 4px;
                padding: 2px 4px;
                font-family: ui-monospace, monospace;
            }
            pre { padding: 8px; overflow-x: auto; }
            table { border-collapse: collapse; max-width: 100%; }
            td, th { padding: 4px 8px; border: 1px solid rgba(127,127,127,0.3); }
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
