import Foundation
import SQLite3
import XCTest
@testable import Pupudiary

final class CoreTests: XCTestCase {
    private var directory: URL!
    private var databaseURL: URL { directory.appendingPathComponent("diary.sqlite3") }
    private let epoch = Date(timeIntervalSince1970: 1_790_000_000)

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("PupudiaryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    private func makeEntry(at date: Date? = nil, note: String? = nil) -> LogEntry {
        LogEntry(occurredAt: date ?? epoch, createdAt: epoch, updatedAt: epoch, note: note)
    }

    private func backup(_ entries: [LogEntry]) throws -> Data {
        try DiaryDate.encoder().encode(DiaryBackup(format: "pupudiary", schemaVersion: 1, exportedAt: epoch, entries: entries))
    }

    func testQuickLogSavesOnlyTimestampAndLeavesAllDetailsUnknown() throws {
        let store = try DiaryStore(url: databaseURL)
        let result = try store.quickLog(at: epoch)
        XCTAssertTrue(result.wasInserted)
        XCTAssertEqual(result.entry.occurredAt, epoch)
        XCTAssertEqual(result.entry.createdAt, epoch)
        XCTAssertEqual(result.entry.updatedAt, epoch)
        XCTAssertNil(result.entry.bristol)
        XCTAssertNil(result.entry.color)
        XCTAssertNil(result.entry.amount)
        XCTAssertNil(result.entry.effort)
        XCTAssertNil(result.entry.symptoms)
        XCTAssertNil(result.entry.durationMinutes)
        XCTAssertNil(result.entry.note)
        XCTAssertNil(result.entry.deletedAt)
        XCTAssertEqual(try store.entries(), [result.entry])
    }

    func testRapidDistinctRequestsDeduplicateThroughInclusiveTwoSecondBoundary() throws {
        let store = try DiaryStore(url: databaseURL)
        let first = try store.quickLog(at: epoch)
        let boundary = try store.quickLog(at: epoch.addingTimeInterval(2))
        XCTAssertFalse(boundary.wasInserted)
        XCTAssertEqual(first.entry.id, boundary.entry.id)
        let later = try store.quickLog(at: epoch.addingTimeInterval(4.001))
        XCTAssertTrue(later.wasInserted)
        XCTAssertNotEqual(first.entry.id, later.entry.id)
        XCTAssertEqual(try store.entries().count, 2)
    }

    func testRequestIdentifierIsIdempotentAcrossReopenAndLongDelay() throws {
        let request = UUID()
        let first: LogEntry = try {
            let store = try DiaryStore(url: databaseURL)
            return try store.quickLog(at: epoch, requestID: request).entry
        }()
        let reopened = try DiaryStore(url: databaseURL)
        let retry = try reopened.quickLog(at: epoch.addingTimeInterval(86_400), requestID: request)
        XCTAssertFalse(retry.wasInserted)
        XCTAssertEqual(retry.entry, first)
        XCTAssertEqual(try reopened.entries().count, 1)
    }

    func testConcurrentQuickRequestsAcrossEightConnectionsProduceOneEntry() throws {
        let stores = try (0..<8).map { _ in try DiaryStore(url: databaseURL) }
        let results = ConcurrentResults()
        let timestamp = epoch
        DispatchQueue.concurrentPerform(iterations: 64) { index in
            do { results.add(try stores[index % stores.count].quickLog(at: timestamp)) }
            catch { results.add(error) }
        }
        XCTAssertTrue(results.errors.isEmpty, results.errors.joined(separator: "\n"))
        XCTAssertEqual(results.quickResults.count, 64)
        XCTAssertEqual(results.quickResults.filter(\.wasInserted).count, 1)
        XCTAssertEqual(Set(results.quickResults.map { $0.entry.id }).count, 1)
        XCTAssertEqual(try stores[0].entries().count, 1)
    }

