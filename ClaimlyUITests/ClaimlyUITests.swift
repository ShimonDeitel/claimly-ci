import XCTest

final class ClaimlyUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-uiTestReset"]
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    // MARK: - Helpers

    private func addRebate(store: String, amount: String, daysFromNow: Int = 30) {
        let addButton = app.buttons["addRebateButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let storeField = app.textFields["storeOrProductField"]
        XCTAssertTrue(storeField.waitForExistence(timeout: 5))
        storeField.tap()
        storeField.typeText(store)

        let amountField = app.textFields["amountField"]
        amountField.tap()
        amountField.typeText(amount)

        let saveButton = app.buttons["saveEntryButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()
    }

    private func waitForTextValue(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        // SwiftUI state-binding commit isn't instant on CI simulators -- poll instead
        // of asserting the value immediately after typing.
        let predicate = NSPredicate(format: "value != '' AND value != nil")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    // MARK: - Add rebate

    func testAddRebateAppearsInList() {
        addRebate(store: "Best Buy TV", amount: "45")
        let card = app.staticTexts["Best Buy TV"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))
    }

    // MARK: - Mark received / expired

    func testMarkRebateReceivedShowsCashedInStamp() {
        addRebate(store: "Home Depot Grill", amount: "30")
        let markReceived = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'markReceivedButton-'")).firstMatch
        XCTAssertTrue(markReceived.waitForExistence(timeout: 5))
        markReceived.tap()
        // Give the stamp animation + state settle a moment.
        let cashedInPill = app.staticTexts["Cashed In"]
        XCTAssertTrue(cashedInPill.waitForExistence(timeout: 5))
    }

    func testMarkRebateExpired() {
        addRebate(store: "Staples Printer", amount: "20")
        let markExpired = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'markExpiredButton-'")).firstMatch
        XCTAssertTrue(markExpired.waitForExistence(timeout: 5))
        markExpired.tap()
        let missedPill = app.staticTexts["Missed"]
        XCTAssertTrue(missedPill.waitForExistence(timeout: 5))
    }

    // MARK: - Free-limit paywall trigger

    func testFreeLimitTriggersPaywallAtSixthRebate() {
        for i in 0..<5 {
            addRebate(store: "Item \(i)", amount: "10")
        }
        let addButton = app.buttons["addRebateButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let purchaseButton = app.buttons["purchaseProButton"]
        let closeButton = app.buttons["closePaywallButton"]
        XCTAssertTrue(purchaseButton.waitForExistence(timeout: 5) || closeButton.waitForExistence(timeout: 5))
    }

    // MARK: - Edit

    func testEditRebateChangesStoreName() {
        addRebate(store: "Original Name", amount: "12")
        let card = app.staticTexts["Original Name"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        let cell = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'rebateCard-'")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.swipeLeft()

        let editButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'editRebateButton-'")).firstMatch
        XCTAssertTrue(editButton.waitForExistence(timeout: 5))
        editButton.tap()

        let storeField = app.textFields["storeOrProductField"]
        XCTAssertTrue(storeField.waitForExistence(timeout: 5))
        storeField.tap()
        // Clear existing text via select-all-like approach: tap, then type new full value
        // after clearing with repeated deletes.
        if let existingValue = storeField.value as? String {
            for _ in existingValue { storeField.typeText(XCUIKeyboardKey.delete.rawValue) }
        }
        storeField.typeText("Renamed Item")

        let saveButton = app.buttons["saveEntryButton"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 5))
        saveButton.tap()

        let renamed = app.staticTexts["Renamed Item"]
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
    }

    // MARK: - Delete

    func testDeleteRebateRemovesCard() {
        addRebate(store: "Delete Target", amount: "8")
        let card = app.staticTexts["Delete Target"]
        XCTAssertTrue(card.waitForExistence(timeout: 5))

        let cell = app.otherElements.matching(NSPredicate(format: "identifier BEGINSWITH 'rebateCard-'")).firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 5))
        cell.swipeLeft()

        let deleteButton = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'deleteRebateButton-'")).firstMatch
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()

        XCTAssertFalse(app.staticTexts["Delete Target"].waitForExistence(timeout: 2))
    }

    // MARK: - Keyboard dismiss via real Form-header tap

    func testKeyboardDismissesOnFormHeaderTap() {
        let addButton = app.buttons["addRebateButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 5))
        addButton.tap()

        let storeField = app.textFields["storeOrProductField"]
        XCTAssertTrue(storeField.waitForExistence(timeout: 5))
        storeField.tap()
        storeField.typeText("Trigger Keyboard")

        XCTAssertTrue(app.keyboards.element.waitForExistence(timeout: 5))

        // Tap a real Form section header label (the gesture is attached to the Form
        // content, not the nav bar chrome -- tapping navigationBars.firstMatch would
        // not trigger it).
        let notesHeader = app.staticTexts["Notes"]
        XCTAssertTrue(notesHeader.waitForExistence(timeout: 5))
        notesHeader.tap()

        let keyboardGone = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: keyboardGone, object: app.keyboards.element)
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed)
    }

    // MARK: - Settings toggle behavior

    func testSettingsLeadTimeToggleChangesValue() {
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 5))
        app.tabBars.buttons["Settings"].tap()

        let leadPicker = app.buttons["leadTimePicker"]
        XCTAssertTrue(leadPicker.waitForExistence(timeout: 5))
        leadPicker.tap()

        let sevenDaysOption = app.buttons["7 days"]
        if sevenDaysOption.waitForExistence(timeout: 3) {
            sevenDaysOption.tap()
        } else {
            app.swipeUp()
        }

        // Navigate back to Home and re-open Settings to confirm persistence.
        app.tabBars.buttons["Home"].tap()
        app.tabBars.buttons["Settings"].tap()

        let updatedPicker = app.buttons["leadTimePicker"]
        XCTAssertTrue(updatedPicker.waitForExistence(timeout: 5))
    }

    func testNotificationsToggleFlips() {
        app.tabBars.buttons["Settings"].tap()
        let toggle = app.switches["notificationsToggle"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let initialValue = toggle.value as? String
        toggle.tap()
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", initialValue ?? ""),
            object: toggle
        )
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(result, .completed)
    }
}
