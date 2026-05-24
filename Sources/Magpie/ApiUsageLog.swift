import Foundation
import SQLite3

struct ApiUsageRecord: Identifiable, Hashable {
    let id: Int64
    let timestamp: Date
    /// Provider family this call was billed against (e.g. "gemini", "ollama").
    /// Older rows written before this column existed default to "gemini".
    let provider: String
    let model: String
    let filenameCount: Int
    let promptTokens: Int
    let candidateTokens: Int
    let totalTokens: Int
    let httpStatus: Int

    var isLocal: Bool { CategorizerProvider(rawValue: provider)?.isLocal ?? false }
}

struct ApiUsageTotals {
    var calls: Int = 0
    var promptTokens: Int = 0
    var candidateTokens: Int = 0
    var totalTokens: Int = 0
    var filenamesProcessed: Int = 0
    /// Token counts coming from local providers (Ollama). These cost $0
    /// regardless of volume but still contribute to the total token tally.
    var localPromptTokens: Int = 0
    var localCandidateTokens: Int = 0
}

/// Default Gemini 2.5 Flash pricing (USD per 1M tokens). Ollama calls are free.
struct PricingTable {
    var inputPerMillion: Double = 0.30
    var outputPerMillion: Double = 2.50

    func cost(prompt: Int, output: Int) -> Double {
        let inCost = Double(prompt) / 1_000_000.0 * inputPerMillion
        let outCost = Double(output) / 1_000_000.0 * outputPerMillion
        return inCost + outCost
    }

    /// Cost for an aggregate, excluding tokens routed through local providers.
    func cost(for totals: ApiUsageTotals) -> Double {
        cost(
            prompt: totals.promptTokens - totals.localPromptTokens,
            output: totals.candidateTokens - totals.localCandidateTokens
        )
    }

    /// Cost for a single recorded call. Local providers are always $0.
    func cost(for record: ApiUsageRecord) -> Double {
        record.isLocal ? 0 : cost(prompt: record.promptTokens, output: record.candidateTokens)
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
            http_status INTEGER NOT NULL,
            provider TEXT NOT NULL DEFAULT 'gemini'
        );
        """
        sqlite3_exec(db, sql, nil, nil, nil)
        // Add the `provider` column when migrating from a pre-Ollama install.
        // SQLite raises if the column already exists — that's fine, we ignore it.
        sqlite3_exec(db,
            "ALTER TABLE api_calls ADD COLUMN provider TEXT NOT NULL DEFAULT 'gemini';",
            nil, nil, nil)
    }

    deinit { if let db { sqlite3_close(db) } }

    func record(provider: String,
                model: String,
                filenameCount: Int,
                promptTokens: Int,
                candidateTokens: Int,
                totalTokens: Int,
                httpStatus: Int) {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            INSERT INTO api_calls (timestamp, provider, model, filename_count, prompt_tokens, candidate_tokens, total_tokens, http_status)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?);
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
            sqlite3_bind_double(stmt, 1, Date().timeIntervalSince1970)
            sqlite3_bind_text(stmt, 2, provider, -1, Self.TRANSIENT)
            sqlite3_bind_text(stmt, 3, model, -1, Self.TRANSIENT)
            sqlite3_bind_int(stmt, 4, Int32(filenameCount))
            sqlite3_bind_int(stmt, 5, Int32(promptTokens))
            sqlite3_bind_int(stmt, 6, Int32(candidateTokens))
            sqlite3_bind_int(stmt, 7, Int32(totalTokens))
            sqlite3_bind_int(stmt, 8, Int32(httpStatus))
            _ = sqlite3_step(stmt)
        }
    }

    func totals(since: Date? = nil) -> ApiUsageTotals {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            // Tracks local-provider tokens separately so the pricing logic
            // can subtract them out when computing dollar costs.
            let sql: String
            if since != nil {
                sql = """
                SELECT
                    COUNT(*),
                    COALESCE(SUM(prompt_tokens), 0),
                    COALESCE(SUM(candidate_tokens), 0),
                    COALESCE(SUM(total_tokens), 0),
                    COALESCE(SUM(filename_count), 0),
                    COALESCE(SUM(CASE WHEN provider = 'ollama' THEN prompt_tokens ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN provider = 'ollama' THEN candidate_tokens ELSE 0 END), 0)
                FROM api_calls WHERE timestamp >= ?;
                """
            } else {
                sql = """
                SELECT
                    COUNT(*),
                    COALESCE(SUM(prompt_tokens), 0),
                    COALESCE(SUM(candidate_tokens), 0),
                    COALESCE(SUM(total_tokens), 0),
                    COALESCE(SUM(filename_count), 0),
                    COALESCE(SUM(CASE WHEN provider = 'ollama' THEN prompt_tokens ELSE 0 END), 0),
                    COALESCE(SUM(CASE WHEN provider = 'ollama' THEN candidate_tokens ELSE 0 END), 0)
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
                t.localPromptTokens = Int(sqlite3_column_int(stmt, 5))
                t.localCandidateTokens = Int(sqlite3_column_int(stmt, 6))
            }
            return t
        }
    }

    func recent(limit: Int) -> [ApiUsageRecord] {
        queue.sync {
            var stmt: OpaquePointer?
            defer { sqlite3_finalize(stmt) }
            let sql = """
            SELECT id, timestamp, model, filename_count, prompt_tokens, candidate_tokens, total_tokens, http_status, provider
            FROM api_calls ORDER BY id DESC LIMIT ?;
            """
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
            sqlite3_bind_int(stmt, 1, Int32(limit))
            var result: [ApiUsageRecord] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let id = sqlite3_column_int64(stmt, 0)
                let ts = sqlite3_column_double(stmt, 1)
                let model = String(cString: sqlite3_column_text(stmt, 2))
                let providerPtr = sqlite3_column_text(stmt, 8)
                let provider = providerPtr.map { String(cString: $0) } ?? "gemini"
                result.append(ApiUsageRecord(
                    id: id,
                    timestamp: Date(timeIntervalSince1970: ts),
                    provider: provider,
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