    func testConcurrentManualWritesAcrossConnectionsHaveNoLostEntries() throws {
        let stores = try (0..<8).map { _ in try DiaryStore(url: databaseURL) }
        let results = ConcurrentResults()
        let timestamp = epoch
        DispatchQueue.concurrentPerform(iterations: 96) { index in
            do {
                let entry = LogEntry(occurredAt: timestamp.addingTimeInterval(Double(index)), createdAt: timestamp, updatedAt: timestamp, note: "Record \(index)")
                try stores[index % stores.count].insert(entry)
            } catch { results.add(error) }
        }
        XCTAssertTrue(results.errors.isEmpty, results.errors.joined(separator: "\n"))
        let entries = try stores[0].entries()
        XCTAssertEqual(entries.count, 96)
        XCTAssertEqual(Set(entries.map(\.id)).count, 96)
        XCTAssertEqual(entries.first?.note, "Record 95")
    }

    func testManualBackdatedEntryDoesNotParticipateInQuickDeduplication() throws {
        let store = try DiaryStore(url: databaseURL)
        let manual = try store.insert(makeEntry(at: epoch.addingTimeInterval(-86_400), note: "Yesterday"))
        let sameTimeManual = try store.insert(makeEntry())
        let quick = try store.quickLog(at: epoch)
        XCTAssertTrue(quick.wasInserted)
        XCTAssertNotEqual(sameTimeManual.id, quick.entry.id)
        XCTAssertEqual(try store.entries().last?.id, manual.id)
        XCTAssertEqual(try store.entries().count, 3)
    }

    func testUpdatesPreserveCreationAndAdvanceTimestampEvenWhenClockMovesBackwards() throws {
        let store = try DiaryStore(url: databaseURL)
        let original = try store.insert(makeEntry())
        var edited = original
        edited.note = "More detail"
        edited.bristol = 4
        edited.createdAt = epoch.addingTimeInterval(-10_000)
        edited.occurredAt = epoch.addingTimeInterval(-3_600)
        try store.update(edited, at: epoch.addingTimeInterval(-60))
        let saved = try XCTUnwrap(store.entry(id: original.id))
        XCTAssertEqual(saved.createdAt, original.createdAt)
        XCTAssertGreaterThan(saved.updatedAt, original.updatedAt)
        XCTAssertEqual(saved.occurredAt, edited.occurredAt)
        XCTAssertEqual(saved.note, "More detail")
        XCTAssertEqual(saved.bristol, 4)
        XCTAssertThrowsError(try store.update(edited, at: epoch.addingTimeInterval(60))) { error in
            guard case DiaryStoreError.staleEntry = error else { return XCTFail("Expected stale edit, got \(error)") }
        }
        XCTAssertEqual(try store.entry(id: saved.id), saved)
    }

    func testInvalidManualEntryAndEditLeaveDatabaseUnchanged() throws {
        let store = try DiaryStore(url: databaseURL)
        let original = try store.insert(makeEntry())
        var invalid = makeEntry()
        invalid.bristol = 8
        XCTAssertThrowsError(try store.insert(invalid))
        invalid = original
        invalid.durationMinutes = -1
        XCTAssertThrowsError(try store.update(invalid))
        XCTAssertEqual(try store.entries(), [original])
        XCTAssertThrowsError(try store.insert(original))
    }

