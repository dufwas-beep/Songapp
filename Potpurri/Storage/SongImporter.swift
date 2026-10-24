import Foundation
import SwiftData
import UniformTypeIdentifiers

struct ImportResult {
    var imported = 0
    var failed: [String] = []

    var summary: String {
        var lines = [imported == 1 ? "1 låt importerades." : "\(imported) låtar importerades."]
        if !failed.isEmpty {
            lines.append("Kunde inte importera: " + failed.joined(separator: ", "))
        }
        return lines.joined(separator: "\n")
    }
}

/// Importerar PDF:er och bilder som valts i Filer (där även Dropbox finns).
enum SongImporter {
    static let allowedTypes: [UTType] = [.pdf, .image]

    @MainActor
    static func importFiles(_ urls: [URL], into context: ModelContext) -> ImportResult {
        var result = ImportResult()
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            guard let kind = kind(of: url) else {
                result.failed.append(url.lastPathComponent)
                continue
            }
            do {
                let fileName = try SongFileStore.importCopy(of: url)
                // Låtens namn är filnamnet utan ändelse.
                let title = url.deletingPathExtension().lastPathComponent
                context.insert(Song(title: title, kind: kind, fileName: fileName))
                result.imported += 1
            } catch {
                result.failed.append(url.lastPathComponent)
            }
        }
        try? context.save()
        return result
    }

    static func kind(of url: URL) -> SongKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        return nil
    }
}
