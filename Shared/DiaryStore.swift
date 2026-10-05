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
    case bowelMovementAlreadyRecorded

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
        case .bowelMovementAlreadyRecorded: return "This day already has a bowel movement. It cannot also be confirmed as a no-bowel-movement day."
        }
    }
}

struct QuickLogResult: Sendable {
    let entry: LogEntry
    let wasInserted: Bool
}

struct DiarySummary: Sendable {
    let count: Int
    /// Latest active entry across all days, not only the requested local day.
    let last: LogEntry?
    let dayStatus: DiaryDayState
    let noBowelMovementConfirmation: DayStatus?
    /// Consecutive explicitly confirmed calendar dates in the requested zone,
    /// ending on the selected day. Includes partial today; NOT elapsed days,
    /// a constipation diagnosis, or proof of a continuous no-BM duration.
    let confirmedNoBowelMovementDaysEndingOnDay: Int

    init(count: Int, last: LogEntry?, dayStatus: DiaryDayState? = nil,
         noBowelMovementConfirmation: DayStatus? = nil,
         confirmedNoBowelMovementDaysEndingOnDay: Int = 0) {
        self.count = count
        self.last = last
        self.dayStatus = dayStatus ?? (count > 0 ? .recordedBowelMovement : .unknown)
        self.noBowelMovementConfirmation = noBowelMovementConfirmation
        self.confirmedNoBowelMovementDaysEndingOnDay = confirmedNoBowelMovementDaysEndingOnDay
    }
}

struct RestoreResult: Sendable {
    let insertedCount: Int
    let skippedCount: Int
    var insertedDayStatusCount: Int = 0
    var skippedDayStatusCount: Int = 0
}

struct BackupValidation: Sendable {
    let entryCount: Int
    let newCount: Int
    let existingCount: Int
    let errors: [String]
    var dayStatusCount: Int = 0
    var newDayStatusCount: Int = 0
    var existingDayStatusCount: Int = 0
    var isValid: Bool { errors.isEmpty }
}

struct DiaryBackup: Codable, Sendable {
    let format: String
    let schemaVersion: Int
    let exportedAt: Date
    let entries: [LogEntry]
    let dayStatuses: [DayStatus]

    init(format: String, schemaVersion: Int, exportedAt: Date, entries: [LogEntry], dayStatuses: [DayStatus] = []) {
        self.format = format
        self.schemaVersion = schemaVersion
        self.exportedAt = exportedAt
        self.entries = entries
        self.dayStatuses = dayStatuses
    }

