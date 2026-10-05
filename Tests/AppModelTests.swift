import XCTest
@testable import Pupudiary

@MainActor final class AppModelTests: XCTestCase {
    func testDeletingAnotherEntryClearsSaveUndoWithoutDeletingTheSavedEntry() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(testingDirectory: directory)
        let store = try XCTUnwrap(model.store)
        let older = try store.insert(LogEntry(occurredAt: Date().addingTimeInterval(-3_600)))
        let newest = LogEntry()
        XCTAssertTrue(model.save(newest, existing: false))
        XCTAssertEqual(model.undoID, newest.id)
        XCTAssertTrue(model.delete(older))
        XCTAssertNil(model.undoID)
        model.undoSave()
        XCTAssertNil(try store.entry(id: newest.id)?.deletedAt)
        XCTAssertNotNil(try store.entry(id: older.id)?.deletedAt)
        await model.reloadAsync()
        XCTAssertEqual(try store.entries().map(\.id), [newest.id])
    }

    func testSupplementingQuickSaveEditsSameUUIDWithoutCreatingDuplicate() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(testingDirectory: directory)
        model.quickSave()
        let store = try XCTUnwrap(model.store)
        model.entries = try store.entries()
        let original = try XCTUnwrap(model.entries.first)
        model.openDetailedRecord()
        var editing = try XCTUnwrap(model.editing)
        XCTAssertEqual(editing.id, original.id)
        editing.note = "补充详情"
        XCTAssertTrue(model.save(editing, existing: true))
        await model.reloadAsync()
        let records = try store.entries()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.id, original.id)
        XCTAssertEqual(records.first?.note, "补充详情")
        XCTAssertEqual(records.first?.occurredAt, original.occurredAt)
    }
}
