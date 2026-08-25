import XCTest

final class AccessibilityUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRuleEditorKeepsCoreControlsReachableAtLargestDynamicTypeSize() {
        let app = launchApp(
            scenario: "valid-rule-draft",
            accessibilityArguments: Self.maximumDynamicTypeArguments
        )

        let startTime = app.buttons["ruleEditor.startTime"]
        XCTAssertTrue(startTime.waitForExistence(timeout: 3))
        XCTAssertEqual(startTime.label, "시작 시간")
        XCTAssertEqual(startTime.value as? String, "06:00 AM")
        assertMinimumTouchTarget(startTime)

        let endTime = app.buttons["ruleEditor.endTime"]
        XCTAssertEqual(endTime.label, "종료 시간")
        XCTAssertEqual(endTime.value as? String, "09:00 AM")
        assertMinimumTouchTarget(endTime)

        let save = app.buttons["ruleEditor.save"]
        XCTAssertTrue(save.exists)
        XCTAssertTrue(save.isEnabled)
        XCTAssertTrue(save.isHittable)
        assertMinimumTouchTarget(save)
    }

    @MainActor
    func testPermissionRecoveryKeepsContentAndActionsAtLargestDynamicTypeSize() {
        let app = launchApp(
            scenario: "permission-location-denied",
            accessibilityArguments: Self.maximumDynamicTypeArguments
        )

        XCTAssertTrue(
            app.staticTexts["정확한 위치 접근 권한이 필요해요"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.otherElements["permissionGuide.screen"].exists)
        XCTAssertTrue(app.staticTexts["LOCATION ACCESS"].exists)

        let later = app.buttons["permissionGuide.later"]
        let settings = app.buttons["permissionGuide.openSettings"]
        XCTAssertTrue(later.exists)
        XCTAssertTrue(settings.exists)
        XCTAssertTrue(later.isHittable)
        XCTAssertTrue(settings.isHittable)
        assertMinimumTouchTarget(later)
        assertMinimumTouchTarget(settings)
    }

    @MainActor
    func testActiveRestrictionExposesColorIndependentVoiceOverSemanticsInReadingOrder() {
        let app = launchActiveRestriction()

        let status = app.staticTexts["restrictionStatus.active"]
        let title = app.staticTexts["출근 준비"]
        let time = app.staticTexts["06:00 AM → 09:00 AM"]
        let location = app.staticTexts["home.ruleCard.rule-1.location"]
        let applications = app.staticTexts["home.ruleCard.rule-1.applications"]
        let guardedEdit = app.buttons["restrictionStatus.editDisabled"]

        XCTAssertTrue(status.waitForExistence(timeout: 3))
        XCTAssertEqual(status.label, "RESTRICTION ACTIVE")
        XCTAssertEqual(location.label, "집 · 1km")
        XCTAssertEqual(applications.label, "1개 앱")
        XCTAssertEqual(guardedEdit.label, "조건 종료 후 수정 가능")
        XCTAssertTrue(title.exists)
        XCTAssertTrue(time.exists)

        assertVerticalReadingOrder([
            status,
            title,
            time,
            location,
            applications,
            guardedEdit,
        ])

        guardedEdit.tap()
        let alert = app.alerts["제한 중에는 수정할 수 없어요"]
        XCTAssertTrue(alert.waitForExistence(timeout: 2))
        XCTAssertTrue(
            alert.staticTexts[
                "집 1km 밖으로 이동하거나 09:00 AM이 지나면 규칙을 수정·끄기·삭제할 수 있어요."
            ].exists
        )
        XCTAssertTrue(alert.buttons["확인"].isHittable)
    }

    @MainActor
    func testReduceMotionKeepsRestrictionAndShieldActionsEquivalent() {
        let app = launchActiveRestriction(
            accessibilityArguments: [
                "-UIAccessibilityReduceMotionEnabled", "YES",
            ]
        )

        XCTAssertTrue(
            app.staticTexts["restrictionStatus.active"]
                .waitForExistence(timeout: 3)
        )

        let openSelectedApplication =
            app.buttons["restrictionProbe.selectedApplication.open"]
        XCTAssertTrue(openSelectedApplication.isHittable)
        openSelectedApplication.tap()

        let shield = app.otherElements["restrictionProbe.shield"]
        XCTAssertTrue(shield.waitForExistence(timeout: 2))

        let close = app.buttons["restrictionProbe.shield.close"]
        XCTAssertEqual(close.label, "앱 닫기")
        XCTAssertTrue(close.isHittable)
        assertMinimumTouchTarget(close)
        close.tap()

        XCTAssertTrue(shield.waitForNonExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["restrictionStatus.active"].exists)
    }

    @MainActor
    func testIncreasedContrastAndDifferentiateWithoutColorKeepExplicitLocationState() {
        let app = launchApp(
            scenario: "location-unavailable-active",
            accessibilityArguments: [
                "-UIAccessibilityDarkerSystemColorsEnabled", "YES",
                "-UIAccessibilityDifferentiateWithoutColor", "YES",
            ]
        )

        XCTAssertTrue(
            app.staticTexts["위치를 확인할 수 없어 제한이 유지돼요"]
                .waitForExistence(timeout: 3)
        )
        XCTAssertTrue(app.staticTexts["LOCATION UNAVAILABLE"].exists)
        XCTAssertTrue(app.staticTexts["현재 상태 · 제한 활성 유지"].exists)
        XCTAssertTrue(app.staticTexts["위치 오류만으로 제한을 해제하지 않아요."].exists)
        XCTAssertTrue(app.buttons["permissionGuide.retryLocation"].isHittable)
        XCTAssertTrue(app.buttons["permissionGuide.openSettings"].isHittable)
    }

    @MainActor
    private func launchActiveRestriction(
        accessibilityArguments: [String] = []
    ) -> XCUIApplication {
        launchApp(
            scenario: "restriction-activation",
            additionalArguments: [
                "--ui-test-now", "2026-08-24T07:00:00Z",
                "--ui-test-location-state", "inside",
            ],
            accessibilityArguments: accessibilityArguments
        )
    }

    @MainActor
    private func launchApp(
        scenario: String,
        additionalArguments: [String] = [],
        accessibilityArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-test-store-id", #function,
            "--ui-test-reset-store",
            "--ui-test-scenario", scenario,
        ] + additionalArguments + accessibilityArguments
        app.launch()
        return app
    }

    @MainActor
    private func assertMinimumTouchTarget(
        _ element: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let frame = element.frame
        XCTAssertGreaterThanOrEqual(frame.width, 44, file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.height, 44, file: file, line: line)
    }

    @MainActor
    private func assertVerticalReadingOrder(
        _ elements: [XCUIElement],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for (earlier, later) in zip(elements, elements.dropFirst()) {
            let earlierFrame = earlier.frame
            let laterFrame = later.frame
            let earlierIdentifier = earlier.identifier
            let laterIdentifier = later.identifier
            XCTAssertLessThan(
                earlierFrame.minY,
                laterFrame.minY,
                "\(earlierIdentifier) must appear before \(laterIdentifier).",
                file: file,
                line: line
            )
        }
    }

    private static let maximumDynamicTypeArguments = [
        "-UIPreferredContentSizeCategoryName",
        "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
    ]
}
