import XCTest

/// Simulator contract for US4 monthly allowance presentation and fixture seams.
/// T082–T088 connect the month-aware model, copy, app lifecycle, and Shield behavior.
final class UserStory4MonthlyAllowanceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testCoinStoreSeparatesBalancesAndExplainsMonthlyReset() {
        let app = launchCoinStore(
            storeID: #function,
            now: "2026-08-24T07:00:00Z",
            resetStore: true
        )
        openCoinStore(in: app)

        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].label, "1")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "3")
        XCTAssertEqual(
            app.staticTexts["coinStore.monthly.title"].label,
            "이번 달 무료 해제권"
        )
        XCTAssertTrue(
            app.staticTexts["coinStore.monthly.nonRollover"].label.contains("이월되지")
        )
        XCTAssertTrue(
            app.staticTexts["coinStore.monthly.nextRefresh"].label.contains("서울")
        )
    }

    @MainActor
    func testShieldSingleButtonSpendsMonthlyFreeBeforePurchased() {
        let app = launchRelease(storeID: #function)
        let open = app.buttons["restrictionProbe.selectedApplication.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()

        let shield = app.otherElements["restrictionProbe.shield"]
        XCTAssertTrue(shield.waitForExistence(timeout: 2))
        let release = shield.buttons["restrictionProbe.shield.release"]
        XCTAssertEqual(
            shield.buttons.matching(identifier: "restrictionProbe.shield.release").count,
            1
        )
        XCTAssertTrue(shield.staticTexts["restrictionProbe.shield.cost"].label.contains("무료"))
        XCTAssertTrue(shield.staticTexts["restrictionProbe.shield.cost"].label.contains("우선"))
        XCTAssertFalse(shield.buttons["coinRelease.chooseFundingSource"].exists)

        release.tap()

        let committed = app.staticTexts["coinRelease.test.committedCount"]
        let completed = expectation(
            for: NSPredicate(format: "label == '1'"),
            evaluatedWith: committed
        )
        wait(for: [completed], timeout: 5)
        XCTAssertEqual(app.staticTexts["coinRelease.balance.free"].label, "1")
        XCTAssertEqual(app.staticTexts["coinRelease.balance.purchased"].label, "3")
    }

    @MainActor
    func testFirstForegroundAfterSeoulMonthBoundaryRefreshesOnlyFreeBalance() {
        let storeID = #function
        var app = launchCoinStore(
            storeID: storeID,
            now: "2026-08-31T14:59:59Z",
            resetStore: true
        )
        openCoinStore(in: app)

        XCTAssertEqual(app.staticTexts["coinStore.monthly.month"].label, "2026년 8월")
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].label, "1")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "3")

        app.terminate()
        app = launchCoinStore(
            storeID: storeID,
            now: "2026-08-31T15:00:00Z",
            resetStore: false
        )
        openCoinStore(in: app)

        XCTAssertEqual(app.staticTexts["coinStore.monthly.month"].label, "2026년 9월")
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].label, "2")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "3")
        XCTAssertTrue(
            app.staticTexts["coinStore.monthly.nonRollover"].label.contains("이월되지")
        )
    }

    @MainActor
    func testHistorySeparatesMonthlyLifecycleFromPurchasedCoinChanges() {
        let app = launchCoinStore(
            storeID: #function,
            now: "2026-08-24T07:00:00Z",
            resetStore: true,
            historyFixture: "full-ledger-events"
        )
        openCoinStore(in: app)
        app.buttons["coinStore.history.open"].tap()

        let monthlyGrant = app.otherElements["coinStore.history.freeGrant"]
        XCTAssertTrue(monthlyGrant.waitForExistence(timeout: 2))
        XCTAssertEqual(
            monthlyGrant.staticTexts["coinStore.history.status"].label,
            "월간 무료 지급"
        )
        XCTAssertTrue(
            monthlyGrant.staticTexts["coinStore.history.monthEnd"].label.contains("월 종료")
        )
        XCTAssertEqual(
            app.otherElements["coinStore.history.spend"]
                .staticTexts["coinStore.history.status"].label,
            "월간 무료 사용"
        )
        XCTAssertEqual(
            app.otherElements["coinStore.history.purchaseGrant"]
                .staticTexts["coinStore.history.status"].label,
            "구매 코인 지급"
        )
        XCTAssertEqual(
            app.otherElements["coinStore.history.refundAdjustment"]
                .staticTexts["coinStore.history.status"].label,
            "구매 코인 환불 보정"
        )
    }

    @MainActor
    private func launchCoinStore(
        storeID: String,
        now: String,
        resetStore: Bool,
        historyFixture: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-test-store-id", storeID,
            "--ui-test-scenario", "coin-store",
            "--ui-test-coin-ledger-state", "current",
            "--ui-test-monthly-allowance", "persisted-one-remaining",
            "--ui-test-now", now,
            "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR",
        ]
        if resetStore {
            app.launchArguments.append("--ui-test-reset-store")
        }
        if let historyFixture {
            app.launchArguments += ["--ui-test-coin-history", historyFixture]
        }
        app.launch()
        return app
    }

    @MainActor
    private func launchRelease(storeID: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-test-store-id", storeID, "--ui-test-reset-store",
            "--ui-test-scenario", "restriction-activation",
            "--ui-test-now", "2026-08-24T07:00:00Z",
            "--ui-test-location-state", "inside",
            "--ui-test-coin-release", "overlapping",
            "--ui-test-coin-release-result", "success",
            "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR",
        ]
        app.launch()
        return app
    }

    @MainActor
    private func openCoinStore(in app: XCUIApplication) {
        let open = app.buttons["coinStore.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.otherElements["coinStore.screen"].waitForExistence(timeout: 2))
    }
}
