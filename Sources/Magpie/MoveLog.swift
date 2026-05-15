import Foundation
import SQLite3

struct MoveRecord: Identifiable, Hashable {
    let id: Int64
    let originalPath: String
    let newPath: String
    let timestamp: Date
    let reverted: Bool
    let reason: String?
    let source: String?       // "rule" | "llm" | nil for legacy rows
}

/// Tiny SQLite-backed move log. No external deps — uses the libsqlite3 system library.
final class MoveLog {
    // SQLITE_TRANSIENT macro isn't auto-imported into Swift
    private static let TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    private let queue = DispatchQueue(label: "magpie.movelog")
    private var db: OpaquePointer?

    init(path: URL) {
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if sqlite3_open(path.path, &db) != SQLITE_OK {
            NSLog("Magpie: failed to open \(path.path)")
            return
        }
        let createSQL = """
        CREATE TABLE IF NOT EXISTS moves (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            original_path TEXT NOT NULL,
            new_path TEXT NOT NULL,
            timestamp REAL NOT NULL,
            reverted INTEGER NOT NULL DEFAULT 0,
            reason TEXT,
            source TEXT
        );
        """
        sqlite3_exec(db, createSQL, nil, nil, nil)
        addColumnIfMissing(table: "moves", column: "reason", definition: "TEXT")
        addColumnIfMissing(table: "moves", column: "source", definition: "TEXT")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    private func addColumnIfMissing(table: String, column: String, definition: String) {
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let info = "PRAGMA table_info(\(table));"
        guard sqlite3_prepare_v2(db, info, -1, &stmt, nil) == SQLITE_OK else { return }
        while sqlite3_step(stmt) == SQLITE_ROW {
            let name = String(cString: sqlite3_column_text(stmt, 1))
            if name == column { return }
        }
        let alter = "ALTER TABLE \(table) ADD COLUMN \(column) \(definition);"
        sqlite3_exec(db, alter, nil, nil, nil)
        NSLog("Magpie: migrated SQLite — added \(table).\(column)")
    }

    @discardableResult
    func record(from source: URL,
                to destination: URL,
                reason: String? = nil,
                sourceKind: String? = nil) -> Int64? {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = """
            INSERT INTO moves (original_path, new_path, timestamp, reason, source)
            VALUES (?, ?, ?, ?, ?);
            """
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            sqlite3_bind_text(stmt, 1, source.path, -1, Self.TRANSIENT)
            sqlite3_bind_text(stmt, 2, destination.path, -1, Self.TRANSIENT)
            sqlite3_bind_double(stmt, 3, Date().timeIntervalSince1970)
            if let reason {
                sqlite3_bind_text(stmt, 4, reason, -1, Self.TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 4)
            }
            if let sourceKind {
                sqlite3_bind_text(stmt, 5, sourceKind, -1, Self.TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 5)
            }
            guard sqlite3_step(stmt) == SQLITE_DONE else { return nil }
            return sqlite3_last_insert_rowid(db)
        }
    }

    func recent(limit: Int) -> [MoveRecord] {
        queue.sync {
            var stmt: OpaquePointer?
            let sql = """
            SELECT id, original_path, new_path, timestamp, reverted, reason, source
            FROM moves
            ORDER BY id DESC
            LIMIT ?;
            """
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int(stmt, 1, Int32(limit))

            var results: [MoveRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let from = String(cString: sqlite3_column_text(stmt, 1))
                let to = String(cString: sqlite3_column_text(stmt, 2))
                let ts = sqlite3_column_double(stmt, 3)
                let reverted = sqlite3_column_int(stmt, 4) != 0
                let reason: String? = sqlite3_column_type(stmt, 5) == SQLITE_NULL
                    ? nil : String(cString: sqlite3_column_text(stmt, 5))
                let src: String? = sqlite3_column_type(stmt, 6) == SQLITE_NULL
                    ? nil : String(cString: sqlite3_column_text(stmt, 6))
                results.append(MoveRecord(
                    id: id,
                    originalPath: from,
                    newPath: to,
                    timestamp: Date(timeIntervalSince1970: ts),
                    reverted: reverted,
                    reason: reason,
                    source: src
                ))
            }
            return results
        }
    }

    func markReverted(id: Int64) {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = "UPDATE moves SET reverted = 1 WHERE id = ?;"
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_int64(stmt, 1, id)
            _ = sqlite3_step(stmt)
        }
    }
}
