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

    func testQuickLogIntentPersistsBeforeReturningWithUnknownOptionalDetails() async throws {
        #if DEBUG && targetEnvironment(simulator)
        let isolated = directory.appendingPathComponent("intent-only", isDirectory: true)
        let url = try StorageLocation.database(in: isolated)
        let reader = try DiaryStore(url: url)
        let before = Date().addingTimeInterval(-1)
        try await QuickLogIntent.$testingDirectory.withValue(isolated) {
            _ = try await QuickLogIntent().perform()
        }
        let entries = try reader.entries()
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)
        XCTAssertGreaterThanOrEqual(entry.occurredAt, before)
        XCTAssertLessThanOrEqual(entry.occurredAt, Date().addingTimeInterval(1))
        XCTAssertNil(entry.bristol)
        XCTAssertNil(entry.color)
        XCTAssertNil(entry.amount)
        XCTAssertNil(entry.effort)
        XCTAssertNil(entry.symptoms)
        XCTAssertNil(entry.durationMinutes)
        XCTAssertNil(entry.note)
        #else
        throw XCTSkip("Actual AppIntent execution requires iOS Simulator; this test does not claim App Group entitlement availability.")
        #endif
    }

    func testQuickLogIntentPersistsIntoIsolatedAppGroupAndOpenAppConnectionSeesIt() async throws {
        #if DEBUG && targetEnvironment(simulator)
        guard let sharedDirectory = StorageLocation.sharedDirectory else {
            throw XCTSkip("App Group entitlement/container is unavailable in this simulator signing configuration. The test will not use production storage or a private fallback.")
        }
        let isolatedDirectory = sharedDirectory
            .appendingPathComponent("PupudiaryCoreTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: isolatedDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: isolatedDirectory) }
        let url = try StorageLocation.database(in: isolatedDirectory)
        // Open an app-side connection before the intent writes on its own
        // connection, then verify a fresh read observes the committed result.
        var appReader: DiaryStore? = try DiaryStore(url: url)
        defer { appReader = nil }
        XCTAssertTrue(try XCTUnwrap(appReader).entries().isEmpty)
        let earliest = Date().addingTimeInterval(-1)
        try await QuickLogIntent.$testingDirectory.withValue(isolatedDirectory) {
            _ = try await QuickLogIntent().perform()
        }
        let entries = try XCTUnwrap(appReader).entries()
        XCTAssertEqual(entries.count, 1)
        let saved = try XCTUnwrap(entries.first)
        XCTAssertGreaterThanOrEqual(saved.occurredAt, earliest)
        XCTAssertLessThanOrEqual(saved.occurredAt, Date().addingTimeInterval(1))
        XCTAssertNil(saved.bristol)
        XCTAssertNil(saved.color)
        XCTAssertNil(saved.amount)
        XCTAssertNil(saved.effort)
        XCTAssertNil(saved.symptoms)
        XCTAssertNil(saved.durationMinutes)
        XCTAssertNil(saved.note)
        XCTAssertNil(saved.deletedAt)
        // Reopening verifies persistence beyond the live reader's lifetime.
        appReader = nil
        appReader = try DiaryStore(url: url)
        XCTAssertEqual(try XCTUnwrap(appReader).entries(), [saved])
        #else
        throw XCTSkip("This integration test requires a Debug iOS simulator build with an App Group container; device and Release builds have no storage override.")
        #endif
    }

    func testSummaryUsesHalfOpenBoundariesOnTwentyThreeHourSpringDSTDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(DiaryDate.parse("2026-03-08T00:00:00-05:00"))
        let end = try XCTUnwrap(DiaryDate.parse("2026-03-09T00:00:00-04:00"))
        XCTAssertEqual(end.timeIntervalSince(start), 23 * 3_600)
        let store = try DiaryStore(url: databaseURL)
        for date in [start.addingTimeInterval(-0.001), start, end.addingTimeInterval(-0.001), end] {
            try store.insert(makeEntry(at: date))
        }
        let summary = try store.summary(on: start.addingTimeInterval(12 * 3_600), calendar: calendar)
        XCTAssertEqual(summary.count, 2, "Include start, exclude the following local midnight")
        XCTAssertEqual(summary.last?.occurredAt, end, "Latest is global, not restricted to the requested day")
    }

    func testSummaryCountsBothRepeatedHoursOnTwentyFiveHourFallDSTDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let start = try XCTUnwrap(DiaryDate.parse("2026-11-01T00:00:00-04:00"))
        let end = try XCTUnwrap(DiaryDate.parse("2026-11-02T00:00:00-05:00"))
        let firstOneThirty = try XCTUnwrap(DiaryDate.parse("2026-11-01T01:30:00-04:00"))
        let secondOneThirty = try XCTUnwrap(DiaryDate.parse("2026-11-01T01:30:00-05:00"))
        XCTAssertEqual(end.timeIntervalSince(start), 25 * 3_600)
        let store = try DiaryStore(url: databaseURL)
        let dates = [start.addingTimeInterval(-0.001), start, firstOneThirty, secondOneThirty, end.addingTimeInterval(-0.001), end]
        for date in dates { try store.insert(makeEntry(at: date)) }
        let summary = try store.summary(on: secondOneThirty, calendar: calendar)
        XCTAssertEqual(summary.count, 4)
        XCTAssertEqual(summary.last?.occurredAt, end)
    }

    func testSummaryIgnoresDeletedRowsAndCanReturnPreviousDaysLatest() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let noon = try XCTUnwrap(DiaryDate.parse("2026-10-05T12:00:00Z"))
        let previous = try XCTUnwrap(DiaryDate.parse("2026-10-04T23:00:00Z"))
        let store = try DiaryStore(url: databaseURL)
        let empty = try store.summary(on: noon, calendar: calendar)
        XCTAssertEqual(empty.count, 0)
        XCTAssertNil(empty.last)
        let previousEntry = try store.insert(makeEntry(at: previous))
        let today = try store.insert(makeEntry(at: noon))
        XCTAssertEqual(try store.summary(on: noon, calendar: calendar).count, 1)
        try store.softDelete(id: today.id, at: noon.addingTimeInterval(60))
        let summary = try store.summary(on: noon, calendar: calendar)
        XCTAssertEqual(summary.count, 0)
        XCTAssertEqual(summary.last, previousEntry)
    }

    func testSummaryDecodesOnlyLatestPayloadWithoutLoadingFullHistory() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let store = try DiaryStore(url: databaseURL)
        let older = try store.insert(makeEntry())
        let latest = try store.insert(makeEntry(at: epoch.addingTimeInterval(60)))
        var raw: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &raw), SQLITE_OK)
        defer { sqlite3_close_v2(raw) }
        // Corrupt only the older payload in this isolated test database. A
        // full-history decode would throw; the widget-sized query must not.
        let damageOlderPayload = "UPDATE entries SET payload = x'7b7d' WHERE id = '\(older.id.uuidString)'"
        XCTAssertEqual(sqlite3_exec(raw, damageOlderPayload, nil, nil, nil), SQLITE_OK)
        let summary = try store.summary(on: epoch, calendar: calendar)
        XCTAssertEqual(summary.count, 2)
        XCTAssertEqual(summary.last, latest)
        XCTAssertThrowsError(try store.entries())
    }

    func testCachedDateCodecConcurrentlyPreservesOffsetsAndMilliseconds() {
        let fixtures: [(input: String, expectedUTC: String)] = [
            ("2026-11-01T01:30:00.123-04:00", "2026-11-01T05:30:00.123Z"),
            ("2026-11-01T01:30:00.987-05:00", "2026-11-01T06:30:00.987Z"),
            ("2026-10-05T19:10:00+08:00", "2026-10-05T11:10:00.000Z"),
            ("2028-02-29T12:34:56.789Z", "2028-02-29T12:34:56.789Z")
        ]
        let results = ConcurrentResults()
        DispatchQueue.concurrentPerform(iterations: 512) { index in
            let fixture = fixtures[index % fixtures.count]
            guard let parsed = DiaryDate.parse(fixture.input) else {
                results.add(NSError(domain: "DateCodecTest", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse \(fixture.input)"]))
                return
            }
            let formatted = DiaryDate.string(parsed)
            if formatted != fixture.expectedUTC || DiaryDate.parse(formatted) != parsed {
                results.add(NSError(domain: "DateCodecTest", code: 2, userInfo: [NSLocalizedDescriptionKey: "Concurrent roundtrip changed \(fixture.input) to \(formatted)"]))
            }
            if DiaryDate.parse("2026-02-30T12:00:00Z") != nil {
                results.add(NSError(domain: "DateCodecTest", code: 3, userInfo: [NSLocalizedDescriptionKey: "Impossible date accepted during concurrent parsing"]))
            }
        }
        XCTAssertTrue(results.errors.isEmpty, results.errors.joined(separator: "\n"))
    }

    func testMaximumEntryBackupFixtureRoundTripsWithinSupportedByteLimit() throws {
        // Exercise the supported record limit once, rather than repeating a
        // large performance measure ten times or enforcing a flaky time cap.
        // Mostly timestamp-only rows with occasional realistic details reflect
        // years of use; the fixture is generated and contains no user data.
        let started = ProcessInfo.processInfo.systemUptime
        let count = DiaryStore.maximumBackupEntries
        var fixture: [LogEntry] = []
        fixture.reserveCapacity(count)
        for index in 0..<count {
            let fractionalSecond = Double(index % 1_000) / 1_000
            let occurred = epoch.addingTimeInterval(-Double(index) * 6 * 3_600 + fractionalSecond)
            var entry = LogEntry(occurredAt: occurred, createdAt: epoch, updatedAt: epoch)
            if index % 10 == 0 {
                entry.bristol = 4
                entry.color = "棕色"
                entry.amount = "适中"
                entry.effort = "轻松"
                entry.symptoms = index % 20 == 0 ? [] : ["腹胀"]
                entry.durationMinutes = 3
                entry.note = "Breakfast, then a quiet moment."
            }
            if index % 17 == 0 {
                entry.updatedAt = epoch.addingTimeInterval(60)
                entry.deletedAt = entry.updatedAt
            }
            fixture.append(entry)
        }
        let data = try backup(fixture)
        XCTAssertEqual(fixture.count, 25_000)
        XCTAssertGreaterThan(data.count, 1_024 * 1_024)
        XCTAssertLessThanOrEqual(data.count, DiaryStore.maximumBackupBytes)
        let store = try DiaryStore(url: databaseURL)
        let preview = store.validateBackup(data)
        XCTAssertTrue(preview.isValid, preview.errors.joined(separator: "\n"))
        XCTAssertEqual(preview.entryCount, count)
        XCTAssertEqual(preview.newCount, count)
        let result = try store.mergeJSON(data)
        XCTAssertEqual(result.insertedCount, count)
        XCTAssertEqual(result.skippedCount, 0)
        let exported = try store.exportJSON()
        XCTAssertLessThanOrEqual(exported.count, DiaryStore.maximumBackupBytes)
        let restored = try DiaryDate.decoder().decode(DiaryBackup.self, from: exported)
        XCTAssertEqual(restored.entries.count, fixture.count)
        for index in fixture.indices {
            guard restored.entries.indices.contains(index) else { break }
            if restored.entries[index] != fixture[index] {
                XCTFail("Maximum-entry backup changed record at index \(index)")
                break
            }
        }
        let first = try XCTUnwrap(restored.entries.first)
        let second = try XCTUnwrap(restored.entries.dropFirst().first)
        XCTAssertNil(second.symptoms)
        XCTAssertEqual(first.symptoms, [])
        XCTAssertNotNil(first.deletedAt)
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let measurement = XCTAttachment(string: "Generated backup fixture: \(count) records, \(data.count) input bytes, \(exported.count) exported bytes. Encode + validation + SQLite restore + export + decode elapsed: \(elapsed) seconds. No fixed timing threshold.")
        measurement.name = "Maximum-entry backup performance fixture"
        measurement.lifetime = .keepAlways
        add(measurement)
    }

    func testNextMidnightUsesLocalBoundariesThroughDSTAndEndOfDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let fixtures: [(start: String, end: String, hours: Double)] = [
            ("2026-03-08T00:00:00-05:00", "2026-03-09T00:00:00-04:00", 23),
            ("2026-11-01T00:00:00-04:00", "2026-11-02T00:00:00-05:00", 25)
        ]
        for fixture in fixtures {
            let start = try XCTUnwrap(DiaryDate.parse(fixture.start))
            let end = try XCTUnwrap(DiaryDate.parse(fixture.end))
            XCTAssertEqual(DiaryDate.nextMidnight(after: start, calendar: calendar), end)
            XCTAssertEqual(end.timeIntervalSince(start), fixture.hours * 3_600)
            XCTAssertEqual(DiaryDate.nextMidnight(after: end.addingTimeInterval(-0.001), calendar: calendar), end)
            let following = try XCTUnwrap(DiaryDate.nextMidnight(after: end, calendar: calendar))
            XCTAssertGreaterThan(following, end, "At midnight, schedule the following day rather than immediately firing again")
            XCTAssertEqual(following.timeIntervalSince(end), 24 * 3_600)
        }
        XCTAssertNil(DiaryDate.nextMidnight(after: Date(timeIntervalSince1970: .infinity), calendar: calendar))
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