    func testSoftDeletionCanBeRecoveredAndRetriedRequestDoesNotResurrect() throws {
        let store = try DiaryStore(url: databaseURL)
        let request = UUID()
        let first = try store.quickLog(at: epoch, requestID: request).entry
        try store.softDelete(id: first.id, at: epoch.addingTimeInterval(1))
        XCTAssertTrue(try store.entries().isEmpty)
        let deleted = try XCTUnwrap(store.entries(includeDeleted: true).first)
        XCTAssertNotNil(deleted.deletedAt)
        XCTAssertGreaterThan(deleted.updatedAt, first.updatedAt)
        let retry = try store.quickLog(at: epoch.addingTimeInterval(1), requestID: request)
        XCTAssertFalse(retry.wasInserted)
        XCTAssertTrue(retry.entry.isDeleted)
        XCTAssertTrue(try store.entries().isEmpty)
        try store.restoreDeleted(id: first.id, at: epoch.addingTimeInterval(2))
        let restored = try XCTUnwrap(store.entries().first)
        XCTAssertEqual(restored.id, first.id)
        XCTAssertNil(restored.deletedAt)
        XCTAssertGreaterThan(restored.updatedAt, deleted.updatedAt)
    }

    func testNewTapAfterUndoCreatesAnActiveEntry() throws {
        let store = try DiaryStore(url: databaseURL)
        let first = try store.quickLog(at: epoch).entry
        try store.softDelete(id: first.id, at: epoch.addingTimeInterval(0.1))
        let second = try store.quickLog(at: epoch.addingTimeInterval(0.2))
        XCTAssertTrue(second.wasInserted)
        XCTAssertNotEqual(first.id, second.entry.id)
        XCTAssertEqual(try store.entries().count, 1)
        XCTAssertEqual(try store.entries(includeDeleted: true).count, 2)
    }

    func testJSONRoundTripPreservesNullableDetailsExplicitNoSymptomsAndDeletedRows() throws {
        let source = try DiaryStore(url: databaseURL)
        _ = try source.insert(makeEntry(at: epoch.addingTimeInterval(0.123)))
        var detailed = makeEntry(at: epoch.addingTimeInterval(60), note: "Comma, quote \" and\nnewline 💩")
        detailed.bristol = 4
        detailed.color = "Brown"
        detailed.amount = "Medium"
        detailed.effort = "Easy"
        detailed.symptoms = []
        detailed.durationMinutes = 3
        try source.insert(detailed)
        try source.softDelete(id: detailed.id, at: epoch.addingTimeInterval(120))
        let data = try source.exportJSON()
        let target = try DiaryStore(url: directory.appendingPathComponent("restored.sqlite3"))
        let preview = target.validateBackup(data)
        XCTAssertTrue(preview.isValid)
        XCTAssertEqual(preview.entryCount, 2)
        XCTAssertEqual(preview.newCount, 2)
        XCTAssertEqual(preview.existingCount, 0)
        XCTAssertTrue(try target.entries(includeDeleted: true).isEmpty, "Preview must not mutate")
        let result = try target.mergeJSON(data)
        XCTAssertEqual(result.insertedCount, 2)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(try target.entries(includeDeleted: true), try source.entries(includeDeleted: true))
        XCTAssertEqual(try target.entries().count, 1)
        let recoveredDetails = try XCTUnwrap(target.entry(id: detailed.id))
        XCTAssertEqual(recoveredDetails.symptoms, [])
        try target.restoreDeleted(id: detailed.id, at: epoch.addingTimeInterval(180))
        XCTAssertEqual(try target.entries().count, 2)
    }

    func testRestoreSkipsExistingUUIDWithoutOverwritingAnyLocalConflict() throws {
        let store = try DiaryStore(url: databaseURL)
        let local = try store.insert(makeEntry(note: "Keep local"))
        var newerBackupCopy = local
        newerBackupCopy.note = "Must not overwrite"
        newerBackupCopy.updatedAt = epoch.addingTimeInterval(86_400)
        let addition = makeEntry(at: epoch.addingTimeInterval(-100), note: "New ID")
        let data = try backup([newerBackupCopy, addition])
        let preview = store.validateBackup(data)
        XCTAssertEqual(preview.existingCount, 1)
        XCTAssertEqual(preview.newCount, 1)
        let result = try store.mergeJSON(data)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(result.insertedCount, 1)
        XCTAssertEqual(try store.entry(id: local.id), local)
        let repeated = try store.mergeJSON(data)
        XCTAssertEqual(repeated.insertedCount, 0)
        XCTAssertEqual(repeated.skippedCount, 2)
    }

