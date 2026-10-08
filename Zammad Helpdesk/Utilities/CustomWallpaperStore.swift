import SwiftUI
import UIKit

/// Holds the user's own wallpaper photos, one for light and one for dark mode.
/// Files live in the app group container so a future widget or the watch
/// bridge can reach them; the decoded images are cached here so the
/// background does not re-read a JPEG on every redraw.
@MainActor
final class CustomWallpaperStore: ObservableObject {
    static let shared = CustomWallpaperStore()

    @Published private(set) var lightImage: UIImage?
    @Published private(set) var darkImage: UIImage?

    /// Longest side a stored photo is scaled down to. Enough for any phone
    /// screen, small enough that decoding and keeping two in memory is cheap.
    private static let maxPixelSize: CGFloat = 2400

    private let directory: URL?

    private init() {
        let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.World-ICT.Zammad-Helpdesk")
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        directory = container?.appendingPathComponent("Wallpapers", isDirectory: true)
        lightImage = load(.light)
        darkImage = load(.dark)
    }

    func image(for mode: WallpaperMode) -> UIImage? {
        mode == .dark ? darkImage : lightImage
    }

    func hasImage(for mode: WallpaperMode) -> Bool {
        image(for: mode) != nil
    }

    /// Scales the photo down, writes it as JPEG and makes it the current
    /// wallpaper for `mode`. Returns false when the file could not be written.
    @discardableResult
    func save(_ image: UIImage, for mode: WallpaperMode) -> Bool {
        guard let directory else { return false }
        let scaled = Self.downscaled(image)
        guard let data = scaled.jpegData(compressionQuality: 0.85) else { return false }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: fileURL(for: mode), options: .atomic)
        } catch {
            print("DEBUG: [Wallpaper] Opslaan mislukt: \(error.localizedDescription)")
            return false
        }
        set(scaled, for: mode)
        return true
    }

    func remove(for mode: WallpaperMode) {
        try? FileManager.default.removeItem(at: fileURL(for: mode))
        set(nil, for: mode)
    }

    private func set(_ image: UIImage?, for mode: WallpaperMode) {
        if mode == .dark { darkImage = image } else { lightImage = image }
    }

    private func fileURL(for mode: WallpaperMode) -> URL {
        (directory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("\(mode.rawValue).jpg")
    }

    private func load(_ mode: WallpaperMode) -> UIImage? {
        guard let data = try? Data(contentsOf: fileURL(for: mode)) else { return nil }
        return UIImage(data: data)
    }

    /// Redraws the image at most `maxPixelSize` on its longest side, which also
    /// bakes in the EXIF orientation so the stored file displays upright.
    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height) * image.scale
        let ratio = min(1, maxPixelSize / max(longest, 1))
        let targetSize = CGSize(width: image.size.width * image.scale * ratio,
                                height: image.size.height * image.scale * ratio)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
