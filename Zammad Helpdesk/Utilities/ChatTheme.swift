import SwiftUI

/// Color theme for the chat conversation screen: background plus bubble and
/// text colors for both sides. Separate palettes for light and dark mode,
/// persisted under "chat_theme_light" / "chat_theme_dark".
enum ChatTheme: String, CaseIterable, Identifiable {
    // Light palettes
    case classicLight, sky, mint, rose, lavender, sand, peach, seafoam, lemon, paper
    // Dark palettes
    case classicDark, midnight, graphite, forest, plum, ocean, ember, crimson, gold, neon

    var id: Self { self }

    static let lightThemes: [ChatTheme] = [.classicLight, .sky, .mint, .rose, .lavender, .sand, .peach, .seafoam, .lemon, .paper]
    static let darkThemes: [ChatTheme] = [.classicDark, .midnight, .graphite, .forest, .plum, .ocean, .ember, .crimson, .gold, .neon]

    static let defaultLight: ChatTheme = .classicLight
    static let defaultDark: ChatTheme = .classicDark

    var localizedString: String {
        switch self {
        case .classicLight, .classicDark: "chat_theme_classic".localized()
        case .sky: "chat_theme_sky".localized()
        case .mint: "chat_theme_mint".localized()
        case .rose: "chat_theme_rose".localized()
        case .lavender: "chat_theme_lavender".localized()
        case .sand: "chat_theme_sand".localized()
        case .peach: "chat_theme_peach".localized()
        case .seafoam: "chat_theme_seafoam".localized()
        case .lemon: "chat_theme_lemon".localized()
        case .paper: "chat_theme_paper".localized()
        case .midnight: "chat_theme_midnight".localized()
        case .graphite: "chat_theme_graphite".localized()
        case .forest: "chat_theme_forest".localized()
        case .plum: "chat_theme_plum".localized()
        case .ocean: "chat_theme_ocean".localized()
        case .ember: "chat_theme_ember".localized()
        case .crimson: "chat_theme_crimson".localized()
        case .gold: "chat_theme_gold".localized()
        case .neon: "chat_theme_neon".localized()
        }
    }

    var background: Color {
        switch self {
        case .classicLight: Color(red: 0.95, green: 0.95, blue: 0.97)
        case .sky: Color(red: 0.87, green: 0.93, blue: 0.98)
        case .mint: Color(red: 0.88, green: 0.96, blue: 0.90)
        case .rose: Color(red: 0.99, green: 0.91, blue: 0.93)
        case .lavender: Color(red: 0.93, green: 0.91, blue: 0.98)
        case .sand: Color(red: 0.96, green: 0.93, blue: 0.86)
        case .peach: Color(red: 0.99, green: 0.92, blue: 0.87)
        case .seafoam: Color(red: 0.88, green: 0.96, blue: 0.95)
        case .lemon: Color(red: 0.99, green: 0.97, blue: 0.85)
        case .paper: Color(red: 0.98, green: 0.97, blue: 0.94)
        case .classicDark: Color(red: 0.07, green: 0.07, blue: 0.08)
        case .midnight: Color(red: 0.06, green: 0.08, blue: 0.15)
        case .graphite: Color(red: 0.10, green: 0.10, blue: 0.11)
        case .forest: Color(red: 0.05, green: 0.11, blue: 0.08)
        case .plum: Color(red: 0.10, green: 0.06, blue: 0.13)
        case .ocean: Color(red: 0.04, green: 0.10, blue: 0.14)
        case .ember: Color(red: 0.11, green: 0.07, blue: 0.05)
        case .crimson: Color(red: 0.11, green: 0.05, blue: 0.06)
        case .gold: Color(red: 0.10, green: 0.08, blue: 0.04)
        case .neon: Color(red: 0.02, green: 0.02, blue: 0.02)
        }
    }

