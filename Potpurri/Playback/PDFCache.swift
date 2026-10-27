import Foundation
import ImageIO
import PDFKit
import UIKit

/// Håller nyss öppnade och nästa låts PDF:er i minnet så att låtbyten går direkt.
final class PDFCache: @unchecked Sendable {
    static let shared = PDFCache()
    private let cache = NSCache<NSURL, PDFDocument>()

    init() {
        cache.countLimit = 8
    }

    func document(for url: URL) -> PDFDocument? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let document = PDFDocument(url: url) else { return nil }
        cache.setObject(document, forKey: url as NSURL)
        return document
    }

    /// Läser in en PDF i bakgrunden (nästa låt i listan).
    func preload(_ url: URL) {
        guard cache.object(forKey: url as NSURL) == nil else { return }
        Task.detached(priority: .utility) {
            _ = self.document(for: url)
        }
    }
}

/// Bildlåtar läses in i bakgrunden, förminskade till vad skärmen behöver och färdigavkodade,
/// så att låtbytet inte väntar på att en stor kamerabild packas upp.
final class ImageCache: @unchecked Sendable {
    static let shared = ImageCache()
    private let cache = NSCache<NSURL, UIImage>()

    init() {
        cache.countLimit = 6
    }

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func image(for url: URL) async -> UIImage? {
        if let cached = cached(url) { return cached }
        let image = await Task.detached(priority: .userInitiated) { Self.decode(url) }.value
        if let image { cache.setObject(image, forKey: url as NSURL) }
        return image
    }

    func preload(_ url: URL) {
        guard cached(url) == nil else { return }
        Task.detached(priority: .utility) {
            if let image = Self.decode(url) { self.cache.setObject(image, forKey: url as NSURL) }
        }
    }

    private static func decode(_ url: URL) -> UIImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        // Räcker för hela skärmbredden även inzoomat.
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: 3600
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