    func testRestoreDoesNotResurrectLocallyDeletedExistingUUID() throws {
        let store = try DiaryStore(url: databaseURL)
        let original = try store.insert(makeEntry())
        let oldBackup = try store.exportJSON()
        try store.softDelete(id: original.id, at: epoch.addingTimeInterval(60))
        let deleted = try store.entry(id: original.id)
        let result = try store.mergeJSON(oldBackup)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertEqual(try store.entry(id: original.id), deleted)
        XCTAssertTrue(try store.entries().isEmpty)
    }

    func testOneInvalidBackupRecordRejectsEntireImportWithoutMutation() throws {
        let store = try DiaryStore(url: databaseURL)
        let existing = try store.insert(makeEntry(note: "Original"))
        let valid = makeEntry(note: "Valid but must not be partially restored")
        var invalid = makeEntry(note: "Invalid")
        invalid.bristol = 99
        let data = try backup([valid, invalid])
        let preview = store.validateBackup(data)
        XCTAssertFalse(preview.isValid)
        XCTAssertFalse(preview.errors.isEmpty)
        XCTAssertThrowsError(try store.mergeJSON(data))
        XCTAssertEqual(try store.entries(includeDeleted: true), [existing])
    }

    func testDuplicateIdentifiersAndMalformedAndOversizedBackupsAreRejected() throws {
        let store = try DiaryStore(url: databaseURL)
        let duplicated = makeEntry()
        let duplicateData = try backup([duplicated, duplicated])
        for data in [duplicateData, Data("not json".utf8), Data(), Data(repeating: 32, count: DiaryStore.maximumBackupBytes + 1)] {
            XCTAssertFalse(store.validateBackup(data).isValid)
            XCTAssertThrowsError(try store.mergeJSON(data))
        }
        XCTAssertTrue(try store.entries(includeDeleted: true).isEmpty)
    }

    func testUnsupportedBackupVersionRejectedWithoutMutation() throws {
        let store = try DiaryStore(url: databaseURL)
        let data = try DiaryDate.encoder().encode(DiaryBackup(format: "pupudiary", schemaVersion: 2, exportedAt: epoch, entries: [makeEntry()]))
        XCTAssertFalse(store.validateBackup(data).isValid)
        XCTAssertThrowsError(try store.mergeJSON(data))
        XCTAssertTrue(try store.entries().isEmpty)
    }

