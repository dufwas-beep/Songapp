import Foundation

/// Låtfilerna sparas som kopior i appens egen mapp (Application Support/Songs),
/// så att de finns kvar även om originalet i Filer flyttas eller tas bort.
enum SongFileStore {
    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Songs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func url(for fileName: String) -> URL {
        directory.appendingPathComponent(fileName)
    }

    /// Kopierar in en fil och returnerar det nya, unika filnamnet.
    static func importCopy(of source: URL) throws -> String {
        let ext = source.pathExtension.lowercased()
        let name = UUID().uuidString + (ext.isEmpty ? "" : "." + ext)
        try FileManager.default.copyItem(at: source, to: url(for: name))
        return name
    }

    /// Sparar data (t.ex. en fil ur en OnSong-backup) och returnerar det nya filnamnet.
    static func store(_ data: Data, pathExtension ext: String) throws -> String {
        let name = UUID().uuidString + (ext.isEmpty ? "" : "." + ext.lowercased())
        try data.write(to: url(for: name), options: .atomic)
        return name
    }

    static func delete(_ fileName: String) {
        guard !fileName.isEmpty else { return }
        try? FileManager.default.removeItem(at: url(for: fileName))
    }
}
