import Foundation
import SQLite3

/// Minimal read-only SQLite access — enough to query the Codex and OpenCode
/// databases without adding a dependency. Opens with `mode=ro` so the live
/// files are never disturbed.
final class SQLiteDB {
    private var handle: OpaquePointer?

    enum Value {
        case integer(Int64)
        case real(Double)
        case text(String)
        case null
    }

    init?(readOnly url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let uri = "file:\(url.path)?mode=ro"
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(uri, &handle, flags, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            return nil
        }
        sqlite3_busy_timeout(handle, 1500)
    }

    deinit {
        sqlite3_close(handle)
    }

    /// Run a query and map every row.
    func query<T>(_ sql: String, _ map: ([Value]) -> T?) -> [T] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        var rows: [T] = []
        let count = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var values: [Value] = []
            values.reserveCapacity(Int(count))
            for i in 0..<count {
                switch sqlite3_column_type(stmt, i) {
                case SQLITE_INTEGER: values.append(.integer(sqlite3_column_int64(stmt, i)))
                case SQLITE_FLOAT: values.append(.real(sqlite3_column_double(stmt, i)))
                case SQLITE_TEXT:
                    if let c = sqlite3_column_text(stmt, i) {
                        values.append(.text(String(cString: c)))
                    } else {
                        values.append(.null)
                    }
                default: values.append(.null)
                }
            }
            if let row = map(values) { rows.append(row) }
        }
        return rows
    }
}

extension SQLiteDB.Value {
    var int: Int64 {
        switch self {
        case .integer(let v): v
        case .real(let v): Int64(v)
        case .text(let s): Int64(s) ?? 0
        case .null: 0
        }
    }

    var double: Double {
        switch self {
        case .integer(let v): Double(v)
        case .real(let v): v
        case .text(let s): Double(s) ?? 0
        case .null: 0
        }
    }

    var string: String? {
        if case .text(let s) = self { return s }
        return nil
    }
}
