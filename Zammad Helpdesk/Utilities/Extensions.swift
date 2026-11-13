import Foundation
import SwiftUI

extension String {
    func localized() -> String {
        return NSLocalizedString(self, comment: "")
    }

    func strippingHTML() -> String {
        var s = self.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</p\\s*>", with: "\n\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "</div\\s*>", with: "\n", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        s = s.decodingHTMLEntities()
        s = s.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        s = s.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func decodingHTMLEntities() -> String {
        let namedEntities: [String: String] = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">",
            "&quot;": "\"", "&apos;": "'",
            "&euro;": "€", "&pound;": "£", "&yen;": "¥", "&cent;": "¢",
            "&copy;": "©", "&reg;": "®", "&trade;": "™",
            "&hellip;": "…", "&ndash;": "–", "&mdash;": "—",
            "&lsquo;": "\u{2018}", "&rsquo;": "\u{2019}",
            "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}",
            "&bull;": "•", "&middot;": "·",
            "&iexcl;": "¡", "&iquest;": "¿",
            "&laquo;": "«", "&raquo;": "»",
            "&sect;": "§", "&para;": "¶",
            "&deg;": "°", "&plusmn;": "±", "&times;": "×", "&divide;": "÷",
        ]
        var s = self
        for (entity, replacement) in namedEntities {
            s = s.replacingOccurrences(of: entity, with: replacement)
        }
        guard let regex = try? NSRegularExpression(pattern: "&#([xX])?([0-9a-fA-F]+);") else { return s }
        let matches = regex.matches(in: s, range: NSRange(s.startIndex..., in: s))
        for match in matches.reversed() {
            guard let fullRange = Range(match.range, in: s),
                  let numRange = Range(match.range(at: 2), in: s) else { continue }
            let isHex = match.range(at: 1).location != NSNotFound
            let numStr = String(s[numRange])
            let value = isHex ? UInt32(numStr, radix: 16) : UInt32(numStr, radix: 10)
            if let v = value, let scalar = Unicode.Scalar(v) {
                s.replaceSubrange(fullRange, with: String(scalar))
            }
        }
        return s
    }

    var looksLikeHTML: Bool {
        self.range(of: "<[a-zA-Z][^>]*>", options: .regularExpression) != nil
    }
}

extension Date {
    func timeAgoDisplay() -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: self, relativeTo: Date())
    }
}

#if os(iOS)
// MARK: - UIKit Background Fixes
// MARK: - Liquid Glass with iOS 18 fallbacks
//
// The deployment target is below iOS 26, so every Liquid Glass call goes
// through these helpers: glass where the OS has it, the same shape in a
// material where it does not.

extension View {
    /// Liquid Glass in a rounded rectangle, or a material of the same shape.
    @ViewBuilder
    func glassOrMaterial(cornerRadius: CGFloat) -> some View {
        if #available(iOS 26, *) {
            glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
        } else {
            background(.regularMaterial, in: .rect(cornerRadius: cornerRadius))
        }
    }

    /// Liquid Glass capsule (optionally reacting to touch), or a material capsule.
    @ViewBuilder
    func glassOrMaterialCapsule(interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular)
        } else {
            background(.regularMaterial, in: .capsule)
        }
    }

    /// Liquid Glass circle (optionally reacting to touch), or a material circle.
    @ViewBuilder
    func glassOrMaterialCircle(interactive: Bool = false) -> some View {
        if #available(iOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: .circle)
        } else {
            background(.regularMaterial, in: .circle)
        }
    }

    /// Round glass button, or a round bordered button before iOS 26.
    @ViewBuilder
    func roundGlassButtonStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glass).buttonBorderShape(.circle)
        } else {
            buttonStyle(.bordered).buttonBorderShape(.circle)
        }
    }

    /// Round prominent glass button, or a round prominent bordered button.
    @ViewBuilder
    func roundProminentGlassButtonStyle() -> some View {
        if #available(iOS 26, *) {
            buttonStyle(.glassProminent).buttonBorderShape(.circle)
        } else {
            buttonStyle(.borderedProminent).buttonBorderShape(.circle)
        }
    }
}

/// `GlassEffectContainer` on iOS 26, so neighbouring glass shapes blend and
/// morph; just the content before that.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        if #available(iOS 26, *) {
            GlassEffectContainer(spacing: spacing, content: content)
        } else {
            content()
        }
    }
}

/// Lets the app-wide wallpaper show through UIKit containers that SwiftUI
/// puts between it and the content (navigation controllers, and since the
/// ticket screen became a split view, the split view controller and its
/// column wrappers). Place it as a `.background` of the content to clear.
struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        AncestorClearingView()
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

/// Walks every superview up to the window and clears its background. Runs
/// when attached to a window and again on layout, because UIKit containers
/// (the split view in particular) re-apply their own colours on trait and
/// size changes.
private final class AncestorClearingView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        clearAncestors()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clearAncestors()
    }

    private func clearAncestors() {
        var view = superview
        while let current = view, !(current is UIWindow) {
            // Visual effect views ignore backgroundColor and log about it.
            if !(current is UIVisualEffectView) {
                current.backgroundColor = .clear
            }
            view = current.superview
        }
        parentViewController?.view.backgroundColor = .clear
    }
}

extension UIView {
    var parentViewController: UIViewController? {
        var parentResponder: UIResponder? = self
        while parentResponder != nil {
            parentResponder = parentResponder?.next
            if let viewController = parentResponder as? UIViewController {
                return viewController
            }
        }
        return nil
    }
}
#endif

