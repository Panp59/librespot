import Foundation
import SQLite3

/// Une plage d'activité continue : même app, même fenêtre.
struct WorkSession {
    var id: Int64 = 0
    var start: Date
    var end: Date
    var bundle: String
    var app: String
    var title: String

    var duration: TimeInterval { end.timeIntervalSince(start) }
}

/// Persistance SQLite, tout en local dans Application Support.
/// Le suivi du temps est une donnée sensible : elle ne quitte jamais ce Mac.
final class Store {
    static let shared = Store()

    static var dataDirectory: URL {
        let dir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("Sablier")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var db: OpaquePointer?
    private let transient = unsafeBitCast(
        OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self
    )

    private init() {
        let path = Self.dataDirectory.appendingPathComponent("sablier.db").path
        if sqlite3_open(path, &db) != SQLITE_OK {
            NSLog("Sablier: impossible d'ouvrir la base %@", path)
            return
        }
        exec("""
        CREATE TABLE IF NOT EXISTS sessions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            start REAL NOT NULL,
            end REAL NOT NULL,
            bundle TEXT NOT NULL,
            app TEXT NOT NULL,
            title TEXT NOT NULL DEFAULT ''
        );
        """)
        exec("CREATE INDEX IF NOT EXISTS idx_sessions_start ON sessions(start);")
    }

    private func exec(_ sql: String) {
        var errorMessage: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &errorMessage) != SQLITE_OK {
            if let errorMessage {
                NSLog("Sablier: erreur SQL: %@", String(cString: errorMessage))
                sqlite3_free(errorMessage)
            }
        }
    }

    /// Insère une session et retourne son identifiant.
    func insert(_ session: WorkSession) -> Int64 {
        var statement: OpaquePointer?
        let sql = "INSERT INTO sessions(start, end, bundle, app, title) VALUES(?,?,?,?,?);"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return 0 }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, session.start.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, session.end.timeIntervalSince1970)
        sqlite3_bind_text(statement, 3, session.bundle, -1, transient)
        sqlite3_bind_text(statement, 4, session.app, -1, transient)
        sqlite3_bind_text(statement, 5, session.title, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else { return 0 }
        return sqlite3_last_insert_rowid(db)
    }

    /// Prolonge une session en cours (appelé à chaque échantillon).
    func updateEnd(id: Int64, end: Date) {
        var statement: OpaquePointer?
        let sql = "UPDATE sessions SET end = ? WHERE id = ?;"
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, end.timeIntervalSince1970)
        sqlite3_bind_int64(statement, 2, id)
        sqlite3_step(statement)
    }

    /// Sessions recoupant l'intervalle [from, to], rognées à cet intervalle.
    /// Les états « absent » (écran verrouillé, économiseur) sont exclus, y
    /// compris rétroactivement pour les données enregistrées avant le correctif.
    func sessions(from: Date, to: Date) -> [WorkSession] {
        var statement: OpaquePointer?
        let awayList = Sampler.awayBundleIDs
            .map { "'\($0)'" }
            .joined(separator: ",")
        let sql = """
        SELECT id, start, end, bundle, app, title FROM sessions
        WHERE end > ? AND start < ? AND bundle NOT IN (\(awayList)) ORDER BY start;
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_double(statement, 1, from.timeIntervalSince1970)
        sqlite3_bind_double(statement, 2, to.timeIntervalSince1970)

        var result: [WorkSession] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let start = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
            let end = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
            let bundle = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
            let app = sqlite3_column_text(statement, 4).map { String(cString: $0) } ?? ""
            let title = sqlite3_column_text(statement, 5).map { String(cString: $0) } ?? ""
            result.append(WorkSession(
                id: sqlite3_column_int64(statement, 0),
                start: max(start, from),
                end: min(end, to),
                bundle: bundle,
                app: app,
                title: title
            ))
        }
        return result
    }

    /// Total d'activité sur un intervalle (pour la barre de menus).
    func totalDuration(from: Date, to: Date) -> TimeInterval {
        sessions(from: from, to: to).reduce(0) { $0 + $1.duration }
    }

    /// Efface tout l'historique. Irréversible, sur confirmation uniquement.
    func deleteAll() {
        exec("DELETE FROM sessions;")
        exec("VACUUM;")
    }
}

/// Formatage des durées : "2 h 05", "38 min", "45 s".
func formatDuration(_ interval: TimeInterval) -> String {
    let seconds = Int(interval.rounded())
    if seconds < 60 { return "\(seconds) s" }
    let minutes = seconds / 60
    if minutes < 60 { return "\(minutes) min" }
    return String(format: "%d h %02d", minutes / 60, minutes % 60)
}
