import XCTest

/// Simulator contract for the app and Shield presentation seam, not system Shield proof.
/// T054–T058 must wire the seam to the production content provider and release model.
/// Fixture: 출근 준비, 09:00 end in the fixture calendar, free 2, purchased 3.
/// Overlap adds one matching rule without changing the representative's schedule.
/// Hold mode keeps the fake release pending until coinRelease.test.complete is tapped.
/// Diagnostic counters must observe the injected ledger, never synthesize UI success.
final class UserStory2CoinReleaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testShieldShowsExistingInformationAndSingleReleaseButton() {
        let app = launchApp(storeID: #function, overlap: true)
        let open = app.buttons["restrictionProbe.selectedApplication.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let shield = app.otherElements["restrictionProbe.shield"]
        XCTAssertTrue(shield.waitForExistence(timeout: 2))
        assertInformation(in: shield, prefix: "restrictionProbe.shield")
        let release = shield.buttons["restrictionProbe.shield.release"]
        XCTAssertTrue(release.exists)
        XCTAssertEqual(release.label, "해제권 1회 사용")
        XCTAssertEqual(shield.buttons.matching(identifier: "restrictionProbe.shield.release").count, 1)
        XCTAssertEqual(shield.buttons["restrictionProbe.shield.close"].label, "앱 닫기")
        XCTAssertFalse(shield.buttons["coinRelease.chooseFundingSource"].exists)
        XCTAssertFalse(app.otherElements["restrictionProbe.selectedApplication.content"].exists)
    }

    @MainActor
    func testAppRequiresSeparateConfirmationAndCancelDoesNotSpend() {
        let app = launchApp(storeID: #function, overlap: true)
        openRelease(in: app)
        let details = app.otherElements["coinRelease.details"]
        XCTAssertTrue(details.waitForExistence(timeout: 2))
        assertInformation(in: details, prefix: "coinRelease")
        XCTAssertEqual(app.staticTexts["coinRelease.balance.free"].label, "2")
        XCTAssertEqual(app.staticTexts["coinRelease.balance.purchased"].label, "3")
        XCTAssertEqual(app.staticTexts["coinRelease.test.reservationCount"].label, "0")

        app.buttons["coinRelease.requestConfirmation"].tap()
        let dialog = app.alerts["coinRelease.confirmation"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 2))
        XCTAssertTrue(dialog.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "출근 준비")).firstMatch.exists)
        XCTAssertEqual(app.staticTexts["coinRelease.test.reservationCount"].label, "0")
        dialog.buttons["취소"].tap()
        XCTAssertFalse(dialog.exists)
        XCTAssertEqual(app.staticTexts["coinRelease.balance.free"].label, "2")
        XCTAssertEqual(app.staticTexts["coinRelease.balance.purchased"].label, "3")
        XCTAssertEqual(app.staticTexts["coinRelease.test.reservationCount"].label, "0")
    }

    @MainActor
    func testDuplicateAppConfirmationSpendsOnceAndKeepsOverlappingRestriction() {
        let app = launchApp(storeID: #function, overlap: true, holdRelease: true)
        openRelease(in: app)
        app.buttons["coinRelease.requestConfirmation"].tap()
        let dialog = app.alerts["coinRelease.confirmation"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 2))
        dialog.buttons["해제권 1회 사용"].doubleTap()
        XCTAssertTrue(app.staticTexts["coinRelease.processing"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.buttons["coinRelease.requestConfirmation"].isEnabled)
        app.buttons["coinRelease.test.complete"].tap()
        assertOneSpend(in: app)
        XCTAssertTrue(app.staticTexts["restrictionStatus.active"].exists)
        XCTAssertEqual(app.staticTexts["coinRelease.test.remainingOccurrenceCount"].label, "1")
    }

    @MainActor
    func testDuplicateShieldTapSpendsOnceWithoutAnotherConfirmation() {
        let app = launchApp(storeID: #function, overlap: true, holdRelease: true)
        let open = app.buttons["restrictionProbe.selectedApplication.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        let release = app.buttons["restrictionProbe.shield.release"]
        XCTAssertTrue(release.waitForExistence(timeout: 2))
        release.doubleTap()
        XCTAssertFalse(app.alerts["coinRelease.confirmation"].exists)
        XCTAssertTrue(app.staticTexts["coinRelease.processing"].waitForExistence(timeout: 2))
        app.buttons["coinRelease.test.complete"].tap()
        assertOneSpend(in: app)
        XCTAssertTrue(app.otherElements["restrictionProbe.shield"].exists)
        XCTAssertFalse(app.otherElements["restrictionProbe.selectedApplication.content"].exists)
    }

    @MainActor
    private func launchApp(
        storeID: String,
        overlap: Bool,
        holdRelease: Bool = false
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-test-store-id", storeID, "--ui-test-reset-store",
            "--ui-test-scenario", "restriction-activation",
            "--ui-test-now", "2026-08-24T07:00:00Z",
            "--ui-test-location-state", "inside",
            "--ui-test-coin-release", overlap ? "overlapping" : "single",
            "--ui-test-coin-release-result", holdRelease ? "held-success" : "success",
            "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func openRelease(in app: XCUIApplication) {
        let open = app.buttons["coinRelease.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
    }

    @MainActor
    private func assertInformation(in element: XCUIElement, prefix: String) {
        XCTAssertTrue(element.staticTexts["\(prefix).target"].label.contains("출근 준비"))
        let cost = element.staticTexts["\(prefix).cost"].label
        XCTAssertTrue(cost.contains("무료"))
        XCTAssertTrue(cost.contains("우선"))
        XCTAssertTrue(cost.contains("코인 1개"))
        XCTAssertTrue(element.staticTexts["\(prefix).endsAt"].label.contains("9:00"))
        XCTAssertTrue(element.staticTexts["\(prefix).remainingRestrictions"].label.contains("다른 규칙"))
    }

    @MainActor
    private func assertOneSpend(in app: XCUIApplication) {
        let spent = app.staticTexts["coinRelease.test.committedCount"]
        let committed = expectation(for: NSPredicate(format: "label == '1'"), evaluatedWith: spent)
        wait(for: [committed], timeout: 5)
        XCTAssertEqual(app.staticTexts["coinRelease.test.reservationCount"].label, "1")
        XCTAssertEqual(app.staticTexts["coinRelease.balance.free"].label, "1")
        XCTAssertEqual(app.staticTexts["coinRelease.balance.purchased"].label, "3")
    }
}
