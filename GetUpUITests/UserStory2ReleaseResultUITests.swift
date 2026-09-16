import XCTest

/// Simulator contract for the T105-approved release handoff surfaces.
/// Production wiring and localized accessibility behavior arrive in T111–T112.
final class UserStory2ReleaseResultUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testProcessingShowsMaintainedRestrictionAndNoActions() {
        let app = launchApp(state: "processing")
        let screen = app.scrollViews["releaseHandoff.processing.screen"]

        XCTAssertTrue(screen.waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertEqual(app.staticTexts["releaseHandoff.statusTitle"].label, "해제 상태를 확인하고 있어요")
        XCTAssertTrue(app.activityIndicators["releaseHandoff.processing.progress"].exists)
        XCTAssertTrue(app.staticTexts["releaseHandoff.restrictionMaintained"].label.contains("제한은 유지"))
        XCTAssertTrue(app.staticTexts["releaseHandoff.resumeMessage"].label.contains("다음 실행"))
        XCTAssertFalse(app.buttons["releaseHandoff.primaryAction"].exists)
        XCTAssertFalse(app.buttons["releaseHandoff.secondaryAction"].exists)
    }

    @MainActor
    func testCompletedShowsConfirmedResultAndSingleAcknowledgeAction() {
        let app = launchApp(state: "completed")

        XCTAssertTrue(app.otherElements["releaseHandoff.completed.screen"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["releaseHandoff.statusTitle"].label, "해제가 완료됐어요")
        XCTAssertTrue(app.images["releaseHandoff.completed.icon"].exists)
        XCTAssertTrue(app.staticTexts["releaseHandoff.fundingResult"].label.contains("무료 해제권 1회"))
        XCTAssertTrue(app.staticTexts["releaseHandoff.remainingRestrictions"].label.contains("다른 규칙 1개"))
        XCTAssertEqual(app.buttons["releaseHandoff.primaryAction"].label, "확인")
        XCTAssertFalse(app.buttons["releaseHandoff.secondaryAction"].exists)
    }

    @MainActor
    func testRetryableShowsNoChargeAndSameCommandRetry() {
        let app = launchApp(state: "retryable")

        XCTAssertTrue(app.otherElements["releaseHandoff.retryable.screen"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["releaseHandoff.statusTitle"].label, "해제를 완료하지 못했어요")
        XCTAssertTrue(app.staticTexts["releaseHandoff.fundingResult"].label.contains("차감되지 않았어요"))
        XCTAssertTrue(app.staticTexts["releaseHandoff.restrictionMaintained"].label.contains("제한은 유지"))
        XCTAssertEqual(app.buttons["releaseHandoff.primaryAction"].label, "다시 시도")
        XCTAssertEqual(app.buttons["releaseHandoff.secondaryAction"].label, "닫기")
    }

    @MainActor
    func testRetryAfterDisablesRetryUntilDeadline() {
        let app = launchApp(state: "retryable-waiting")
        let retry = app.buttons["releaseHandoff.primaryAction"]

        XCTAssertTrue(app.otherElements["releaseHandoff.retryable.screen"].waitForExistence(timeout: 5))
        XCTAssertTrue(retry.exists)
        XCTAssertFalse(retry.isEnabled)
        XCTAssertEqual(retry.label, "30초 뒤 다시 시도")
        XCTAssertTrue(app.buttons["releaseHandoff.secondaryAction"].isEnabled)
    }

    @MainActor
    func testInsufficientUsesXAndOffersCoinPurchase() {
        let app = launchApp(state: "insufficient")

        XCTAssertTrue(app.otherElements["releaseHandoff.insufficient.screen"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["releaseHandoff.statusTitle"].label, "사용할 수 있는 해제권이 없어요")
        XCTAssertEqual(app.images["releaseHandoff.insufficient.icon"].label, "사용할 수 없음")
        XCTAssertEqual(app.staticTexts["releaseHandoff.balance.free"].label, "0회")
        XCTAssertEqual(app.staticTexts["releaseHandoff.balance.purchased"].label, "0개")
        XCTAssertEqual(app.buttons["releaseHandoff.primaryAction"].label, "코인 구매")
        XCTAssertEqual(app.buttons["releaseHandoff.secondaryAction"].label, "닫기")
    }

    @MainActor
    func testInsufficientPurchaseActionOpensStoreWithoutStartingAnotherRelease() {
        let app = launchApp(state: "insufficient")

        let purchase = app.buttons["releaseHandoff.primaryAction"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 5))
        purchase.tap()

        XCTAssertTrue(
            app.otherElements["coinStore.screen"].waitForExistence(timeout: 5),
            app.debugDescription
        )
        XCTAssertTrue(app.staticTexts["coinStore.releaseHandoffNotice"].exists)
        XCTAssertFalse(app.buttons["releaseHandoff.primaryAction"].exists)
    }

    @MainActor
    func testRecoveryRequiredReusesExistingRecoverySurfaceWithoutPurchase() {
        let app = launchApp(state: "recovery-required")

        XCTAssertTrue(
            app.otherElements["coinRelease.destination.iCloudRecovery"].waitForExistence(timeout: 5),
            app.debugDescription
        )
        XCTAssertFalse(app.otherElements["releaseHandoff.recoveryRequired.screen"].exists)
        XCTAssertFalse(app.buttons["releaseHandoff.primaryAction"].exists)
        XCTAssertFalse(app.buttons["coinStore.product.1.purchase"].exists)
    }

    @MainActor
    private func launchApp(state: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-test-store-id", #function, "--ui-test-reset-store",
            "--ui-test-scenario", "restriction-activation",
            "--ui-test-now", "2026-08-24T07:00:00Z",
            "--ui-test-location-state", "inside",
            "--ui-test-release-handoff", state,
            "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR",
        ]
        app.launch()
        return app
    }
}
