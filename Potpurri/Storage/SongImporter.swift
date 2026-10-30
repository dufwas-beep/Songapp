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
    static let allowedTypes: [UTType] = [.pdf, .image, .plainText]

    @MainActor
    static func importFiles(_ urls: [URL], into context: ModelContext, progress: TaskProgress) async -> ImportResult {
        var result = ImportResult()
        progress.start("Importerar låtar", total: urls.count)
        AppLog.info("Importerar \(urls.count) fil(er): \(urls.map(\.lastPathComponent).joined(separator: ", "))")
        for url in urls {
            // Låtens namn är filnamnet utan ändelse.
            let title = url.deletingPathExtension().lastPathComponent
            progress.currentName = title
            if kind(of: url) == .note, let text = await readTextInBackground(url) {
                AppLog.info("Läste textfilen \"\(url.lastPathComponent)\" (\(text.count) tecken, \(text.split(separator: "\n", omittingEmptySubsequences: false).count) rader)")
                context.insert(Song(title: title, kind: .note, text: text))
                result.imported += 1
            } else if let kind = kind(of: url), kind != .note, let fileName = await copyInBackground(url) {
                context.insert(Song(title: title, kind: kind, fileName: fileName))
                result.imported += 1
            } else {
                AppLog.problem("Kunde inte importera \"\(url.lastPathComponent)\"")
                result.failed.append(url.lastPathComponent)
            }
            progress.done += 1
        }
        do {
            try context.save()
        } catch {
            AppLog.problem("Importen kunde inte sparas: \(error.localizedDescription)")
        }
        progress.finish()
        AppLog.info("Importen klar: \(result.imported) av \(urls.count)")
        return result
    }

    /// Kopierar filen utan att låsa skärmen. Filer i Dropbox/iCloud som inte finns
    /// på iPaden laddas ner först (via filkoordinatorn), vilket kan ta en stund.
    private static func copyInBackground(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            var fileName: String?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
                fileName = try? SongFileStore.importCopy(of: readURL)
            }
            return fileName
        }.value
    }

    /// Läser en textfil (anteckning, t.ex. quizmanus) i bakgrunden.
    private static func readTextInBackground(_ url: URL) async -> String? {
        await Task.detached(priority: .userInitiated) { () -> String? in
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing { url.stopAccessingSecurityScopedResource() }
            }
            var text: String?
            var coordinationError: NSError?
            NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readURL in
                if let data = try? Data(contentsOf: readURL) {
                    text = OnSongBackup.decodeText(data)
                }
            }
            return text
        }.value
    }

    static func kind(of url: URL) -> SongKind? {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return nil }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .plainText) { return .note }
        return nil
    }
}