    /// Bubble color for the current user's own messages.
    var myBubble: Color {
        switch self {
        case .classicLight: Color(red: 0.00, green: 0.48, blue: 1.00)
        case .sky: Color(red: 0.05, green: 0.40, blue: 0.75)
        case .mint: Color(red: 0.13, green: 0.60, blue: 0.33)
        case .rose: Color(red: 0.85, green: 0.25, blue: 0.45)
        case .lavender: Color(red: 0.48, green: 0.35, blue: 0.80)
        case .sand: Color(red: 0.65, green: 0.45, blue: 0.20)
        case .peach: Color(red: 0.90, green: 0.45, blue: 0.20)
        case .seafoam: Color(red: 0.10, green: 0.55, blue: 0.55)
        case .lemon: Color(red: 0.72, green: 0.55, blue: 0.05)
        case .paper: Color(red: 0.20, green: 0.20, blue: 0.22)
        case .classicDark: Color(red: 0.04, green: 0.42, blue: 0.90)
        case .midnight: Color(red: 0.30, green: 0.40, blue: 0.85)
        case .graphite: Color(red: 0.45, green: 0.45, blue: 0.50)
        case .forest: Color(red: 0.15, green: 0.55, blue: 0.32)
        case .plum: Color(red: 0.55, green: 0.32, blue: 0.75)
        case .ocean: Color(red: 0.10, green: 0.55, blue: 0.65)
        case .ember: Color(red: 0.85, green: 0.42, blue: 0.12)
        case .crimson: Color(red: 0.75, green: 0.20, blue: 0.25)
        case .gold: Color(red: 0.85, green: 0.65, blue: 0.15)
        case .neon: Color(red: 0.15, green: 0.90, blue: 0.45)
        }
    }

    /// Text color on the user's own bubbles (dark text on bright bubbles).
    var myText: Color {
        switch self {
        case .gold, .neon: .black
        default: .white
        }
    }

    /// Bubble color for the partner's messages.
    var partnerBubble: Color {
        switch self {
        case .classicLight: Color(red: 0.90, green: 0.90, blue: 0.92)
        case .paper: Color(red: 0.90, green: 0.89, blue: 0.86)
        case .sky, .mint, .rose, .lavender, .sand, .peach, .seafoam, .lemon: .white
        case .classicDark: Color(red: 0.20, green: 0.20, blue: 0.22)
        case .midnight: Color(red: 0.14, green: 0.17, blue: 0.26)
        case .graphite: Color(red: 0.19, green: 0.19, blue: 0.21)
        case .forest: Color(red: 0.12, green: 0.19, blue: 0.15)
        case .plum: Color(red: 0.19, green: 0.13, blue: 0.24)
        case .ocean: Color(red: 0.10, green: 0.18, blue: 0.23)
        case .ember: Color(red: 0.21, green: 0.15, blue: 0.12)
        case .crimson: Color(red: 0.20, green: 0.12, blue: 0.13)
        case .gold: Color(red: 0.20, green: 0.17, blue: 0.10)
        case .neon: Color(red: 0.15, green: 0.15, blue: 0.15)
        }
    }

    var partnerText: Color {
        Self.lightThemes.contains(self) ? .black : .white
    }

    /// Timestamp/metadata color that stays readable on the background.
    var metaText: Color {
        Self.lightThemes.contains(self) ? Color.black.opacity(0.45) : Color.white.opacity(0.5)
    }
}

// MARK: - Theme picker

/// Grid of chat theme preview cards (mini conversation mockups).
struct ChatThemePickerView: View {
    let title: String
    let themes: [ChatTheme]
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(themes) { theme in
                    ChatThemeCell(theme: theme, isSelected: selection == theme.rawValue) {
                        selection = theme.rawValue
                    }
                }
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ChatThemeCell: View {
    let theme: ChatTheme
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ChatThemePreview(theme: theme)
                    .aspectRatio(0.75, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(
                                isSelected ? Color.accentColor : Color.primary.opacity(0.15),
                                lineWidth: isSelected ? 3 : 1
                            )
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.title3)
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(.white, Color.accentColor)
                                .padding(6)
                        }
                    }

                Text(theme.localizedString)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.localizedString)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// Miniature conversation mockup: two bubbles on the theme background.
struct ChatThemePreview: View {
    let theme: ChatTheme

    var body: some View {
        ZStack {
            theme.background
            VStack(spacing: 8) {
                Capsule()
                    .fill(theme.partnerBubble)
                    .frame(width: 56, height: 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Capsule()
                    .fill(theme.myBubble)
                    .frame(width: 56, height: 18)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Capsule()
                    .fill(theme.partnerBubble)
                    .frame(width: 40, height: 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
    }
}
