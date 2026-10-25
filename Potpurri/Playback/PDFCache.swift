import Foundation
import PDFKit

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
