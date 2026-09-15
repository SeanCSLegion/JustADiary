import Foundation
import SQLite3
import os

// `SQLITE_TRANSIENT` is imported as a global, and MainActor default isolation
// treats imported globals as main-actor isolated. Keep an explicitly
// nonisolated copy so the SQLite helpers stay usable off the main actor.
private nonisolated let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

nonisolated final class SQLite {
    private var db: OpaquePointer?

    init(path: String) throws {
        var handle: OpaquePointer?
        let rc = sqlite3_open_v2(path, &handle, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil)
        guard rc == SQLITE_OK, let h = handle else {
            if let h = handle { sqlite3_close(h) }
            throw NSError(domain: "SQLite", code: Int(rc), userInfo: [NSLocalizedDescriptionKey: "open failed: \(rc)"])
        }
        db = h
        sqlite3_busy_timeout(h, 3000)
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA foreign_keys=OFF;")
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    func closeQuietly() {
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    var userVersion: Int {
        get {
            guard let row = query("PRAGMA user_version;").first,
                  let v = row["user_version"] as? Int64 else { return 0 }
            return Int(v)
        }
        set {
            try? execute("PRAGMA user_version=\(newValue);")
        }
    }

    func execute(_ sql: String, _ args: [Any?] = []) throws {
        let stmt = try prepare(sql, args)
        let rc = sqlite3_step(stmt)
        sqlite3_finalize(stmt)
        guard rc == SQLITE_DONE || rc == SQLITE_ROW else {
            throw error(rc, sql)
        }
    }

    func query(_ sql: String, _ args: [Any?] = []) -> [[String: Any]] {
        guard let stmt = try? prepare(sql, args) else {
            Log.db.error("query prepare failed: \(sql, privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }
        var rows: [[String: Any]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            rows.append(columnValues(stmt))
        }
        return rows
    }

    func queryFirst(_ sql: String, _ args: [Any?] = []) -> [String: Any]? {
        guard let stmt = try? prepare(sql, args) else {
            Log.db.error("queryFirst prepare failed: \(sql, privacy: .public)")
            return nil
        }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return columnValues(stmt)
    }

    func lastInsertId() -> Int64 {
        sqlite3_last_insert_rowid(db)
    }

    func inTransaction<T>(_ block: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try block()
            try execute("COMMIT;")
            return result
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func prepare(_ sql: String, _ args: [Any?]) throws -> OpaquePointer {
        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let s = stmt else {
            throw error(rc, sql)
        }
        for (i, arg) in args.enumerated() {
            let idx = Int32(i + 1)
            if let text = arg as? String {
                _ = text.withCString { cstr in
                    sqlite3_bind_text(s, idx, cstr, -1, sqliteTransient)
                }
            } else if let d = arg as? Double {
                sqlite3_bind_double(s, idx, d)
            } else if let intVal = arg as? Int {
                sqlite3_bind_int64(s, idx, Int64(intVal))
            } else if let int64Val = arg as? Int64 {
                sqlite3_bind_int64(s, idx, int64Val)
            } else if let boolVal = arg as? Bool {
                sqlite3_bind_int64(s, idx, boolVal ? 1 : 0)
            } else if let n = arg as? NSNumber {
                sqlite3_bind_double(s, idx, n.doubleValue)
            } else {
                sqlite3_bind_null(s, idx)
            }
        }
        return s
    }

    private func columnValues(_ stmt: OpaquePointer) -> [String: Any] {
        let count = sqlite3_column_count(stmt)
        var row: [String: Any] = [:]
        for i in 0..<count {
            let name = String(cString: sqlite3_column_name(stmt, i))
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_INTEGER:
                row[name] = sqlite3_column_int64(stmt, i)
            case SQLITE_FLOAT:
                row[name] = sqlite3_column_double(stmt, i)
            case SQLITE_TEXT:
                if let text = sqlite3_column_text(stmt, i) {
                    row[name] = String(cString: text)
                }
            case SQLITE_BLOB:
                if let blob = sqlite3_column_blob(stmt, i) {
                    let len = sqlite3_column_bytes(stmt, i)
                    row[name] = Data(bytes: blob, count: Int(len))
                }
            default:
                break
            }
        }
        return row
    }

    private func error(_ rc: Int32, _ sql: String) -> NSError {
        let msg = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
        return NSError(domain: "SQLite", code: Int(rc),
                       userInfo: [NSLocalizedDescriptionKey: "\(msg) in: \(sql)"])
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
