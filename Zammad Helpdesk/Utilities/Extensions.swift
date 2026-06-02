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
struct ClearBackgroundView: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        Task { @MainActor in
            view.parentViewController?.view.backgroundColor = .clear
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
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

// MARK: - Visual Effects
struct VisualEffectView: UIViewRepresentable {
    var effect: UIVisualEffect?
    func makeUIView(context: Context) -> UIVisualEffectView {
        UIVisualEffectView(effect: effect)
    }
    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = effect
    }
}
#endif

