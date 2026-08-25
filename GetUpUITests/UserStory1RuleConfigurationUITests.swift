import XCTest

final class UserStory1RuleConfigurationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRequiredInputValidationAndApplicationSelection() {
        let app = launchApp(
            scenario: "empty-editor",
            storeID: #function,
            resetStore: true,
            familyPickerResult: "one-application"
        )

        let saveButton = app.buttons["ruleEditor.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertFalse(saveButton.isEnabled)
        XCTAssertTrue(app.staticTexts["ruleEditor.weekday.validation"].exists)
        XCTAssertTrue(app.staticTexts["ruleEditor.location.validation"].exists)
        XCTAssertTrue(app.staticTexts["ruleEditor.application.validation"].exists)

        let ruleName = app.textFields["ruleEditor.name"]
        ruleName.tap()
        ruleName.typeText("Morning Focus")

        let monday = app.buttons["ruleEditor.weekday.monday"]
        monday.tap()
        XCTAssertTrue(monday.isSelected)

        app.buttons["ruleEditor.locationRow"].tap()
        XCTAssertTrue(app.buttons["locationPicker.savedPlace.home"].exists)
        XCTAssertTrue(app.buttons["locationPicker.savedPlace.work"].exists)
        app.buttons["locationPicker.customPlace"].tap()
        let placeName = app.textFields["locationPicker.placeName"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 2))
        placeName.typeText("12345678901")
        let cappedValue = expectation(
            for: NSPredicate(format: "value == %@", "1234567890"),
            evaluatedWith: placeName
        )
        wait(for: [cappedValue], timeout: 2)
        app.buttons["locationPicker.savedPlace.home"].tap()
        app.buttons["locationPicker.confirm"].tap()
        XCTAssertEqual(app.staticTexts["ruleEditor.locationSummary"].label, "집 · 1km")

        app.buttons["ruleEditor.applicationRow"].tap()
        let applicationSummary = app.staticTexts["ruleEditor.applicationSummary"]
        XCTAssertTrue(applicationSummary.waitForExistence(timeout: 2))
        XCTAssertEqual(applicationSummary.label, "1개 앱 선택됨")

        XCTAssertTrue(saveButton.isEnabled)
    }

    @MainActor
    func testValidRuleSavesAndReloadsFromPersistentStore() {
        let storeID = #function
        var app = launchApp(
            scenario: "valid-rule-draft",
            storeID: storeID,
            resetStore: true,
            familyPickerResult: "one-application"
        )

        XCTAssertEqual(app.buttons["ruleEditor.startTime"].value as? String, "06:00 AM")
        XCTAssertEqual(app.buttons["ruleEditor.endTime"].value as? String, "09:00 AM")
        XCTAssertEqual(app.staticTexts["ruleEditor.applicationSummary"].label, "1개 앱 선택됨")

        app.buttons["ruleEditor.save"].tap()

        assertFirstRuleCard(in: app)

        app.terminate()
        app = launchApp(storeID: storeID)

        assertFirstRuleCard(in: app)
    }

    @MainActor
    func testHomePagerShowsEverySavedRuleAndSupportsBidirectionalSwipe() {
        let app = launchApp(
            scenario: "three-saved-rules",
            storeID: #function,
            resetStore: true
        )
        let pager = app.otherElements["home.rulePager"]

        XCTAssertTrue(pager.waitForExistence(timeout: 2))
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-1"].exists)
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "1 / 3")

        pager.swipeLeft()
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-2"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "2 / 3")

        pager.swipeLeft()
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-3"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "3 / 3")

        pager.swipeRight()
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-2"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "2 / 3")
    }

    @MainActor
    func testEditingAHomeCardPreservesThatRulesValues() {
        let app = launchApp(
            scenario: "three-saved-rules",
            storeID: #function,
            resetStore: true
        )
        let pager = app.otherElements["home.rulePager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 2))

        pager.swipeLeft()
        app.buttons["home.ruleCard.rule-2.edit"].tap()

        XCTAssertEqual(app.textFields["ruleEditor.name"].value as? String, "퇴근 준비")
        XCTAssertEqual(app.buttons["ruleEditor.startTime"].value as? String, "06:00 PM")
        XCTAssertEqual(app.buttons["ruleEditor.endTime"].value as? String, "08:00 PM")
        XCTAssertEqual(app.staticTexts["ruleEditor.locationSummary"].label, "회사 · 500m")
        XCTAssertEqual(app.staticTexts["ruleEditor.applicationSummary"].label, "2개 앱 선택됨")
    }

    @MainActor
    func testDeletingAHomeRuleRequiresConfirmationAndPersistsAfterRelaunch() {
        let storeID = #function
        var app = launchApp(
            scenario: "three-saved-rules",
            storeID: storeID,
            resetStore: true
        )
        let pager = app.otherElements["home.rulePager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 2))

        pager.swipeLeft()
        app.buttons["home.ruleCard.rule-2.edit"].tap()
        app.buttons["ruleEditor.delete"].tap()

        let confirmation = app.alerts["규칙을 삭제할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["삭제"].tap()

        XCTAssertTrue(app.otherElements["home.rulePager"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "1 / 2")

        app.terminate()
        app = launchApp(storeID: storeID)
        XCTAssertTrue(app.otherElements["home.rulePager"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "1 / 2")
    }

    @MainActor
    private func launchApp(
        scenario: String? = nil,
        storeID: String,
        resetStore: Bool = false,
        familyPickerResult: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-test-store-id", storeID,
        ]

        if let scenario {
            app.launchArguments += ["--ui-test-scenario", scenario]
        }
        if resetStore {
            app.launchArguments.append("--ui-test-reset-store")
        }
        if let familyPickerResult {
            app.launchArguments += ["--ui-test-family-picker-result", familyPickerResult]
        }

        app.launch()
        return app
    }

    @MainActor
    private func assertFirstRuleCard(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let card = app.otherElements["home.ruleCard.rule-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 2), file: file, line: line)
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.time"].label,
            "06:00 AM → 09:00 AM",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.schedule"].label,
            "RULE 1 OF 1 · MON–WED–FRI",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.location"].label,
            "집 · 1km",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.applications"].label,
            "1개 앱",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.otherElements["home.rulePageIndicator"].label,
            "1 / 1",
            file: file,
            line: line
        )
    }
}
