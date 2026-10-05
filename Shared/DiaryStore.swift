import Foundation
import SQLite3

enum DiaryStoreError: LocalizedError {
    case sqlite(code: Int32, message: String)
    case unsupportedSchema(Int)
    case invalidEntry(String)
    case invalidBackup(String)
    case entryNotFound(UUID)
    case duplicateEntry(UUID)
    case deletedEntry(UUID)
    case staleEntry(UUID)
    case corruptRecord(String)

    var errorDescription: String? {
        switch self {
        case let .sqlite(code, message): return "The diary could not be saved or read (SQLite \(code)): \(message)"
        case let .unsupportedSchema(version): return "This diary uses database version \(version). Update Pupudiary to open it."
        case let .invalidEntry(message): return message
        case let .invalidBackup(message): return "This backup could not be restored: \(message)"
        case .entryNotFound: return "This entry is no longer available. Refresh and try again."
        case .duplicateEntry: return "An entry with this identifier already exists."
        case .deletedEntry: return "Restore this deleted entry before editing it."
        case .staleEntry: return "This entry changed while you were editing. Reopen it to avoid losing the newer changes."
        case let .corruptRecord(message): return "A diary record could not be read: \(message)"
        }
    }
}

struct QuickLogResult: Sendable {
    let entry: LogEntry
    let wasInserted: Bool
}

struct RestoreResult: Sendable {
    let insertedCount: Int
    let skippedCount: Int
}

struct BackupValidation: Sendable {
    let entryCount: Int
    let newCount: Int
    let existingCount: Int
    let errors: [String]
    var isValid: Bool { errors.isEmpty }
}

struct DiaryBackup: Codable, Sendable {
    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let entries: [LogEntry]
}

/// One SQLite connection per store. All operations are serialized within this
/// instance; BEGIN IMMEDIATE + WAL + a busy timeout serialize writers across
/// the main app, App Intent, and widget processes. The caller supplies the
/// shared App Group URL. This store never falls back to a different container.
final class DiaryStore: @unchecked Sendable {
    static let maximumBackupBytes = 10 * 1_024 * 1_024
    static let maximumBackupEntries = 25_000
    static let quickLogDebounceInterval: TimeInterval = 2

