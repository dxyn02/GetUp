import XCTest

final class UserStory3AutoReleaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testActiveRestrictionRejectsEditingDisablingAndDeleting() {
        let app = launchApp(
            now: "2026-08-24T07:00:00Z",
            locationState: "inside"
        )

        let activeStatus = app.staticTexts["restrictionStatus.active"]
        XCTAssertTrue(activeStatus.waitForExistence(timeout: 2))
        XCTAssertEqual(activeStatus.label, "현재 활성화됨")
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.schedule"].label,
            "RULE 1 OF 1 · MON-FRI"
        )

        let guardedEdit = app.buttons["restrictionStatus.editDisabled"]
        XCTAssertTrue(guardedEdit.waitForExistence(timeout: 2))
        XCTAssertEqual(guardedEdit.label, "규칙 적용 중 수정 불가")
        guardedEdit.tap()

        let alert = app.alerts["제한 중에는 수정할 수 없어요"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(
            alert.staticTexts[
                "집 1km 밖으로 이동하거나 09:00 AM이 지나면 규칙을 수정·끄기·삭제할 수 있어요."
            ].exists
        )
        alert.buttons["확인"].tap()

        XCTAssertTrue(app.staticTexts["restrictionStatus.active"].exists)
        XCTAssertFalse(app.textFields["ruleEditor.name"].exists)
        XCTAssertFalse(app.switches["ruleEditor.enabled"].exists)
        XCTAssertFalse(app.buttons["ruleEditor.delete"].exists)
    }

    @MainActor
    func testReleasedRestrictionAllowsEditingAndDisabling() {
        let app = launchApp(
            now: "2026-08-24T10:00:00Z",
            locationState: "inside"
        )

        let edit = app.buttons["home.ruleCard.rule-1.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()

        let enabledSwitch = app.switches["ruleEditor.enabled"]
        XCTAssertTrue(enabledSwitch.waitForExistence(timeout: 2))
        XCTAssertEqual(enabledSwitch.value as? String, "1")
        enabledSwitch.tap()
        XCTAssertEqual(enabledSwitch.value as? String, "0")

        app.buttons["ruleEditor.save"].tap()

        XCTAssertTrue(
            app.staticTexts["restrictionStatus.inactive"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.staticTexts["restrictionStatus.active"].exists)
    }

    @MainActor
    func testReleasedRestrictionAllowsDeletion() {
        let app = launchApp(
            now: "2026-08-24T07:00:00Z",
            locationState: "outside"
        )

        let edit = app.buttons["home.ruleCard.rule-1.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()

        app.buttons["ruleEditor.delete"].tap()
        let confirmation = app.alerts["규칙을 삭제할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["삭제"].tap()

        XCTAssertTrue(
            app.buttons["ruleEditor.delete"]
                .waitForNonExistence(timeout: 5)
        )
        XCTAssertFalse(app.otherElements["home.ruleCard.rule-1"].exists)
    }

    @MainActor
    private func launchApp(
        now: String,
        locationState: String
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-test-store-id", #function,
            "--ui-test-reset-store",
            "--ui-test-scenario", "restriction-activation",
            "--ui-test-now", now,
            "--ui-test-location-state", locationState,
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
        app.launch()
        return app
    }
}
