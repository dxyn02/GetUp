import XCTest

final class UserStory4PermissionGuidanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testPermissionOverviewDistinguishesEveryRequiredCapability() {
        let app = launchApp(scenario: "permission-overview")

        assertPermissionScreen(
            titled: "원활한 사용을 위해 아래 권한이 필요해요",
            in: app
        )
        XCTAssertTrue(app.otherElements["permissionGuide.permissionList"].exists)
        assertElement(containing: "🛡️ 앱 사용 제한", in: app)
        assertElement(containing: "📍 위치 접근", in: app)
        assertElement(containing: "🎯 정확한 위치", in: app)
        assertElement(containing: "🔄 Background App Refresh", in: app)
        XCTAssertTrue(app.buttons["permissionGuide.next"].exists)
    }

    @MainActor
    func testApprovedRecoverySkipsTheOnboardingPermissionGuide() {
        let app = launchApp(scenario: "permission-runtime-approved")

        XCTAssertTrue(app.buttons["home.createRule"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.otherElements["permissionGuide.screen"].exists)
    }

    @MainActor
    func testUndeterminedFamilyControlsShowsDisabledNextDuringSystemRequest() {
        let app = launchApp(scenario: "permission-family-controls-undetermined")

        assertPermissionScreen(titled: "앱 사용 제한 권한이 필요해요", in: app)
        let next = app.buttons["permissionGuide.next"]
        XCTAssertTrue(next.exists)
        XCTAssertFalse(next.isEnabled)
        XCTAssertFalse(app.buttons["permissionGuide.openSettings"].exists)
    }

    @MainActor
    func testApprovedFamilyControlsShowsEnabledNext() {
        let app = launchApp(scenario: "permission-family-controls-approved")

        assertPermissionScreen(titled: "앱 사용 제한 권한이 필요해요", in: app)
        let next = app.buttons["permissionGuide.next"]
        XCTAssertTrue(next.exists)
        XCTAssertTrue(next.isEnabled)
    }

    @MainActor
    func testDeniedFamilyControlsShowsSettingsRecovery() {
        let app = launchApp(scenario: "permission-family-controls-denied")

        assertPermissionScreen(titled: "앱 사용 제한 권한이 필요해요", in: app)
        XCTAssertFalse(app.staticTexts["원활한 사용을 위해 아래 권한이 필요해요"].exists)
        XCTAssertTrue(app.buttons["permissionGuide.openSettings"].exists)
        XCTAssertFalse(app.buttons["permissionGuide.next"].exists)
    }

    @MainActor
    func testUndeterminedLocationShowsDisabledNextDuringSystemRequest() {
        let app = launchApp(scenario: "permission-location-undetermined")

        assertPermissionScreen(titled: "정확한 위치 접근 권한이 필요해요", in: app)
        let next = app.buttons["permissionGuide.next"]
        XCTAssertTrue(next.exists)
        XCTAssertFalse(next.isEnabled)
        XCTAssertFalse(app.buttons["permissionGuide.openSettings"].exists)
    }

    @MainActor
    func testApprovedLocationShowsEnabledNext() {
        let app = launchApp(scenario: "permission-location-approved")

        assertPermissionScreen(titled: "정확한 위치 접근 권한이 필요해요", in: app)
        let next = app.buttons["permissionGuide.next"]
        XCTAssertTrue(next.exists)
        XCTAssertTrue(next.isEnabled)
    }

    @MainActor
    func testDeniedLocationExplainsBothSettingsAndRecoveryActions() {
        let app = launchApp(scenario: "permission-location-denied")

        assertPermissionScreen(titled: "정확한 위치 접근 권한이 필요해요", in: app)
        XCTAssertFalse(app.staticTexts["원활한 사용을 위해 아래 권한이 필요해요"].exists)
        assertElement(containing: "항상 허용", in: app)
        assertElement(containing: "정확한 위치", in: app)
        XCTAssertTrue(app.buttons["permissionGuide.later"].exists)
        XCTAssertTrue(app.buttons["permissionGuide.openSettings"].exists)
    }

    @MainActor
    func testApprovedBackgroundRefreshShowsEnabledNext() {
        let app = launchApp(scenario: "permission-background-refresh-approved")

        assertPermissionScreen(
            titled: "백그라운드 새로 고침을 확인해 주세요",
            in: app
        )
        let next = app.buttons["permissionGuide.next"]
        XCTAssertTrue(next.exists)
        XCTAssertTrue(next.isEnabled)
    }

    @MainActor
    func testDeniedBackgroundRefreshExplainsDelayedRestoration() {
        let app = launchApp(scenario: "permission-background-refresh-denied")

        assertPermissionScreen(
            titled: "백그라운드 새로 고침을 확인해 주세요",
            in: app
        )
        assertElement(containing: "복구가 늦어질", in: app)
        assertElement(containing: "저전력 모드", in: app)
        XCTAssertTrue(app.buttons["permissionGuide.later"].exists)
        XCTAssertFalse(app.buttons["permissionGuide.openSettings"].exists)
    }

    @MainActor
    func testRetryingUnavailableLocationReturnsToAnInactiveRule() {
        let app = launchApp(
            scenario: "location-unavailable-inactive",
            locationRetryResult: "outside"
        )

        assertPermissionScreen(titled: "현재 위치를 확인할 수 없어요", in: app)
        assertElement(containing: "새 제한을 시작하지 않", in: app)
        assertLocationRecoveryActions(in: app)

        app.buttons["permissionGuide.retryLocation"].tap()

        XCTAssertTrue(
            app.staticTexts["restrictionStatus.inactive"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.otherElements["permissionGuide.screen"]
                .waitForNonExistence(timeout: 2)
        )
    }

    @MainActor
    func testRetryingUnavailableLocationReturnsToThePreservedActiveRule() {
        let app = launchApp(
            scenario: "location-unavailable-active",
            locationRetryResult: "inside"
        )

        assertPermissionScreen(
            titled: "위치를 확인할 수 없어 제한이 유지돼요",
            in: app
        )
        assertElement(containing: "제한을 유지", in: app)
        assertElement(containing: "시간", in: app)
        assertLocationRecoveryActions(in: app)

        app.buttons["permissionGuide.retryLocation"].tap()

        XCTAssertTrue(
            app.staticTexts["restrictionStatus.active"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.otherElements["permissionGuide.screen"]
                .waitForNonExistence(timeout: 2)
        )
    }

    @MainActor
    private func launchApp(
        scenario: String,
        locationRetryResult: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-test-store-id", #function,
            "--ui-test-reset-store",
            "--ui-test-scenario", scenario,
        ]
        if let locationRetryResult {
            app.launchArguments += [
                "--ui-test-location-retry-result", locationRetryResult,
            ]
        }
        app.launch()
        return app
    }

    @MainActor
    private func assertPermissionScreen(
        titled title: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.otherElements["permissionGuide.screen"]
                .waitForExistence(timeout: 2),
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.staticTexts[title].exists,
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertLocationRecoveryActions(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            app.buttons["permissionGuide.retryLocation"].exists,
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.buttons["permissionGuide.openSettings"].exists,
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertElement(
        containing label: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "label CONTAINS %@", label)
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(predicate)
                .firstMatch
                .exists,
            "\(label)을 포함한 안내가 필요합니다.",
            file: file,
            line: line
        )
    }
}
