import XCTest

/// Real iOS Simulator smoke tests. Each --uitesting launch uses isolated demo data.
final class PupudiaryUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting", "--screen", "home"]
        app.launch()
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 20))
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "enabled == true"), object: app.buttons["quick-save"])
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 15), .completed)
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

// Native screenshot-only cases run in their own CI shards so their result bundle
// finalizes and uploads without waiting for unrelated interaction tests.
extension PupudiaryUITests {
    @MainActor
    @objc func test00CaptureNativeScreensForRecovery() throws {
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 20))
        scrollToTop()
        XCTAssertTrue(app.staticTexts["entry-count"].exists)
        retainNativeCapture("home")

        app.buttons["open-record"].tap()
        XCTAssertTrue(app.buttons["cancel-record"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["save-record"].exists)
        // A new sheet starts at its top; swiping down here could dismiss it.
        retainNativeCapture("record")
        app.buttons["cancel-record"].tap()
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 10))

        launchScreen("widget-preview")
        XCTAssertTrue(app.staticTexts["排便记录小组件"].waitForExistence(timeout: 20))
        retainNativeCapture("widget-preview-app-hosted")
    }

    @MainActor
    @objc func testCaptureRedesignedHomeAndRecord() throws {
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 20))
        scrollToTop()
        XCTAssertTrue(app.staticTexts["排便记录"].exists)
        retainNativeCapture("redesigned-home")
        app.buttons["open-record"].tap()
        XCTAssertTrue(app.buttons["save-record"].waitForExistence(timeout: 10))
        let firstShapeAppeared = app.buttons["bristol-1"].waitForExistence(timeout: 10)
        retainNativeCapture("redesigned-record")
        XCTAssertTrue(firstShapeAppeared)
        XCTAssertTrue(app.buttons["bristol-7"].isHittable)
        XCTAssertTrue(app.buttons["effort-easy"].isHittable)
        XCTAssertTrue(app.buttons["effort-hard"].isHittable)
    }

    @MainActor
    @objc func testNativeAppearanceAndSecondaryScreens() throws {
        launchScreen("home", flags: ["--dark-mode"])
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 20))
        scrollToTop()
        retainNativeCapture("home-dark")

        launchScreen("home", flags: ["--large-type"])
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 20))
        scrollToTop()
        retainNativeCapture("home-large-type")

        // Navigate within the same native process for the two secondary screens.
        app.tabBars.buttons["记录"].tap()
        XCTAssertTrue(app.navigationBars["排便历史"].waitForExistence(timeout: 10))
        scrollToTop()
        retainNativeCapture("history-large-type")
        app.tabBars.buttons["趋势"].tap()
        XCTAssertTrue(app.navigationBars["排便趋势"].waitForExistence(timeout: 10))
        scrollToTop()
        retainNativeCapture("trends-large-type")
    }

    @MainActor
    @objc func testSupplementAfterQuickSaveDoesNotDuplicate() throws {
        let initial = try count()
        app.buttons["quick-save"].tap()
        expectCount(initial + 1)
        let supplement = app.buttons["open-record"]
        XCTAssertEqual(supplement.label, "补充刚才记录")
        supplement.tap()
        XCTAssertTrue(app.buttons["save-record"].waitForExistence(timeout: 10))
        let type = app.buttons["bristol-4"]
        reveal(type)
        type.tap()
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 10))
        expectCount(initial + 1)
        XCTAssertEqual(app.buttons["open-record"].label, "详细记录")
        keepScreenshot("supplement-updates-existing-record")
    }

    @MainActor
    @objc func testEmptyDiaryHasNoInventedBowelInterval() throws {
        launchScreen("home", flags: ["--empty-diary"])
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["尚无排便记录"].exists)
        XCTAssertFalse(app.staticTexts["last-bowel-interval"].exists)
        keepScreenshot("empty-diary-no-invented-interval")
    }

    @MainActor
    @objc func testRecordKeyboardScrollAndNotePersistence() throws {
        let initial = try count()
        app.buttons["open-record"].tap()
        XCTAssertTrue(app.buttons["save-record"].waitForExistence(timeout: 10))
        let moreDetails = app.buttons["more-details-toggle"]
        reveal(moreDetails)
        moreDetails.tap()
        let duration = app.descendants(matching: .any).matching(identifier: "duration-field").firstMatch
        reveal(duration)
        duration.tap()
        duration.typeText("7")
        // Exercise interactive keyboard dismissal while reaching the lower note field.
        visibleScrollView().swipeUp()
        let note = app.descendants(matching: .any).matching(identifier: "note-field").firstMatch
        reveal(note)
        note.tap()
        note.typeText("CI keyboard and scroll note")
        visibleScrollView().swipeDown()
        keepScreenshot("record-note-after-keyboard-scroll")
        app.buttons["save-record"].tap()
        XCTAssertTrue(app.buttons["quick-save"].waitForExistence(timeout: 10))
        expectCount(initial + 1)

        // A newly saved entry is offered for supplementation; verify persisted fields.
        app.buttons["open-record"].tap()
        XCTAssertTrue(app.buttons["cancel-record"].waitForExistence(timeout: 10))
        reveal(note)
        XCTAssertTrue((note.value as? String)?.contains("CI keyboard and scroll note") == true)
        XCTAssertEqual(duration.value as? String, "7")
        app.buttons["cancel-record"].tap()
        expectCount(initial + 1)
    }

    @MainActor
    private func launchScreen(_ screen: String, flags: [String] = []) {
        app.terminate()
        app.launchArguments = ["--uitesting", "--screen", screen] + flags
        app.launch()
    }

    @MainActor
    private func visibleScrollView() -> XCUIElement {
        app.scrollViews.allElementsBoundByIndex.first(where: { $0.isHittable }) ?? app.scrollViews.firstMatch
    }

    @MainActor
    private func scrollToTop() {
        let scroll = visibleScrollView()
        if scroll.exists { scroll.swipeDown(); scroll.swipeDown() }
    }

    @MainActor
    private func reveal(_ element: XCUIElement, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            visibleScrollView().swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Field must be reachable by native scrolling", file: file, line: line)
    }

    @MainActor
    private func retainNativeCapture(_ screen: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Pupudiary-native-\(screen)"
        attachment.lifetime = .keepAlways
        add(attachment)
        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Pupudiary-native-\(screen)-accessibility-hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)
    }
}