    private var database: OpaquePointer?
    private let lock = NSLock()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(url: URL) throws {
        guard url.isFileURL else { throw DiaryStoreError.invalidEntry("The diary must use a local file URL.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var opened: OpaquePointer?
        let code = sqlite3_open_v2(url.path, &opened, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard code == SQLITE_OK, let opened else {
            let message = opened.map { String(cString: sqlite3_errmsg($0)) } ?? "Could not open the diary file."
            if let opened { sqlite3_close_v2(opened) }
            throw DiaryStoreError.sqlite(code: code, message: message)
        }
        database = opened
        do {
            sqlite3_extended_result_codes(opened, 1)
            try check(sqlite3_busy_timeout(opened, 5_000))
            try execute("PRAGMA journal_mode = WAL")
            try execute("PRAGMA synchronous = FULL")
            try execute("PRAGMA foreign_keys = ON")
            try transaction {
                let version = try scalarInt("PRAGMA user_version")
                guard version <= 1 else { throw DiaryStoreError.unsupportedSchema(version) }
                if version == 0 {
                    try execute("""
                    CREATE TABLE IF NOT EXISTS entries (
                        id TEXT PRIMARY KEY NOT NULL,
                        occurred_at REAL NOT NULL,
                        created_at REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        deleted_at REAL,
                        payload BLOB NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS entries_occurred ON entries(occurred_at DESC);
                    CREATE TABLE IF NOT EXISTS quick_log_ledger (
                        request_id TEXT PRIMARY KEY NOT NULL,
                        entry_id TEXT NOT NULL REFERENCES entries(id),
                        requested_at REAL NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS ledger_requested ON quick_log_ledger(requested_at DESC);
                    PRAGMA user_version = 1;
                    """)
                }
            }
        } catch {
            sqlite3_close_v2(opened)
            database = nil
            throw error
        }
    }

    deinit {
        if let database { sqlite3_close_v2(database) }
    }

    /// Reusing a requestID is always idempotent. Distinct quick requests within
    /// two seconds of another quick request share an active entry. Manual
    /// entries are never coalesced. Undo does not resurrect on a retried request.
    func quickLog(at date: Date = Date(), requestID: UUID = UUID()) throws -> QuickLogResult {
        try synchronized {
            try transaction {
                let now = DiaryDate.canonical(date)
                let candidate = LogEntry(occurredAt: now, createdAt: now, updatedAt: now)
                try candidate.validate()
                if let repeated = try queryEntries("""
                    SELECT e.payload FROM quick_log_ledger l JOIN entries e ON e.id = l.entry_id
                    WHERE l.request_id = ?
                    """, bind: { try self.bind(requestID.uuidString, to: 1, in: $0) }).first {
                    return QuickLogResult(entry: repeated, wasInserted: false)
                }
                let recent = try queryEntries("""
                    SELECT e.payload FROM quick_log_ledger l JOIN entries e ON e.id = l.entry_id
                    WHERE e.deleted_at IS NULL AND l.requested_at >= ? AND l.requested_at <= ?
                    ORDER BY l.requested_at DESC, l.request_id ASC LIMIT 1
                    """, bind: {
                        try self.check(sqlite3_bind_double($0, 1, now.timeIntervalSince1970 - Self.quickLogDebounceInterval))
                        try self.check(sqlite3_bind_double($0, 2, now.timeIntervalSince1970 + Self.quickLogDebounceInterval))
                    }).first
                let entry = recent ?? candidate
                if recent == nil { try write(entry, inserting: true) }
                let statement = try prepare("INSERT INTO quick_log_ledger (request_id, entry_id, requested_at) VALUES (?, ?, ?)")
                defer { sqlite3_finalize(statement) }
                try bind(requestID.uuidString, to: 1, in: statement)
                try bind(entry.id.uuidString, to: 2, in: statement)
                try check(sqlite3_bind_double(statement, 3, now.timeIntervalSince1970))
                try stepDone(statement)
                return QuickLogResult(entry: entry, wasInserted: recent == nil)
            }
        }
    }

    @discardableResult
    func insert(_ entry: LogEntry) throws -> LogEntry {
        try synchronized {
            let entry = entry.canonicalized()
            try entry.validate()
            return try transaction {
                guard try find(entry.id) == nil else { throw DiaryStoreError.duplicateEntry(entry.id) }
                try write(entry, inserting: true)
                return entry
            }
        }
    }

    /// Newest occurredAt first, including backdated manual logs. Deleted rows
    /// stay in the database until restored; there is no destructive purge API.
    func entries(includeDeleted: Bool = false) throws -> [LogEntry] {
        try synchronized {
            try queryEntries("SELECT payload FROM entries \(includeDeleted ? "" : "WHERE deleted_at IS NULL") ORDER BY occurred_at DESC, id ASC")
        }
    }

    func entry(id: UUID) throws -> LogEntry? {
        try synchronized { try find(id) }
    }

    /// Optimistic concurrency prevents a stale editor from overwriting a newer
    /// edit. Identity, createdAt and deletedAt cannot be changed by editing.
    func update(_ entry: LogEntry, at date: Date = Date()) throws {
        try synchronized {
            try transaction {
                guard let original = try find(entry.id) else { throw DiaryStoreError.entryNotFound(entry.id) }
                guard !original.isDeleted else { throw DiaryStoreError.deletedEntry(entry.id) }
                guard DiaryDate.canonical(entry.updatedAt) == original.updatedAt else { throw DiaryStoreError.staleEntry(entry.id) }
                var updated = entry.canonicalized()
                updated.createdAt = original.createdAt
                updated.deletedAt = original.deletedAt
                updated.updatedAt = nextTimestamp(date, after: original.updatedAt)
                try updated.validate()
                try write(updated, inserting: false)
            }
        }
    }

    func softDelete(id: UUID, at date: Date = Date()) throws {
        try synchronized {
            try transaction {
                guard var entry = try find(id) else { throw DiaryStoreError.entryNotFound(id) }
                guard !entry.isDeleted else { return }
                entry.updatedAt = nextTimestamp(date, after: entry.updatedAt)
                entry.deletedAt = entry.updatedAt
                try entry.validate()
                try write(entry, inserting: false)
            }
        }
    }

    func restoreDeleted(id: UUID, at date: Date = Date()) throws {
        try synchronized {
            try transaction {
                guard var entry = try find(id) else { throw DiaryStoreError.entryNotFound(id) }
                guard entry.isDeleted else { return }
                entry.updatedAt = nextTimestamp(date, after: entry.updatedAt)
                entry.deletedAt = nil
                try entry.validate()
                try write(entry, inserting: false)
            }
        }
    }

    /// JSON is the lossless restore format. It includes deleted rows and unknown
    /// details (omitted optional keys decode as nil); [] symptoms stays explicit.
    func exportJSON() throws -> Data {
        try synchronized {
            let records = try queryEntries("SELECT payload FROM entries ORDER BY occurred_at DESC, id ASC")
            guard records.count <= Self.maximumBackupEntries else {
                throw DiaryStoreError.invalidBackup("The diary exceeds the supported 25,000-entry backup limit.")
            }
            let backup = DiaryBackup(format: "pupudiary", schemaVersion: 1, exportedAt: DiaryDate.canonical(Date()), entries: records)
            let data = try DiaryDate.encoder().encode(backup)
            guard data.count <= Self.maximumBackupBytes else {
                throw DiaryStoreError.invalidBackup("The diary exceeds the supported 10 MiB backup limit.")
            }
            return data
        }
    }

    /// Preview only. Restore validates again, so changes after preview are safe.
    /// Invalid data produces errors, never partial mutations or dropped rows.
    func validateBackup(_ data: Data) -> BackupValidation {
        do {
            let backup = try decodeBackup(data)
            return try synchronized {
                var existing = 0
                for entry in backup.entries {
                    if try find(entry.id) != nil { existing += 1 }
                }
                return BackupValidation(entryCount: backup.entries.count, newCount: backup.entries.count - existing, existingCount: existing, errors: [])
            }
        } catch {
            return BackupValidation(entryCount: 0, newCount: 0, existingCount: 0, errors: [error.localizedDescription])
        }
    }

    /// Restore is additive: an existing UUID is NEVER overwritten, even if its
    /// backup copy is newer or conflicts. Existing deleted rows remain deleted.
    /// Every record must validate before the single write transaction starts.
    func mergeJSON(_ data: Data) throws -> RestoreResult {
        let backup = try decodeBackup(data)
        return try synchronized {
            try transaction {
                var inserted = 0
                var skipped = 0
                for entry in backup.entries {
                    if try find(entry.id) != nil { skipped += 1 }
                    else {
                        try write(entry, inserting: true)
                        inserted += 1
                    }
                }
                return RestoreResult(insertedCount: inserted, skippedCount: skipped)
            }
        }
    }

    /// Human/spreadsheet export; use JSON for lossless recovery. RFC 4180:
    /// UTF-8, comma delimiter, quoted cells, doubled quotes, CRLF row endings.
    /// Formula-like text gets a leading apostrophe, including after whitespace.
    /// CSV includes deleted rows and uses UTC instants, never local wall times.
    func exportCSV() throws -> Data {
        let records = try entries(includeDeleted: true)
        let headers = ["id", "occurred_at_utc", "created_at_utc", "updated_at_utc", "bristol", "color", "amount", "effort", "symptoms", "duration_minutes", "note", "deleted_at_utc"]
        var rows = [headers.map(Self.csvCell).joined(separator: ",")]
        for entry in records {
            let symptomText = try entry.symptoms.map { String(decoding: try JSONEncoder().encode($0), as: UTF8.self) } ?? ""
            let cells = [
                entry.id.uuidString, DiaryDate.string(entry.occurredAt), DiaryDate.string(entry.createdAt), DiaryDate.string(entry.updatedAt),
                entry.bristol.map(String.init) ?? "", entry.color ?? "", entry.amount ?? "", entry.effort ?? "", symptomText,
                entry.durationMinutes.map(String.init) ?? "", entry.note ?? "", entry.deletedAt.map(DiaryDate.string) ?? ""
            ]
            rows.append(cells.map(Self.csvCell).joined(separator: ","))
        }
        return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
    }

    private static func csvCell(_ text: String) -> String {
        let invisible = CharacterSet.whitespacesAndNewlines.union(.controlCharacters).union(CharacterSet(charactersIn: "\u{FEFF}"))
        let leadingTrimmed = text.unicodeScalars.drop(while: { invisible.contains($0) })
        let dangerous = leadingTrimmed.first.map { "=+-@".unicodeScalars.contains($0) } ?? false
        let startsControl = text.first.map { $0 == "\t" || $0 == "\r" || $0 == "\n" } ?? false
        let safe = dangerous || startsControl ? "'" + text : text
        return "\"" + safe.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func decodeBackup(_ data: Data) throws -> DiaryBackup {
        guard !data.isEmpty, data.count <= Self.maximumBackupBytes else {
            throw DiaryStoreError.invalidBackup("Choose a nonempty JSON file no larger than 10 MiB.")
        }
        let backup: DiaryBackup
        do { backup = try DiaryDate.decoder().decode(DiaryBackup.self, from: data) }
        catch { throw DiaryStoreError.invalidBackup("The file is not a valid Pupudiary JSON backup. \(error.localizedDescription)") }
        guard backup.format == "pupudiary", backup.schemaVersion == 1 else {
            throw DiaryStoreError.invalidBackup("This backup format or version is not supported.")
        }
        guard backup.entries.count <= Self.maximumBackupEntries else {
            throw DiaryStoreError.invalidBackup("A backup may contain at most 25,000 entries.")
        }
        let exported = backup.exportedAt.timeIntervalSince1970
        guard exported.isFinite, exported >= 0, exported <= 253_402_300_799.999 else {
            throw DiaryStoreError.invalidBackup("The export timestamp is invalid.")
        }
        var identifiers = Set<UUID>()
        for entry in backup.entries {
            guard identifiers.insert(entry.id).inserted else {
                throw DiaryStoreError.invalidBackup("Entry \(entry.id.uuidString) occurs more than once.")
            }
            do { try entry.validate() }
            catch { throw DiaryStoreError.invalidBackup("Entry \(entry.id.uuidString): \(error.localizedDescription)") }
        }
        return backup
    }

    private func nextTimestamp(_ candidate: Date, after previous: Date) -> Date {
        DiaryDate.canonical(max(candidate, previous.addingTimeInterval(0.001)))
    }

    private func synchronized<T>(_ action: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try action()
    }

    private func transaction<T>(_ action: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE TRANSACTION")
        do {
            let result = try action()
            try execute("COMMIT")
            return result
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func check(_ code: Int32) throws {
        guard code == SQLITE_OK else { throw databaseError(code) }
    }

    private func databaseError(_ code: Int32) -> DiaryStoreError {
        DiaryStoreError.sqlite(code: code, message: database.map { String(cString: sqlite3_errmsg($0)) } ?? "The database is closed.")
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(database, sql, nil, nil, nil))
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        try check(sqlite3_prepare_v2(database, sql, -1, &statement, nil))
        guard let statement else { throw DiaryStoreError.corruptRecord("Could not prepare a database operation.") }
        return statement
    }

    private func bind(_ value: String, to index: Int32, in statement: OpaquePointer) throws {
        try check(sqlite3_bind_text(statement, index, value, -1, transient))
    }

    private func stepDone(_ statement: OpaquePointer) throws {
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE else { throw databaseError(code) }
    }

    private func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW else { throw databaseError(code) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func find(_ id: UUID) throws -> LogEntry? {
        try queryEntries("SELECT payload FROM entries WHERE id = ?", bind: { try self.bind(id.uuidString, to: 1, in: $0) }).first
    }

    private func queryEntries(_ sql: String, bind: ((OpaquePointer) throws -> Void)? = nil) throws -> [LogEntry] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind?(statement)
        var result: [LogEntry] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw databaseError(code) }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { throw DiaryStoreError.corruptRecord("Empty record.") }
            let data = Data(bytes: bytes, count: count)
            do {
                let entry = try DiaryDate.decoder().decode(LogEntry.self, from: data)
                try entry.validate()
                result.append(entry)
            } catch { throw DiaryStoreError.corruptRecord(error.localizedDescription) }
        }
        return result
    }

    private func write(_ entry: LogEntry, inserting: Bool) throws {
        let data = try DiaryDate.encoder().encode(entry)
        let sql = inserting
            ? "INSERT INTO entries (occurred_at, created_at, updated_at, deleted_at, payload, id) VALUES (?, ?, ?, ?, ?, ?)"
            : "UPDATE entries SET occurred_at = ?, created_at = ?, updated_at = ?, deleted_at = ?, payload = ? WHERE id = ?"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try check(sqlite3_bind_double(statement, 1, entry.occurredAt.timeIntervalSince1970))
        try check(sqlite3_bind_double(statement, 2, entry.createdAt.timeIntervalSince1970))
        try check(sqlite3_bind_double(statement, 3, entry.updatedAt.timeIntervalSince1970))
        if let deleted = entry.deletedAt { try check(sqlite3_bind_double(statement, 4, deleted.timeIntervalSince1970)) }
        else { try check(sqlite3_bind_null(statement, 4)) }
        try data.withUnsafeBytes { bytes in
            try check(sqlite3_bind_blob(statement, 5, bytes.baseAddress, Int32(bytes.count), transient))
        }
        try bind(entry.id.uuidString, to: 6, in: statement)
        try stepDone(statement)
    }
}
