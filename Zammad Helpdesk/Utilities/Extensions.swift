import SwiftUI
import UIKit

// MARK: - Kleur Extensie
extension Color {
    // Een dynamische accentkleur die zich aanpast aan de lichte en donkere modus.
    static var glassAccent: Color {
        return Color(UIColor { traitCollection in
            if traitCollection.userInterfaceStyle == .light {
                return UIColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 1.0)
            } else {
                return UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0)
            }
        })
    }
}

// MARK: - String Localization Helper
extension String {
    func localized() -> String {
        return NSLocalizedString(self, comment: "")
    }
}

// MARK: - HTML Parsing Helper
struct HTMLParser {
    static func attributedString(from html: String) -> NSAttributedString? {
        let styledHtml = """
        <style> body { font-family: -apple-system, sans-serif; font-size: 16px; color: #333; } </style>
        \(html)
        """
        guard let data = styledHtml.data(using: .utf8) else { return nil }
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [.documentType: NSAttributedString.DocumentType.html, .characterEncoding: String.Encoding.utf8.rawValue]
        return try? NSAttributedString(data: data, options: options, documentAttributes: nil)
    }
}

