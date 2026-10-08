import SwiftUI
import PhotosUI

/// Grid of wallpaper thumbnails and color swatches for choosing a background,
/// plus a slot for the user's own photo.
struct BackgroundPickerView: View {
    let title: String
    let mode: WallpaperMode
    let wallpapers: [BackgroundOption]
    let colors: [BackgroundOption]
    @Binding var selection: String

    @ObservedObject private var customStore = CustomWallpaperStore.shared
    @State private var photoSelection: PhotosPickerItem?
    @State private var isImportingPhoto = false

    private let columns = [GridItem(.adaptive(minimum: 96, maximum: 130), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                customSection
                optionSection(header: "wallpapers".localized(), options: wallpapers)
                optionSection(header: "solid_colors".localized(), options: colors)
            }
            .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoSelection) { _, item in
            guard let item else { return }
            importPhoto(item)
        }
    }

    // MARK: - Custom photo

    private var customOption: BackgroundOption { .custom(for: mode) }

    private var customSection: some View {
        // Read once: the PhotosPicker label closure is not main-actor isolated.
        let hasPhoto = customStore.hasImage(for: mode)
        let pickerTitle = (hasPhoto ? "change_photo" : "choose_photo").localized()
        return VStack(alignment: .leading, spacing: 12) {
            sectionHeader("custom_wallpaper_section".localized())

            HStack(alignment: .top, spacing: 16) {
                if hasPhoto {
                    BackgroundOptionCell(option: customOption, isSelected: selection == customOption.rawValue) {
                        selection = customOption.rawValue
                    }
                    .frame(maxWidth: 130)
                }

                VStack(alignment: .leading, spacing: 10) {
                    PhotosPicker(selection: $photoSelection, matching: .images, photoLibrary: .shared()) {
                        Label(pickerTitle, systemImage: "photo.on.rectangle")
                    }
                    .disabled(isImportingPhoto)

                    if hasPhoto {
                        Button(role: .destructive) {
                            removePhoto()
                        } label: {
                            Label("remove_photo".localized(), systemImage: "trash")
                        }
                    }

                    if isImportingPhoto {
                        ProgressView()
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    /// Reads the picked photo, hands it to the store (which scales and saves
    /// it) and makes it the active background for this mode.
    private func importPhoto(_ item: PhotosPickerItem) {
        isImportingPhoto = true
        Task {
            defer {
                isImportingPhoto = false
                photoSelection = nil
            }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data) else { return }
            if customStore.save(image, for: mode) {
                selection = customOption.rawValue
            }
        }
    }

    /// Deletes the photo; if it was the active background the mode falls back
    /// to its default wallpaper so the selection never points at nothing.
    private func removePhoto() {
        customStore.remove(for: mode)
        if selection == customOption.rawValue {
            selection = BackgroundOption.defaultOption(for: mode).rawValue
        }
    }

    // MARK: - Built-in options

    private func optionSection(header: String, options: [BackgroundOption]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader(header)

            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(options) { option in
                    BackgroundOptionCell(option: option, isSelected: selection == option.rawValue) {
                        selection = option.rawValue
                    }
                }
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
            .padding(.leading, 4)
    }
}

/// Renders a background option's preview: catalog thumbnail, solid color, or
/// the user's own photo. Shared by the picker grid and the Settings swatch.
struct BackgroundPreview: View {
    let option: BackgroundOption
    @ObservedObject private var customStore = CustomWallpaperStore.shared

    init(option: BackgroundOption) {
        self.option = option
    }

    var body: some View {
        switch option.previewStyle {
        case .image(let name):
            Image(name)
                .resizable()
                .aspectRatio(contentMode: .fill)
        case .color(let color):
            color
        case .custom(let mode):
            if let image = customStore.image(for: mode) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                BackgroundPreview(option: .defaultOption(for: mode))
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
                    .overlay { BackgroundPreview(option: option) }
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

#Preview {
    NavigationStack {
        BackgroundPickerView(
            title: "Dark mode background",
            mode: .dark,
            wallpapers: BackgroundOption.darkWallpapers,
            colors: BackgroundOption.darkColors,
            selection: .constant(BackgroundOption.pebbles.rawValue)
        )
    }
}
