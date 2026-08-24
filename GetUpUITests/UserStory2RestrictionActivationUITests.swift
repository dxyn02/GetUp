import XCTest

final class UserStory2RestrictionActivationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testActiveScheduleAndInsideLocationRestrictOnlyTheSelectedApplication() {
        let app = launchApp(
            now: "2026-08-24T07:00:00Z",
            locationState: "inside"
        )

        XCTAssertTrue(
            app.staticTexts["restrictionStatus.active"]
                .waitForExistence(timeout: 2)
        )

        app.buttons["restrictionProbe.selectedApplication.open"].tap()
        XCTAssertTrue(
            app.otherElements["restrictionProbe.shield"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(
            app.otherElements["restrictionProbe.selectedApplication.content"]
                .exists
        )

        app.buttons["restrictionProbe.shield.close"].tap()
        app.buttons["restrictionProbe.unselectedApplication.open"].tap()
        XCTAssertTrue(
            app.otherElements["restrictionProbe.unselectedApplication.content"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.otherElements["restrictionProbe.shield"].exists)
    }

    @MainActor
    func testInsideLocationWithoutAnActiveScheduleDoesNotRestrict() {
        let app = launchApp(
            now: "2026-08-24T10:00:00Z",
            locationState: "inside"
        )

        assertSelectedApplicationOpensWithoutRestriction(in: app)
    }

    @MainActor
    func testActiveScheduleWithoutInsideLocationDoesNotRestrict() {
        let app = launchApp(
            now: "2026-08-24T07:00:00Z",
            locationState: "outside"
        )

        assertSelectedApplicationOpensWithoutRestriction(in: app)
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
        ]
        app.launch()
        return app
    }

    @MainActor
    private func assertSelectedApplicationOpensWithoutRestriction(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.staticTexts["restrictionStatus.inactive"]
                .waitForExistence(timeout: 2),
            file: file,
            line: line
        )

        app.buttons["restrictionProbe.selectedApplication.open"].tap()
        XCTAssertTrue(
            app.otherElements["restrictionProbe.selectedApplication.content"]
                .waitForExistence(timeout: 2),
            file: file,
            line: line
        )
        XCTAssertFalse(
            app.otherElements["restrictionProbe.shield"].exists,
            file: file,
            line: line
        )
    }
}
