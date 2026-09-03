import SwiftUI

/// Grid of wallpaper thumbnails and color swatches for choosing a background.
struct BackgroundPickerView: View {
    let title: String
    let wallpapers: [BackgroundOption]
    let colors: [BackgroundOption]
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                optionSection(header: "wallpapers".localized(), options: wallpapers)
                optionSection(header: "solid_colors".localized(), options: colors)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func optionSection(header: String, options: [BackgroundOption]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(header)
                .font(.footnote)
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.leading, 4)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(options) { option in
                    BackgroundOptionCell(option: option, isSelected: selection == option.rawValue) {
                        selection = option.rawValue
                    }
                }
            }
        }
    }
}

/// A tappable thumbnail card with a selection ring and checkmark badge.
private struct BackgroundOptionCell: View {
    let option: BackgroundOption
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Color.clear
                    .aspectRatio(9.0 / 16.0, contentMode: .fit)
                    .overlay {
                        switch option.previewStyle {
                        case .image(let name):
                            Image(name)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        case .color(let color):
                            color
                        }
                    }
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

                Text(option.localizedString)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(option.localizedString)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}
