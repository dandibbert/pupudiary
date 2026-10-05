import XCTest

/// Real iOS Simulator smoke tests. Each --uitesting launch uses isolated demo data.
final class PupudiaryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 10))
    }

    private func count() throws -> Int {
        let value = app.staticTexts["entry-count"]
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        return try XCTUnwrap(Int(value.label), "Today's count must be a numeric accessible label")
    }

    private func expectCount(_ expected: Int, file: StaticString = #filePath, line: UInt = #line) {
        let predicate = NSPredicate(format: "label == %@", String(expected))
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app.staticTexts["entry-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func keepScreenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testQuickSaveAndUndo() throws {
        let initial = try count()
        app.buttons["quick-save"].tap()
        expectCount(initial + 1)
        XCTAssertTrue(app.buttons["undo-save"].waitForExistence(timeout: 3))
        keepScreenshot("quick-save-confirmation")
        app.buttons["undo-save"].tap()
        expectCount(initial)
        keepScreenshot("undo-confirmation")
    }

    func testRapidRepeatedQuickSaveDoesNotDuplicate() throws {
        let initial = try count()
        app.buttons["quick-save"].doubleTap()
        expectCount(initial + 1)
        keepScreenshot("rapid-save-deduplicated")
    }

    func testCancelThenReopenRecordDoesNotCreateEntry() throws {
        let initial = try count()
        for _ in 0..<2 {
            app.buttons["open-record"].tap()
            XCTAssertTrue(app.buttons["cancel-record"].waitForExistence(timeout: 3))
            app.buttons["cancel-record"].tap()
            XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 3))
            expectCount(initial)
        }
    }

    func testDetailedRecordSavesWithOptionalFieldsEmpty() throws {
        let initial = try count()
        app.buttons["open-record"].tap()
        XCTAssertTrue(app.buttons["save-record"].waitForExistence(timeout: 3))
        keepScreenshot("detailed-record-before-save")
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 3))
        expectCount(initial + 1)
    }

    func testQuickSaveSurvivesBackgroundAndForeground() throws {
        let initial = try count()
        app.buttons["quick-save"].tap()
        expectCount(initial + 1)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 5))
        expectCount(initial + 1)
        app.buttons["undo-save"].tap()
        expectCount(initial)
    }
}
