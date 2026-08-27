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
        XCTAssertFalse(app.staticTexts["permissionGuide.title"].exists)
    }

    @MainActor
    func testInterruptedPermissionOnboardingReturnsAfterAppRelaunch() {
        let storeID = "permissionOnboardingPersistence"
        let firstLaunch = launchApp(
            scenario: "permission-onboarding-persistence",
            storeID: storeID,
            resetsStore: true
        )

        assertPermissionScreen(
            titled: "원활한 사용을 위해 아래 권한이 필요해요",
            in: firstLaunch
        )
        firstLaunch.terminate()

        let secondLaunch = launchApp(
            scenario: "permission-onboarding-persistence",
            storeID: storeID,
            resetsStore: false
        )

        assertPermissionScreen(
            titled: "원활한 사용을 위해 아래 권한이 필요해요",
            in: secondLaunch
        )
        XCTAssertFalse(secondLaunch.buttons["home.createRule"].exists)
    }

    @MainActor
    func testStartingFromTheFinalPageCompletesOnboardingAcrossRelaunch() {
        let storeID = "permissionOnboardingCompletion"
        let firstLaunch = launchApp(
            scenario: "permission-onboarding-completion",
            storeID: storeID,
            resetsStore: true
        )

        assertPermissionScreen(
            titled: "백그라운드 새로 고침을 확인해 주세요",
            in: firstLaunch
        )
        let start = firstLaunch.buttons["permissionGuide.completeOnboarding"]
        XCTAssertTrue(start.exists)
        XCTAssertEqual(start.label, "시작하기")
        start.tap()
        XCTAssertTrue(firstLaunch.buttons["home.createRule"].waitForExistence(timeout: 2))
        firstLaunch.terminate()

        let secondLaunch = launchApp(
            scenario: "permission-onboarding-completion",
            storeID: storeID,
            resetsStore: false
        )

        XCTAssertTrue(secondLaunch.buttons["home.createRule"].waitForExistence(timeout: 2))
        XCTAssertFalse(secondLaunch.staticTexts["permissionGuide.title"].exists)
    }

    @MainActor
    func testUndeterminedFamilyControlsWaitsForExplicitMockupTap() {
        let app = launchApp(scenario: "permission-family-controls-undetermined")

        assertPermissionScreen(titled: "앱 사용 제한 권한이 필요해요", in: app)
        let request = app.buttons["permissionGuide.requestFamilyControlsAuthorization"]
        XCTAssertTrue(request.exists)
        XCTAssertTrue(request.isHittable)
        XCTAssertFalse(app.buttons["permissionGuide.next"].exists)
        XCTAssertFalse(app.buttons["permissionGuide.openSettings"].exists)
        XCTAssertTrue(app.otherElements["permissionGuide.mockup.familyControls"].exists)
        XCTAssertEqual(
            app.staticTexts["permissionGuide.mockup.familyControlsTitle"].label,
            "“나서”가 화면 사용 시간에\n접근하도록 허용할까요?"
        )
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
    func testGrantingFamilyControlsDuringOnboardingAdvancesToLocation() {
        let app = launchApp(scenario: "permission-family-controls-grant-onboarding")

        app.buttons["permissionGuide.requestFamilyControlsAuthorization"].tap()

        assertPermissionScreen(titled: "정확한 위치 접근 권한이 필요해요", in: app)
    }

    @MainActor
    func testDenyingFamilyControlsChangesTheNextPrimaryActionToSettings() {
        let app = launchApp(scenario: "permission-family-controls-deny-onboarding")

        app.buttons["permissionGuide.requestFamilyControlsAuthorization"].tap()

        XCTAssertTrue(
            app.buttons["permissionGuide.openSettings"].waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.buttons["permissionGuide.requestFamilyControlsAuthorization"].exists)
    }

    @MainActor
    func testUndeterminedLocationWaitsForExplicitMockupTap() {
        let app = launchApp(scenario: "permission-location-undetermined")

        assertPermissionScreen(titled: "정확한 위치 접근 권한이 필요해요", in: app)
        let request = app.buttons["permissionGuide.requestLocationAuthorization"]
        XCTAssertTrue(request.exists)
        XCTAssertTrue(request.isHittable)
        XCTAssertFalse(app.buttons["permissionGuide.next"].exists)
        XCTAssertFalse(app.buttons["permissionGuide.openSettings"].exists)
        XCTAssertTrue(app.otherElements["permissionGuide.mockup.locationPrompt"].exists)
    }

    @MainActor
    func testWhenInUseLocationShowsExplicitAlwaysUpgradeTap() {
        let app = launchApp(scenario: "permission-location-when-in-use")

        assertPermissionScreen(titled: "항상 위치 접근 권한이 필요해요", in: app)
        let request = app.buttons["permissionGuide.requestAlwaysLocationAuthorization"]
        XCTAssertTrue(request.exists)
        XCTAssertTrue(request.isHittable)
        XCTAssertTrue(app.otherElements["permissionGuide.mockup.locationAlwaysPrompt"].exists)
        XCTAssertFalse(app.buttons["permissionGuide.openSettings"].exists)
    }

    @MainActor
    func testRepairingAlwaysLocationDuringNormalUseClosesTheGuide() {
        let app = launchApp(scenario: "permission-location-always-grant-recovery")

        app.buttons["permissionGuide.requestAlwaysLocationAuthorization"].tap()

        XCTAssertTrue(app.buttons["home.createRule"].waitForExistence(timeout: 2))
        XCTAssertFalse(app.staticTexts["permissionGuide.title"].exists)
    }

    @MainActor
    func testDecliningAlwaysUpgradeChangesTheNextPrimaryActionToSettings() {
        let app = launchApp(scenario: "permission-location-always-decline-onboarding")

        app.buttons["permissionGuide.requestAlwaysLocationAuthorization"].tap()

        XCTAssertTrue(
            app.buttons["permissionGuide.openSettings"].waitForExistence(timeout: 2)
        )
        XCTAssertTrue(
            app.staticTexts[
                "‘한 번만 허용’을 선택했거나 ‘항상 허용’으로 변경하지 않았다면, 설정에서 위치 접근을 ‘항상’으로 바꿔 주세요."
            ].exists
        )
        XCTAssertFalse(app.buttons["permissionGuide.requestAlwaysLocationAuthorization"].exists)
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
        XCTAssertTrue(app.otherElements["permissionGuide.mockup.locationSettings"].exists)
        XCTAssertTrue(app.staticTexts["permissionGuide.location.alwaysInstruction"].exists)
        XCTAssertTrue(app.staticTexts["permissionGuide.location.accuracyInstruction"].exists)
        XCTAssertFalse(app.buttons["permissionGuide.confirm"].exists)
        XCTAssertTrue(app.buttons["permissionGuide.openSettings"].exists)
    }

    @MainActor
    func testApprovedBackgroundRefreshShowsEnabledStart() {
        let app = launchApp(scenario: "permission-background-refresh-approved")

        assertPermissionScreen(
            titled: "백그라운드 새로 고침을 확인해 주세요",
            in: app
        )
        let start = app.buttons["permissionGuide.completeOnboarding"]
        XCTAssertTrue(start.exists)
        XCTAssertTrue(start.isEnabled)
        XCTAssertEqual(start.label, "시작하기")
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
        XCTAssertTrue(app.otherElements["permissionGuide.mockup.backgroundRefresh"].exists)
        let start = app.buttons["permissionGuide.completeOnboarding"]
        XCTAssertTrue(start.exists)
        XCTAssertEqual(start.label, "시작하기")
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
            app.staticTexts["permissionGuide.title"]
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
            app.staticTexts["permissionGuide.title"]
                .waitForNonExistence(timeout: 2)
        )
    }

    @MainActor
    private func launchApp(
        scenario: String,
        locationRetryResult: String? = nil,
        storeID: String = #function,
        resetsStore: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-test-store-id", storeID,
            "--ui-test-scenario", scenario,
        ]
        if resetsStore {
            app.launchArguments.append("--ui-test-reset-store")
        }
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
            app.staticTexts["permissionGuide.title"].waitForExistence(timeout: 2),
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.staticTexts["permissionGuide.title"].label,
            title,
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
