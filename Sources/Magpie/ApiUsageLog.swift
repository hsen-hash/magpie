import Foundation
import SQLite3

struct ApiUsageRecord: Identifiable, Hashable {
    let id: Int64
    let timestamp: Date
    let model: String
    let filenameCount: Int
    let promptTokens: Int
    let candidateTokens: Int
    let totalTokens: Int
    let httpStatus: Int
}

struct ApiUsageTotals {
    var calls: Int = 0
    var promptTokens: Int = 0
    var candidateTokens: Int = 0
    var totalTokens: Int = 0
    var filenamesProcessed: Int = 0
}

/// Default Gemini 2.5 Flash pricing (USD per 1M tokens).
struct PricingTable {
    var inputPerMillion: Double = 0.30
    var outputPerMillion: Double = 2.50

    func cost(prompt: Int, output: Int) -> Double {
        let inCost = Double(prompt) / 1_000_000.0 * inputPerMillion
        let outCost = Double(output) / 1_000_000.0 * outputPerMillion
        return inCost + outCost
    }
}

final class ApiUsageLog {
    private static let TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )
    private let queue = DispatchQueue(label: "magpie.apiusage")
    private var db: OpaquePointer?

    init(path: URL) {
        try? FileManager.default.createDirectory(
            at: path.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if sqlite3_open(path.path, &db) != SQLITE_OK { return }
        let sql = """
        CREATE TABLE IF NOT EXISTS api_calls (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp REAL NOT NULL,
            model TEXT NOT NULL,
            filename_count INTEGER NOT NULL,
            prompt_tokens INTEGER NOT NULL,
            candidate_tokens INTEGER NOT NULL,
            total_tokens INTEGER NOT NULL,
            http_status INTEGER NOT NULL
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    deinit { if let db { sqlite3_close(db) } }

    func record(model: String,
                filenameCount: Int,
                promptTokens: Int,
                candidateTokens: Int,
                totalTokens: Int,
                httpStatus: Int) {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT INTO api_calls (timestamp, model, filename_count, prompt_tokens, candidate_tokens, total_tokens, http_status)
            VALUES (?, ?, ?, ?, ?, ?, ?);
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, model, -1, Self.TRANSIENT)
            sqlite3_bind_int(stmt, 3, Int32(filenameCount))
            sqlite3_bind_int(stmt, 4, Int32(promptTokens))
            sqlite3_bind_int(stmt, 5, Int32(candidateTokens))
            sqlite3_bind_int(stmt, 6, Int32(totalTokens))
            sqlite3_bind_int(stmt, 7, Int32(httpStatus))
            _ = sqlite3_step(stmt)
        }
    }

    func totals(since: Date? = nil) -> ApiUsageTotals {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql: String
            if since != nil {
                sql = """
                SELECT COUNT(*), COALESCE(SUM(prompt_tokens), 0), COALESCE(SUM(candidate_tokens), 0),
                       COALESCE(SUM(total_tokens), 0), COALESCE(SUM(filename_count), 0)
                FROM api_calls WHERE timestamp >= ?;
                """
            } else {
                sql = """
                SELECT COUNT(*), COALESCE(SUM(prompt_tokens), 0), COALESCE(SUM(candidate_tokens), 0),
                       COALESCE(SUM(total_tokens), 0), COALESCE(SUM(filename_count), 0)
                FROM api_calls;
                """
            }
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return ApiUsageTotals() }
            if let since {
                sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)
            }
            var t = ApiUsageTotals()
            if sqlite3_step(stmt) == SQLITE_ROW {
                t.calls = Int(sqlite3_column_int(stmt, 0))
                t.promptTokens = Int(sqlite3_column_int(stmt, 1))
                t.candidateTokens = Int(sqlite3_column_int(stmt, 2))
                t.totalTokens = Int(sqlite3_column_int(stmt, 3))
                t.filenamesProcessed = Int(sqlite3_column_int(stmt, 4))
            }
            return t
        }
    }

    func recent(limit: Int) -> [ApiUsageRecord] {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            SELECT id, timestamp, model, filename_count, prompt_tokens, candidate_tokens, total_tokens, http_status
            FROM api_calls ORDER BY id DESC LIMIT ?;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var result: [ApiUsageRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let ts = sqlite3_column_double(stmt, 1)
                let model = String(cString: sqlite3_column_text(stmt, 2))
                result.append(ApiUsageRecord(
                    id: id,
                    timestamp: Date(timeIntervalSince1970: ts),
                    model: model,
                    filenameCount: Int(sqlite3_column_int(stmt, 3)),
                    promptTokens: Int(sqlite3_column_int(stmt, 4)),
                    candidateTokens: Int(sqlite3_column_int(stmt, 5)),
                    totalTokens: Int(sqlite3_column_int(stmt, 6)),
                    httpStatus: Int(sqlite3_column_int(stmt, 7))
                ))
            }
            return result
        }
    }
}