    func testDatabaseFailureDuringImportRollsBackEarlierRows() throws {
        let store = try DiaryStore(url: databaseURL)
        let valid = makeEntry(note: "First would succeed")
        let rejected = makeEntry(note: "Trigger rejects this UUID")
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &raw), SQLITE_OK)
        defer { sqlite3_close_v2(raw) }
        let trigger = "CREATE TRIGGER test_abort BEFORE INSERT ON entries WHEN NEW.id = '\(rejected.id.uuidString)' BEGIN SELECT RAISE(ABORT, 'injected failure'); END"
        XCTAssertEqual(sqlite3_exec(raw, trigger, nil, nil, nil), SQLITE_OK)
        XCTAssertThrowsError(try store.mergeJSON(backup([valid, rejected])))
        XCTAssertTrue(try store.entries(includeDeleted: true).isEmpty)
    }

    func testCSVIsRFC4180EscapedAndNeutralizesFormulaText() throws {
        let store = try DiaryStore(url: databaseURL)
        try store.insert(makeEntry(note: "Comma, \"quote\"\r\nnext line"))
        try store.insert(makeEntry(at: epoch.addingTimeInterval(1), note: "=HYPERLINK(\"https://example.invalid\",\"open\")"))
        try store.insert(makeEntry(at: epoch.addingTimeInterval(2), note: "  +SUM(1,2)"))
        try store.insert(makeEntry(at: epoch.addingTimeInterval(3), note: "\t@SUM(A1:A2)"))
        let text = String(decoding: try store.exportCSV(), as: UTF8.self)
        XCTAssertTrue(text.hasSuffix("\r\n"))
        XCTAssertTrue(text.contains("\"Comma, \"\"quote\"\"\r\nnext line\""))
        XCTAssertTrue(text.contains("\"'=HYPERLINK(\"\"https://example.invalid\"\",\"\"open\"\")\""))
        XCTAssertTrue(text.contains("\"'  +SUM(1,2)\""))
        XCTAssertTrue(text.contains("\"'\t@SUM(A1:A2)\""))
        XCTAssertTrue(text.contains("\"occurred_at_utc\""))
        XCTAssertTrue(text.contains(DiaryDate.string(epoch)))
        XCTAssertFalse(text.contains("<null>"))
    }

    func testUTCExportAndOffsetImportPreserveInstantAcrossDST() throws {
        let before = try XCTUnwrap(DiaryDate.parse("2026-11-01T01:30:00.123-04:00"))
        let after = try XCTUnwrap(DiaryDate.parse("2026-11-01T01:30:00.123-05:00"))
        XCTAssertEqual(after.timeIntervalSince(before), 3_600, accuracy: 0.0001)
        XCTAssertEqual(DiaryDate.string(before), "2026-11-01T05:30:00.123Z")
        XCTAssertEqual(DiaryDate.string(after), "2026-11-01T06:30:00.123Z")
        XCTAssertNil(DiaryDate.parse("2026-11-01T01:30:00.123"), "No timezone must not be silently assumed")
        let store = try DiaryStore(url: databaseURL)
        let entry = LogEntry(occurredAt: before, createdAt: before, updatedAt: before)
        var json = String(decoding: try backup([entry]), as: UTF8.self)
        json = json.replacingOccurrences(of: "2026-11-01T05:30:00.123Z", with: "2026-11-01T01:30:00.123-04:00")
        _ = try store.mergeJSON(Data(json.utf8))
        XCTAssertEqual(try store.entries().first?.occurredAt, before)
        let exported = String(decoding: try store.exportJSON(), as: UTF8.self)
        XCTAssertTrue(exported.contains("2026-11-01T05:30:00.123Z"))
    }

    func testTimestampParserRejectsImpossibleDatesAndTrailingContent() {
        XCTAssertNil(DiaryDate.parse("2026-02-30T12:00:00Z"))
        XCTAssertNil(DiaryDate.parse("2026-02-29T12:00:00Z"))
        XCTAssertNil(DiaryDate.parse("2026-10-05T24:00:00Z"))
        XCTAssertNil(DiaryDate.parse("2026-10-05T12:00:00Z trailing"))
        XCTAssertNil(DiaryDate.parse("2026-10-05T12:00:00Z\n"))
        XCTAssertNil(DiaryDate.parse("2026-10-05T12:00:00+25:00"))
        XCTAssertNotNil(DiaryDate.parse("2028-02-29T12:00:00Z"))
    }
}

/// Test-only collection avoids concurrent mutation of a captured array.
private final class ConcurrentResults: @unchecked Sendable {
    private let lock = NSLock()
    private var savedErrors: [String] = []
    private var savedQuickResults: [QuickLogResult] = []

    var errors: [String] {
        lock.lock()
        defer { lock.unlock() }
        return savedErrors
    }

    var quickResults: [QuickLogResult] {
        lock.lock()
        defer { lock.unlock() }
        return savedQuickResults
    }

    func add(_ error: Error) {
        lock.lock()
        defer { lock.unlock() }
        savedErrors.append(error.localizedDescription)
    }

    func add(_ result: QuickLogResult) {
        lock.lock()
        defer { lock.unlock() }
        savedQuickResults.append(result)
    }
}