    private enum CodingKeys: String, CodingKey { case format, schemaVersion, exportedAt, entries, dayStatuses }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        format = try values.decode(String.self, forKey: .format)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        exportedAt = try values.decode(Date.self, forKey: .exportedAt)
        entries = try values.decode([LogEntry].self, forKey: .entries)
        if schemaVersion == 1 {
            dayStatuses = try values.decodeIfPresent([DayStatus].self, forKey: .dayStatuses) ?? []
        } else {
            dayStatuses = try values.decode([DayStatus].self, forKey: .dayStatuses)
        }
    }
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
                guard version <= 2 else { throw DiaryStoreError.unsupportedSchema(version) }
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
                if version <= 1 {
                    try execute("""
                    CREATE TABLE IF NOT EXISTS day_statuses (
                        id TEXT PRIMARY KEY NOT NULL,
                        local_date TEXT NOT NULL,
                        timezone_identifier TEXT NOT NULL,
                        day_start REAL NOT NULL,
                        day_end REAL NOT NULL,
                        updated_at REAL NOT NULL,
                        cancelled_at REAL,
                        payload BLOB NOT NULL,
                        UNIQUE(local_date, timezone_identifier)
                    );
                    CREATE INDEX IF NOT EXISTS day_statuses_interval ON day_statuses(day_start, day_end) WHERE cancelled_at IS NULL;
                    PRAGMA user_version = 2;
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

    /// An explicit no-BM observation, separate from entries. Repeated marking is
    /// idempotent; a cancelled day is reactivated only by this user action, with
    /// the same UUID and a newer timestamp. A BM in that zone's day rejects it.
    @discardableResult
    func markNoBowelMovement(on date: Date = Date(), calendar: Calendar = .current, at timestamp: Date = Date()) throws -> DayStatus {
        let localDate = try DayStatus.civilDate(on: date, calendar: calendar)
        let candidate = DayStatus(localDate: localDate, timeZoneIdentifier: calendar.timeZone.identifier,
                                  createdAt: timestamp, updatedAt: timestamp)
        try candidate.validate()
        return try synchronized {
            try transaction {
                guard try !hasBowelMovement(in: candidate.dayInterval()) else {
                    throw DiaryStoreError.bowelMovementAlreadyRecorded
                }
                if var existing = try findDayStatus(localDate: localDate, timeZoneIdentifier: calendar.timeZone.identifier) {
                    guard existing.isCancelled else { return existing }
                    existing.cancelledAt = nil
                    existing.updatedAt = nextTimestamp(timestamp, after: existing.updatedAt)
                    try existing.validate()
                    try writeDayStatus(existing, inserting: false)
                    return existing
                }
                try writeDayStatus(candidate, inserting: true)
                return candidate
            }
        }
    }

    /// Clearing retains a tombstone. Neither old backups nor deleting the BM
    /// which superseded a confirmation can reactivate it. Mark again to recover.
    @discardableResult
    func clearNoBowelMovement(on date: Date = Date(), calendar: Calendar = .current, at timestamp: Date = Date()) throws -> DayStatus? {
        let localDate = try DayStatus.civilDate(on: date, calendar: calendar)
        return try synchronized {
            try transaction {
                guard let existing = try findDayStatus(localDate: localDate, timeZoneIdentifier: calendar.timeZone.identifier) else { return nil }
                return try cancelDayStatus(existing, at: timestamp)
            }
        }
    }

    func dayStatuses(includeCancelled: Bool = false) throws -> [DayStatus] {
        try synchronized {
            try queryDayStatuses("SELECT payload FROM day_statuses \(includeCancelled ? "" : "WHERE cancelled_at IS NULL") ORDER BY local_date DESC, timezone_identifier ASC, id ASC")
        }
    }

    /// Widget-sized read: SQLite counts active entries in the local day's
    /// half-open [start, end) interval and decodes only the latest active row.
    /// Calendar supplies DST-aware boundaries (a day can be 23 or 25 hours).
    /// A read transaction keeps count and last on one cross-process snapshot.
    func summary(on date: Date = Date(), calendar: Calendar = .current) throws -> DiarySummary {
        try synchronized {
            guard date.timeIntervalSince1970.isFinite,
                  let day = calendar.dateInterval(of: .day, for: date) else {
                throw DiaryStoreError.invalidEntry("The selected local day could not be determined.")
            }
            try execute("BEGIN DEFERRED TRANSACTION")
            do {
                let count = try scalarInt("""
                    SELECT COUNT(*) FROM entries
                    WHERE deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?
                    """, bind: { statement in
                        try self.check(sqlite3_bind_double(statement, 1, day.start.timeIntervalSince1970))
                        try self.check(sqlite3_bind_double(statement, 2, day.end.timeIntervalSince1970))
                    })
                let last = try queryEntries("""
                    SELECT payload FROM entries WHERE deleted_at IS NULL
                    ORDER BY occurred_at DESC, id ASC LIMIT 1
                    """).first
                let localDate = try DayStatus.civilDate(on: date, calendar: calendar)
                let saved = try findDayStatus(localDate: localDate, timeZoneIdentifier: calendar.timeZone.identifier)
                let confirmation = count == 0 && saved?.isCancelled == false ? saved : nil
                var confirmedDates = 0
                if confirmation != nil {
                    var cursor = date
                    // Only explicitly confirmed dates count. Unknown dates and
                    // confirmations made in another timezone break the sequence.
                    var gregorian = Calendar(identifier: .gregorian)
                    gregorian.timeZone = calendar.timeZone
                    while let key = try? DayStatus.civilDate(on: cursor, calendar: gregorian),
                          let status = try findDayStatus(localDate: key, timeZoneIdentifier: gregorian.timeZone.identifier),
                          !status.isCancelled {
                        confirmedDates += 1
                        guard let previous = gregorian.date(byAdding: .day, value: -1, to: cursor) else { break }
                        cursor = previous
                    }
                }
                try execute("COMMIT")
                return DiarySummary(count: count, last: last,
                                    dayStatus: count > 0 ? .recordedBowelMovement : (confirmation == nil ? .unknown : .confirmedNoBowelMovement),
                                    noBowelMovementConfirmation: confirmation,
                                    confirmedNoBowelMovementDaysEndingOnDay: confirmedDates)
            } catch {
                try? execute("ROLLBACK")
                throw error
            }
        }
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

    /// JSON v2 is the lossless restore format. A single snapshot includes entries,
    /// deleted rows, explicit day observations, and cancelled-day tombstones.
    /// Backups from v1 (which contain only entries) remain supported on import.
    func exportJSON() throws -> Data {
        try synchronized {
            try readTransaction {
                let records = try queryEntries("SELECT payload FROM entries ORDER BY occurred_at DESC, id ASC")
                let statuses = try queryDayStatuses("SELECT payload FROM day_statuses ORDER BY local_date DESC, timezone_identifier ASC, id ASC")
                guard records.count + statuses.count <= Self.maximumBackupEntries else {
                    throw DiaryStoreError.invalidBackup("The diary exceeds the supported 25,000-record backup limit.")
                }
                let backup = DiaryBackup(format: "pupudiary", schemaVersion: 2, exportedAt: DiaryDate.canonical(Date()), entries: records, dayStatuses: statuses)
                let data = try DiaryDate.encoder().encode(backup)
                guard data.count <= Self.maximumBackupBytes else {
                    throw DiaryStoreError.invalidBackup("The diary exceeds the supported 10 MiB backup limit.")
                }
                return data
            }
        }
    }

    /// Preview only. Counts for bowel movements and day statuses stay separate.
    /// Restore validates again, so changes after preview are safe.
    func validateBackup(_ data: Data) -> BackupValidation {
        do {
            let backup = try decodeBackup(data)
            return try synchronized {
                try readTransaction {
                    var existing = 0
                    var existingStatuses = 0
                    for entry in backup.entries {
                        if try find(entry.id) != nil { existing += 1 }
                    }
                    for status in backup.dayStatuses {
                        if try hasDayStatusConflict(status) { existingStatuses += 1 }
                    }
                    return BackupValidation(entryCount: backup.entries.count, newCount: backup.entries.count - existing,
                                            existingCount: existing, errors: [], dayStatusCount: backup.dayStatuses.count,
                                            newDayStatusCount: backup.dayStatuses.count - existingStatuses,
                                            existingDayStatusCount: existingStatuses)
                }
            }
        } catch {
            return BackupValidation(entryCount: 0, newCount: 0, existingCount: 0, errors: [error.localizedDescription])
        }
    }

    /// Additive restore never overwrites an existing entry UUID or a day-status
    /// UUID/date+zone key, including tombstones. Incoming active BM entries do
    /// supersede contradictory local no-BM observations in this same transaction.
    /// A new imported status contradicted by a local BM is retained as cancelled.
    /// All records and intrinsic backup contradictions validate before mutation.
    func mergeJSON(_ data: Data) throws -> RestoreResult {
        let backup = try decodeBackup(data)
        return try synchronized {
            try transaction {
                var inserted = 0
                var skipped = 0
                var insertedStatuses = 0
                var skippedStatuses = 0
                for entry in backup.entries {
                    if try find(entry.id) != nil { skipped += 1 }
                    else {
                        try write(entry, inserting: true)
                        inserted += 1
                    }
                }
                for original in backup.dayStatuses {
                    if try hasDayStatusConflict(original) { skippedStatuses += 1 }
                    else {
                        var status = original
                        if !status.isCancelled, try hasBowelMovement(in: status.dayInterval()) {
                            status.updatedAt = nextTimestamp(Date(), after: status.updatedAt)
                            status.cancelledAt = status.updatedAt
                            try status.validate()
                        }
                        try writeDayStatus(status, inserting: true)
                        insertedStatuses += 1
                    }
                }
                return RestoreResult(insertedCount: inserted, skippedCount: skipped,
                                     insertedDayStatusCount: insertedStatuses, skippedDayStatusCount: skippedStatuses)
            }
        }
    }

    /// Human/spreadsheet export; JSON is the lossless restore format. RFC 4180:
    /// UTF-8, quoted cells, doubled quotes, CRLF, and formula-text neutralization.
    /// Original entry columns are preserved; appended columns distinguish status
    /// rows, civil dates, their saved zone, and cancellation from actual BMs.
    func exportCSV() throws -> Data {
        try synchronized {
            try readTransaction {
                let records = try queryEntries("SELECT payload FROM entries ORDER BY occurred_at DESC, id ASC")
                let statuses = try queryDayStatuses("SELECT payload FROM day_statuses ORDER BY local_date DESC, timezone_identifier ASC, id ASC")
                let headers = ["id", "occurred_at_utc", "created_at_utc", "updated_at_utc", "bristol", "color", "amount", "effort", "symptoms", "duration_minutes", "note", "deleted_at_utc", "record_type", "day_status", "local_date", "time_zone", "cancelled_at_utc"]
                var rows = [headers.map(Self.csvCell).joined(separator: ",")]
                for entry in records {
                    let symptomText: String
                    if let symptoms = entry.symptoms {
                        let encodedSymptoms = try JSONEncoder().encode(symptoms)
                        symptomText = String(decoding: encodedSymptoms, as: UTF8.self)
                    } else { symptomText = "" }
                    var cells: [String] = []
                    cells.reserveCapacity(headers.count)
                    cells.append(entry.id.uuidString)
                    cells.append(DiaryDate.string(entry.occurredAt))
                    cells.append(DiaryDate.string(entry.createdAt))
                    cells.append(DiaryDate.string(entry.updatedAt))
                    cells.append(entry.bristol.map { String($0) } ?? "")
                    cells.append(entry.color ?? "")
                    cells.append(entry.amount ?? "")
                    cells.append(entry.effort ?? "")
                    cells.append(symptomText)
                    cells.append(entry.durationMinutes.map { String($0) } ?? "")
                    cells.append(entry.note ?? "")
                    cells.append(entry.deletedAt.map { DiaryDate.string($0) } ?? "")
                    cells.append(contentsOf: ["bowel_movement", "", "", "", ""])
                    rows.append(cells.map(Self.csvCell).joined(separator: ","))
                }
                for status in statuses {
                    let cells = [status.id.uuidString, "", DiaryDate.string(status.createdAt), DiaryDate.string(status.updatedAt),
                                 "", "", "", "", "", "", "", "", "day_status", "no_bowel_movement", status.localDate,
                                 status.timeZoneIdentifier, status.cancelledAt.map { DiaryDate.string($0) } ?? ""]
                    rows.append(cells.map(Self.csvCell).joined(separator: ","))
                }
                return Data((rows.joined(separator: "\r\n") + "\r\n").utf8)
            }
        }
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
        guard backup.format == "pupudiary", (1...2).contains(backup.schemaVersion),
              backup.schemaVersion != 1 || backup.dayStatuses.isEmpty else {
            throw DiaryStoreError.invalidBackup("This backup format or version is not supported.")
        }
        guard backup.entries.count + backup.dayStatuses.count <= Self.maximumBackupEntries else {
            throw DiaryStoreError.invalidBackup("A backup may contain at most 25,000 records.")
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
        let activeDates = backup.entries.filter { !$0.isDeleted }.map(\.occurredAt).sorted()
        var dayKeys = Set<String>()
        for status in backup.dayStatuses {
            guard identifiers.insert(status.id).inserted, dayKeys.insert(status.dayKey).inserted else {
                throw DiaryStoreError.invalidBackup("A day-status identifier or civil-date/timezone occurs more than once.")
            }
            do {
                try status.validate()
                if !status.isCancelled, Self.containsDate(in: try status.dayInterval(), sortedDates: activeDates) {
                    throw DiaryStoreError.invalidEntry("A confirmed no-BM day conflicts with a bowel movement in this backup.")
                }
            } catch { throw DiaryStoreError.invalidBackup("Day status \(status.id.uuidString): \(error.localizedDescription)") }
        }
        return backup
    }

    private static func containsDate(in interval: DateInterval, sortedDates: [Date]) -> Bool {
        var low = 0
        var high = sortedDates.count
        while low < high {
            let middle = low + (high - low) / 2
            if sortedDates[middle] < interval.start { low = middle + 1 }
            else { high = middle }
        }
        return low < sortedDates.count && sortedDates[low] < interval.end
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

    private func readTransaction<T>(_ action: () throws -> T) throws -> T {
        try execute("BEGIN DEFERRED TRANSACTION")
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

    private func scalarInt(_ sql: String, bind: ((OpaquePointer) throws -> Void)? = nil) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind?(statement)
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW else { throw databaseError(code) }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private func find(_ id: UUID) throws -> LogEntry? {
        try queryEntries("SELECT payload FROM entries WHERE id = ?", bind: { try self.bind(id.uuidString, to: 1, in: $0) }).first
    }

    private func findDayStatus(localDate: String, timeZoneIdentifier: String) throws -> DayStatus? {
        try queryDayStatuses("SELECT payload FROM day_statuses WHERE local_date = ? AND timezone_identifier = ?", bind: {
            try self.bind(localDate, to: 1, in: $0)
            try self.bind(timeZoneIdentifier, to: 2, in: $0)
        }).first
    }

    private func hasDayStatusConflict(_ status: DayStatus) throws -> Bool {
        try scalarInt("SELECT COUNT(*) FROM day_statuses WHERE id = ? OR (local_date = ? AND timezone_identifier = ?)", bind: {
            try self.bind(status.id.uuidString, to: 1, in: $0)
            try self.bind(status.localDate, to: 2, in: $0)
            try self.bind(status.timeZoneIdentifier, to: 3, in: $0)
        }) > 0
    }

    private func hasBowelMovement(in interval: DateInterval) throws -> Bool {
        try scalarInt("SELECT EXISTS(SELECT 1 FROM entries WHERE deleted_at IS NULL AND occurred_at >= ? AND occurred_at < ?)", bind: {
            try self.check(sqlite3_bind_double($0, 1, interval.start.timeIntervalSince1970))
            try self.check(sqlite3_bind_double($0, 2, interval.end.timeIntervalSince1970))
        }) != 0
    }

    private func cancelDayStatus(_ original: DayStatus, at date: Date) throws -> DayStatus {
        guard !original.isCancelled else { return original }
        var status = original
        status.updatedAt = nextTimestamp(date, after: status.updatedAt)
        status.cancelledAt = status.updatedAt
        try status.validate()
        try writeDayStatus(status, inserting: false)
        return status
    }

    /// Called only inside the BM write transaction. Includes every saved zone
    /// whose day contains the instant, including after travel or backdating.
    /// Undo/deletion of that BM does not re-confirm the day automatically.
    private func supersedeDayStatuses(for entry: LogEntry) throws {
        guard !entry.isDeleted else { return }
        let statuses = try queryDayStatuses("SELECT payload FROM day_statuses WHERE cancelled_at IS NULL AND day_start <= ? AND day_end > ?", bind: {
            try self.check(sqlite3_bind_double($0, 1, entry.occurredAt.timeIntervalSince1970))
            try self.check(sqlite3_bind_double($0, 2, entry.occurredAt.timeIntervalSince1970))
        })
        for status in statuses { _ = try cancelDayStatus(status, at: entry.updatedAt) }
    }

    private func queryDayStatuses(_ sql: String, bind: ((OpaquePointer) throws -> Void)? = nil) throws -> [DayStatus] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind?(statement)
        var result: [DayStatus] = []
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE { break }
            guard code == SQLITE_ROW else { throw databaseError(code) }
            let count = Int(sqlite3_column_bytes(statement, 0))
            guard count > 0, let bytes = sqlite3_column_blob(statement, 0) else { throw DiaryStoreError.corruptRecord("Empty day-status record.") }
            do {
                let status = try DiaryDate.decoder().decode(DayStatus.self, from: Data(bytes: bytes, count: count))
                try status.validate()
                result.append(status)
            } catch { throw DiaryStoreError.corruptRecord(error.localizedDescription) }
        }
        return result
    }

    private func writeDayStatus(_ status: DayStatus, inserting: Bool) throws {
        try status.validate()
        let interval = try status.dayInterval()
        let data = try DiaryDate.encoder().encode(status)
        let sql = inserting
            ? "INSERT INTO day_statuses (local_date, timezone_identifier, day_start, day_end, updated_at, cancelled_at, payload, id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)"
            : "UPDATE day_statuses SET local_date = ?, timezone_identifier = ?, day_start = ?, day_end = ?, updated_at = ?, cancelled_at = ?, payload = ? WHERE id = ?"
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(status.localDate, to: 1, in: statement)
        try bind(status.timeZoneIdentifier, to: 2, in: statement)
        try check(sqlite3_bind_double(statement, 3, interval.start.timeIntervalSince1970))
        try check(sqlite3_bind_double(statement, 4, interval.end.timeIntervalSince1970))
        try check(sqlite3_bind_double(statement, 5, status.updatedAt.timeIntervalSince1970))
        if let cancelled = status.cancelledAt { try check(sqlite3_bind_double(statement, 6, cancelled.timeIntervalSince1970)) }
        else { try check(sqlite3_bind_null(statement, 6)) }
        try data.withUnsafeBytes { bytes in
            try check(sqlite3_bind_blob(statement, 7, bytes.baseAddress, Int32(bytes.count), transient))
        }
        try bind(status.id.uuidString, to: 8, in: statement)
        try stepDone(statement)
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
        try supersedeDayStatuses(for: entry)
    }
}
