import Foundation
import SQLite3
final class SQLiteStore {
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "fr.read-write.wiredsyncd.sqlite")

    init(path: String) throws {
        if sqlite3_open(path, &db) != SQLITE_OK {
            throw NSError(domain: "wiredsyncd", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to open sqlite db"])
        }
        try configureDatabase()
        try execute("""
        CREATE TABLE IF NOT EXISTS sync_pairs (
          id TEXT PRIMARY KEY,
          remote_path TEXT NOT NULL,
          local_path TEXT NOT NULL,
          mode TEXT NOT NULL,
          delete_remote_enabled INTEGER NOT NULL DEFAULT 0,
          exclude_patterns TEXT NOT NULL DEFAULT '',
          endpoint_json TEXT NOT NULL,
          paused INTEGER NOT NULL,
          created_at REAL NOT NULL,
          updated_at REAL NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS op_queue (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          pair_id TEXT NOT NULL,
          op_kind TEXT NOT NULL,
          payload TEXT NOT NULL,
          created_at REAL NOT NULL
        );
        """)
        try execute("""
        CREATE TABLE IF NOT EXISTS uploaded_items (
          pair_id TEXT NOT NULL,
          relative_path TEXT NOT NULL,
          size INTEGER NOT NULL,
          modification_time REAL NOT NULL,
          updated_at REAL NOT NULL,
          PRIMARY KEY(pair_id, relative_path)
        );
        """)
        try execute("ALTER TABLE sync_pairs ADD COLUMN delete_remote_enabled INTEGER NOT NULL DEFAULT 0;")
        try execute("ALTER TABLE sync_pairs ADD COLUMN exclude_patterns TEXT NOT NULL DEFAULT '';")
        try execute("ALTER TABLE sync_pairs ADD COLUMN endpoint_json TEXT;")
    }

    deinit {
        let handle = queue.sync { db }
        if let handle { sqlite3_close(handle) }
    }

    func execute(_ sql: String) throws {
        try queue.sync {
            guard let db else { return }
            var err: UnsafeMutablePointer<Int8>?
            if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
                let msg = err.map { String(cString: $0) } ?? sqliteMessage(db)
                sqlite3_free(err)
                // Ignore duplicate-column migration attempt
                if msg.localizedCaseInsensitiveContains("duplicate column") {
                    return
                }
                throw NSError(domain: "wiredsyncd", code: 2, userInfo: [NSLocalizedDescriptionKey: msg])
            }
        }
    }

    func upsert(pair: SyncPair) throws {
        let endpointData = try JSONEncoder().encode(pair.endpoint)
        let endpointJSON = String(decoding: endpointData, as: UTF8.self)
        let excludePatternsJSON = pair.excludePatterns.joined(separator: "\n")

        try queue.sync {
            guard let db else { return }
            let sql = """
            INSERT INTO sync_pairs(id, remote_path, local_path, mode, delete_remote_enabled, exclude_patterns, endpoint_json, paused, created_at, updated_at)
            VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
              remote_path=excluded.remote_path,
              local_path=excluded.local_path,
              mode=excluded.mode,
              delete_remote_enabled=excluded.delete_remote_enabled,
              exclude_patterns=excluded.exclude_patterns,
              endpoint_json=excluded.endpoint_json,
              paused=excluded.paused,
              updated_at=excluded.updated_at;
            """
            var stmt: OpaquePointer?
            try prepare(db, sql: sql, into: &stmt)
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, pair.id, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 2, pair.remotePath, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 3, pair.localPath, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 4, pair.mode.rawValue, -1, SQLiteBindings.transient)
            sqlite3_bind_int(stmt, 5, pair.deleteRemoteEnabled ? 1 : 0)
            sqlite3_bind_text(stmt, 6, excludePatternsJSON, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 7, endpointJSON, -1, SQLiteBindings.transient)
            sqlite3_bind_int(stmt, 8, pair.paused ? 1 : 0)
            sqlite3_bind_double(stmt, 9, pair.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 10, pair.updatedAt.timeIntervalSince1970)

            try stepDone(db, stmt: stmt)
        }
    }

    func remove(id: String) throws {
        try execute("DELETE FROM sync_pairs WHERE id = '\(id.replacingOccurrences(of: "'", with: "''"))';")
        try execute("DELETE FROM uploaded_items WHERE pair_id = '\(id.replacingOccurrences(of: "'", with: "''"))';")
    }

    func enqueue(pairID: String, opKind: String, payload: String) throws {
        try queue.sync {
            guard let db else { return }
            let sql = "INSERT INTO op_queue(pair_id, op_kind, payload, created_at) VALUES(?, ?, ?, ?);"
            var stmt: OpaquePointer?
            try prepare(db, sql: sql, into: &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pairID, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 2, opKind, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 3, payload, -1, SQLiteBindings.transient)
            sqlite3_bind_double(stmt, 4, Date().timeIntervalSince1970)
            try stepDone(db, stmt: stmt)
        }
    }

    func queueDepth() -> Int {
        queue.sync {
            guard let db else { return 0 }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM op_queue;", -1, &stmt, nil) == SQLITE_OK else { return 0 }
            defer { sqlite3_finalize(stmt) }
            guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
            return Int(sqlite3_column_int(stmt, 0))
        }
    }

    func uploadedSnapshot(pairID: String, relativePath: String) -> UploadedItemSnapshot? {
        queue.sync {
            guard let db else { return nil }
            let sql = """
            SELECT relative_path, size, modification_time
            FROM uploaded_items
            WHERE pair_id = ? AND relative_path = ?;
            """
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pairID, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 2, relativePath, -1, SQLiteBindings.transient)
            guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
            let path = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? relativePath
            let size = UInt64(max(0, sqlite3_column_int64(stmt, 1)))
            let modificationTime = sqlite3_column_double(stmt, 2)
            return UploadedItemSnapshot(relativePath: path, size: size, modificationTime: modificationTime)
        }
    }

    func markUploaded(pairID: String, relativePath: String, size: UInt64, modificationTime: TimeInterval) throws {
        try queue.sync {
            guard let db else { return }
            let sql = """
            INSERT INTO uploaded_items(pair_id, relative_path, size, modification_time, updated_at)
            VALUES(?, ?, ?, ?, ?)
            ON CONFLICT(pair_id, relative_path) DO UPDATE SET
              size=excluded.size,
              modification_time=excluded.modification_time,
              updated_at=excluded.updated_at;
            """
            var stmt: OpaquePointer?
            try prepare(db, sql: sql, into: &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pairID, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 2, relativePath, -1, SQLiteBindings.transient)
            sqlite3_bind_int64(stmt, 3, sqlite3_int64(size))
            sqlite3_bind_double(stmt, 4, modificationTime)
            sqlite3_bind_double(stmt, 5, Date().timeIntervalSince1970)
            try stepDone(db, stmt: stmt)
        }
    }

    func pruneUploadedSnapshots(pairID: String, keeping relativePaths: Set<String>) throws {
        try queue.sync {
            guard let db else { return }
            let sql = "SELECT relative_path FROM uploaded_items WHERE pair_id = ?;"
            var stmt: OpaquePointer?
            try prepare(db, sql: sql, into: &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pairID, -1, SQLiteBindings.transient)

            var stalePaths: [String] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                let path = sqlite3_column_text(stmt, 0).map { String(cString: $0) } ?? ""
                if !relativePaths.contains(path) {
                    stalePaths.append(path)
                }
            }

            let deleteSQL = "DELETE FROM uploaded_items WHERE pair_id = ? AND relative_path = ?;"
            for stalePath in stalePaths {
                var deleteStmt: OpaquePointer?
                try prepare(db, sql: deleteSQL, into: &deleteStmt)
                sqlite3_bind_text(deleteStmt, 1, pairID, -1, SQLiteBindings.transient)
                sqlite3_bind_text(deleteStmt, 2, stalePath, -1, SQLiteBindings.transient)
                try stepDone(db, stmt: deleteStmt)
                sqlite3_finalize(deleteStmt)
            }
        }
    }

    func clearUploadedSnapshots(pairID: String) throws {
        try queue.sync {
            guard let db else { return }
            let sql = "DELETE FROM uploaded_items WHERE pair_id = ?;"
            var stmt: OpaquePointer?
            try prepare(db, sql: sql, into: &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pairID, -1, SQLiteBindings.transient)
            try stepDone(db, stmt: stmt)
        }
    }

    func removeUploadedSnapshot(pairID: String, relativePath: String) throws {
        try queue.sync {
            guard let db else { return }
            let sql = "DELETE FROM uploaded_items WHERE pair_id = ? AND relative_path = ?;"
            var stmt: OpaquePointer?
            try prepare(db, sql: sql, into: &stmt)
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, pairID, -1, SQLiteBindings.transient)
            sqlite3_bind_text(stmt, 2, relativePath, -1, SQLiteBindings.transient)
            try stepDone(db, stmt: stmt)
        }
    }

    private func configureDatabase() throws {
        guard let db else { return }
        sqlite3_busy_timeout(db, 5_000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=NORMAL;")
        try execute("PRAGMA foreign_keys=ON;")
    }

    private func prepare(_ db: OpaquePointer, sql: String, into stmt: inout OpaquePointer?) throws {
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw NSError(domain: "wiredsyncd", code: 3, userInfo: [NSLocalizedDescriptionKey: sqliteMessage(db)])
        }
    }

    private func stepDone(_ db: OpaquePointer, stmt: OpaquePointer?) throws {
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw NSError(domain: "wiredsyncd", code: 4, userInfo: [NSLocalizedDescriptionKey: sqliteMessage(db)])
        }
    }

    private func sqliteMessage(_ db: OpaquePointer) -> String {
        sqlite3_errmsg(db).map { String(cString: $0) } ?? "sqlite error"
    }
}
