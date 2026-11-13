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
    private static let collapsedHeight: CGFloat = 180
    /// Only collapse when there is clearly more to gain than the button costs.
    private static let collapseSlack: CGFloat = 40
    /// Plain-text line limit before "More" appears.
    private static let collapsedLineLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if article.isHTMLBody {
                htmlBody
            } else {
                plainBody
            }
            if needsCollapse {
                // Bordered on purpose: the app's accent is black/white, so a
                // borderless "More" would read as just another line of text.
                Button(action: { withAnimation(.easeInOut(duration: 0.2)) { isExpanded.toggle() } }) {
                    Label(
                        (isExpanded ? "show_less" : "show_more").localized(),
                        systemImage: isExpanded ? "chevron.up" : "chevron.down"
                    )
                    .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(.top, 2)
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
            // The web view always gets its full content height, so its own
            // scroll view has nothing to scroll vertically and only pans
            // sideways for wide tables; the outer frame does the collapsing.
            HTMLWebView(html: html, height: $height)
                .frame(height: height)
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
        return text.count > 400 || text.filter { $0 == "\n" }.count >= Self.collapsedLineLimit
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

    private static let heightMessageName = "articleHeight"

    /// Reports the document height whenever it changes, so images that
    /// finish decoding after load still grow the card instead of being cut.
    /// Injected by the app, so it runs even with content JavaScript off.
    private static let heightReporterScript = """
    (function () {
        var last = 0;
        function report() {
            var body = document.body;
            if (!body) { return; }
            var h = Math.ceil(Math.max(body.scrollHeight, body.getBoundingClientRect().height));
            if (h > 0 && h !== last) {
                last = h;
                window.webkit.messageHandlers.\(heightMessageName).postMessage(h);
            }
        }
        report();
        if (window.ResizeObserver) {
            new ResizeObserver(report).observe(document.body);
        }
        window.addEventListener('load', report);
        Array.prototype.forEach.call(document.images, function (img) {
            img.addEventListener('load', report);
        });
    })();
    """

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // Mail content has no business running scripts. Only JavaScript that
        // the *page* brings along is blocked; the app's own user script and
        // evaluateJavaScript calls below still run.
        config.defaultWebpagePreferences.allowsContentJavaScript = false
        let contentController = WKUserContentController()
        // The content controller retains its handler; go through a weak proxy
        // so the coordinator (and with it the web view) can be freed.
        contentController.add(WeakScriptMessageHandler(context.coordinator), name: Self.heightMessageName)
        contentController.addUserScript(WKUserScript(
            source: Self.heightReporterScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        config.userContentController = contentController
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        // Horizontal scrolling only: wide tables and fixed-width mail layouts
        // can be panned sideways. Vertical movement belongs to the outer
        // List; the frame matches the content height so there is nothing to
        // scroll, and the delegate pins the offset in case images grow it.
        //
        // The built-in pan is replaced by our own (see Coordinator): nested
        // UIScrollViews lock a drag to one axis, whereas our recognizer moves
        // the content sideways *and* lets the List's pan run at the same
        // time, so a diagonal drag scrolls both.
        webView.scrollView.isScrollEnabled = true
        webView.scrollView.bounces = false
        webView.scrollView.alwaysBounceVertical = false
        webView.scrollView.alwaysBounceHorizontal = false
        webView.scrollView.showsVerticalScrollIndicator = false
        webView.scrollView.showsHorizontalScrollIndicator = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.delegate = context.coordinator
        context.coordinator.installHorizontalPan(on: webView.scrollView)
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

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        let contentController = webView.configuration.userContentController
        contentController.removeScriptMessageHandler(forName: heightMessageName)
        contentController.removeAllUserScripts()
        webView.scrollView.delegate = nil
        webView.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        let height: Binding<CGFloat>
        var lastLoadedHTML: String?

        private weak var scrollView: UIScrollView?
        private var panStartOffsetX: CGFloat = 0

        init(height: Binding<CGFloat>) {
            self.height = height
        }

        // MARK: Height

        /// Pushes a measured document height into SwiftUI, ignoring noise.
        private func apply(height measured: CGFloat) {
            guard measured > 0, abs(height.wrappedValue - measured) > 1 else { return }
            height.wrappedValue = measured
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let number = message.body as? NSNumber else { return }
            apply(height: CGFloat(number.doubleValue))
        }

        /// Keeps the web view from scrolling vertically even if late-loading
        /// images make the document taller than the measured height.
        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            if scrollView.contentOffset.y != 0 {
                scrollView.contentOffset.y = 0
            }
        }

        func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }

        // MARK: Free (diagonal) scrolling

        /// Swaps the scroll view's own pan recognizer for one that only moves
        /// the content horizontally and is happy to recognise alongside the
        /// enclosing List's pan.
        func installHorizontalPan(on scrollView: UIScrollView) {
            self.scrollView = scrollView
            scrollView.panGestureRecognizer.isEnabled = false
            let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
            pan.maximumNumberOfTouches = 1
            pan.delegate = self
            scrollView.addGestureRecognizer(pan)
        }

        @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
            guard let scrollView else { return }
            let maxOffsetX = max(0, scrollView.contentSize.width - scrollView.bounds.width)

            switch pan.state {
            case .began:
                // Stop any fling still in progress and take over from there.
                scrollView.setContentOffset(scrollView.contentOffset, animated: false)
                panStartOffsetX = scrollView.contentOffset.x
            case .changed:
                let proposed = panStartOffsetX - pan.translation(in: scrollView).x
                scrollView.contentOffset.x = min(max(0, proposed), maxOffsetX)
            case .ended, .cancelled:
                // Coast like UIScrollView's normal deceleration rate would
                // (roughly a quarter of the release velocity in points).
                let velocityX = pan.velocity(in: scrollView).x
                let projected = scrollView.contentOffset.x - velocityX * 0.25
                let target = min(max(0, projected), maxOffsetX)
                guard abs(target - scrollView.contentOffset.x) > 0.5 else { return }
                UIView.animate(withDuration: 0.45, delay: 0,
                               options: [.curveEaseOut, .allowUserInteraction, .beginFromCurrentState]) {
                    scrollView.contentOffset.x = target
                }
            default:
                break
            }
        }

        /// Only claim the gesture when there is actually something to pan
        /// sideways; otherwise the List gets the drag untouched.
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let scrollView else { return false }
            return scrollView.contentSize.width > scrollView.bounds.width + 1
        }

        /// The whole point: the List's vertical pan and our horizontal pan
        /// track the same finger, so a diagonal drag moves both axes.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Belt and braces next to the user script: one direct measurement
            // once the document has finished loading.
            webView.evaluateJavaScript("Math.ceil(document.body.scrollHeight)") { [weak self] result, _ in
                guard let self, let number = result as? NSNumber else { return }
                self.apply(height: CGFloat(number.doubleValue))
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

/// WKUserContentController holds its message handlers strongly, which would
/// pin the coordinator and the web view forever; this forwards weakly.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(userContentController, didReceive: message)
    }
}
