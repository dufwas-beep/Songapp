import Foundation
import SwiftData

/// Automatisk säkerhetskopia en gång i veckan till en mapp man valt i Filer
/// (t.ex. iCloud Drive). Görs när appen öppnas och det gått en vecka sedan sist.
/// De fyra senaste kopiorna sparas, äldre tas bort.
@MainActor
enum AutoBackup {
    private static let bookmarkKey = "autoBackupFolder"
    private static let lastKey = "autoBackupLast"
    static let prefix = "Potpurri autokopia "
    private static let keep = 4
    private static let interval: TimeInterval = 7 * 24 * 3600
    private static var running = false

    static var lastBackup: Date? {
        UserDefaults.standard.object(forKey: lastKey) as? Date
    }

    static var isOn: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Namnet på mappen som kopiorna sparas i.
    static var folderName: String? {
        folder()?.lastPathComponent
    }

    static func setFolder(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(data, forKey: bookmarkKey)
    }

    static func turnOff() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    private static func folder() -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        if stale { try? setFolder(url) }
        return url
    }

    /// Körs när appen öppnas. Gör en kopia om det gått en vecka (eller `force`).
    static func runIfDue(context: ModelContext, colorNames: [String], force: Bool = false) async throws {
        guard !running, let folder = folder() else { return }
        if !force, let last = lastBackup, Date().timeIntervalSince(last) < interval { return }
        running = true
        defer { running = false }
        let file = try await Backup.export(context: context, colorNames: colorNames, progress: TaskProgress())
        defer { try? FileManager.default.removeItem(at: file) }
        let accessing = folder.startAccessingSecurityScopedResource()
        defer { if accessing { folder.stopAccessingSecurityScopedResource() } }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let target = folder.appendingPathComponent(prefix + formatter.string(from: Date()) + ".potpurri")
        // Samordnad skrivning så att iCloud Drive inte krockar med kopian.
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: target, options: .forReplacing, error: &coordinationError) { url in
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: file, to: url)
            } catch {
                writeError = error
            }
        }
        if let error = coordinationError ?? writeError { throw error }
        UserDefaults.standard.set(Date(), forKey: lastKey)
        removeOld(in: folder)
    }

    private static func removeOld(in folder: URL) {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let backups = files.filter { $0.lastPathComponent.hasPrefix(prefix) }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in backups.dropFirst(keep) {
            try? FileManager.default.removeItem(at: old)
        }
    }
}
