import Foundation
import SQLite3

/// Enkel läsare för en SQLite-databas (OnSongs databas i backupen). Bara läsning.
final class SQLiteReader {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private var db: OpaquePointer?

    init(url: URL) throws {
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "okänt fel"
            sqlite3_close(db)
            db = nil
            throw Failure(message: "Databasen kunde inte öppnas: \(message)")
        }
    }

    deinit {
        sqlite3_close(db)
    }

    /// Kör en fråga och returnerar raderna som [kolumnnamn: text]. Tomma värden utelämnas.
    func rows(_ sql: String) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Failure(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        var result: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for column in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, column))
                if let text = sqlite3_column_text(statement, column) {
                    row[name] = String(cString: text)
                }
            }
            result.append(row)
        }
        return result
    }
}
