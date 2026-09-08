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

        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].value as? String, "1회")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].value as? String, "3개")
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
        XCTAssertEqual(
            app.staticTexts["coinRelease.test.createsMonthlyAllowanceOnRequest"].label,
            "true"
        )

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
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].value as? String, "1회")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].value as? String, "3개")

        app.terminate()
        app = launchCoinStore(
            storeID: storeID,
            now: "2026-08-31T15:00:00Z",
            resetStore: false,
            monthlyAllowance: "first-app"
        )
        openCoinStore(in: app)

        XCTAssertEqual(app.staticTexts["coinStore.monthly.month"].label, "2026년 9월")
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].value as? String, "2회")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].value as? String, "3개")
        XCTAssertTrue(
            app.staticTexts["coinStore.monthly.nonRollover"].label.contains("이월되지")
        )
    }

    @MainActor
    func testFirstSetupAndDeletionResetUseDistinctMonthlyFixtures() {
        var app = launchCoinStore(
            storeID: "\(#function).setup",
            now: "2026-08-24T07:00:00Z",
            resetStore: true,
            ledgerState: "setup-required",
            monthlyAllowance: "first-setup"
        )
        openCoinStore(in: app)
        app.buttons["coinStore.setup.confirm"].tap()

        XCTAssertTrue(app.otherElements["coinStore.catalog"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].value as? String, "2회")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].value as? String, "0개")
        XCTAssertEqual(app.staticTexts["coinStore.test.setupCount"].label, "1")

        app.terminate()
        app = launchCoinStore(
            storeID: "\(#function).reset",
            now: "2026-08-24T07:00:00Z",
            resetStore: true,
            ledgerState: "deletion-confirmed",
            monthlyAllowance: "deletion-reset"
        )
        openCoinStore(in: app)
        app.buttons["coinStore.reset.requestConfirmation"].tap()

        let dialog = app.alerts["새 장부를 시작할까요?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 2))
        dialog.buttons["새 장부 시작"].tap()

        XCTAssertTrue(app.otherElements["coinStore.catalog"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].value as? String, "0회")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].value as? String, "0개")
        XCTAssertEqual(app.staticTexts["coinStore.test.resetCount"].label, "1")
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

        XCTAssertTrue(
            app.descendants(matching: .any)["coinStore.history.current"]
                .waitForExistence(timeout: 2)
        )
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
    func testBalancesExposeLoadingEmptyStaleAndCurrentVoiceOverStates() {
        assertBalanceState(
            ledgerState: "syncing",
            free: 1,
            purchased: 3,
            expectedState: "잔액을 확인하는 중이에요",
            expectedFreeValue: "확인 중",
            expectedPurchasedValue: "확인 중"
        )
        assertBalanceState(
            ledgerState: "current",
            free: 0,
            purchased: 0,
            expectedState: "사용 가능한 해제권이 없어요",
            expectedFreeValue: "0회",
            expectedPurchasedValue: "0개"
        )
        assertBalanceState(
            ledgerState: "stale",
            free: 1,
            purchased: 3,
            expectedState: "마지막으로 확인한 잔액이에요",
            expectedFreeValue: "1회",
            expectedPurchasedValue: "3개"
        )
        assertBalanceState(
            ledgerState: "current",
            free: 1,
            purchased: 3,
            expectedState: "최신 잔액이에요",
            expectedFreeValue: "1회",
            expectedPurchasedValue: "3개"
        )
    }

    @MainActor
    func testHistoryDistinguishesLoadingEmptyAndStaleLedgerStates() {
        var app = launchCoinStore(
            storeID: "\(#function).loading",
            now: "2026-08-24T07:00:00Z",
            resetStore: true,
            ledgerState: "syncing"
        )
        openCoinStore(in: app)
        app.buttons["coinStore.history.open"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["coinStore.history.loading"]
                .waitForExistence(timeout: 2)
        )

        app.terminate()
        app = launchCoinStore(
            storeID: "\(#function).empty",
            now: "2026-08-24T07:00:00Z",
            resetStore: true,
            freeBalance: 0,
            purchasedBalance: 0
        )
        openCoinStore(in: app)
        app.buttons["coinStore.history.open"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["coinStore.history.empty"]
                .waitForExistence(timeout: 2)
        )

        app.terminate()
        app = launchCoinStore(
            storeID: "\(#function).stale",
            now: "2026-08-24T07:00:00Z",
            resetStore: true,
            ledgerState: "stale",
            historyFixture: "full-ledger-events"
        )
        openCoinStore(in: app)
        app.buttons["coinStore.history.open"].tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["coinStore.history.stale"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertTrue(app.otherElements["coinStore.history.freeGrant"].exists)
    }

    @MainActor
    private func launchCoinStore(
        storeID: String,
        now: String,
        resetStore: Bool,
        ledgerState: String = "current",
        monthlyAllowance: String = "persisted-one-remaining",
        freeBalance: Int? = nil,
        purchasedBalance: Int? = nil,
        historyFixture: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-test-store-id", storeID,
            "--ui-test-scenario", "coin-store",
            "--ui-test-coin-ledger-state", ledgerState,
            "--ui-test-monthly-allowance", monthlyAllowance,
            "--ui-test-now", now,
            "-AppleLanguages", "(ko)", "-AppleLocale", "ko_KR",
        ]
        if resetStore {
            app.launchArguments.append("--ui-test-reset-store")
        }
        if let historyFixture {
            app.launchArguments += ["--ui-test-coin-history", historyFixture]
        }
        if let freeBalance {
            app.launchArguments += ["--ui-test-free-balance", String(freeBalance)]
        }
        if let purchasedBalance {
            app.launchArguments += ["--ui-test-purchased-balance", String(purchasedBalance)]
        }
        app.launch()
        return app
    }

    @MainActor
    private func assertBalanceState(
        ledgerState: String,
        free: Int,
        purchased: Int,
        expectedState: String,
        expectedFreeValue: String,
        expectedPurchasedValue: String
    ) {
        let app = launchCoinStore(
            storeID: "\(#function).\(ledgerState).\(free).\(purchased)",
            now: "2026-08-24T07:00:00Z",
            resetStore: true,
            ledgerState: ledgerState,
            freeBalance: free,
            purchasedBalance: purchased
        )
        openCoinStore(in: app)

        let state = app.staticTexts["coinStore.balance.state"]
        let freeBalance = app.staticTexts["coinStore.balance.free"]
        let purchasedBalance = app.staticTexts["coinStore.balance.purchased"]
        XCTAssertEqual(state.label, expectedState)
        XCTAssertEqual(freeBalance.label, "남은 무료 해제권")
        XCTAssertEqual(freeBalance.value as? String, expectedFreeValue)
        XCTAssertEqual(purchasedBalance.label, "구매 코인 잔액")
        XCTAssertEqual(purchasedBalance.value as? String, expectedPurchasedValue)
        XCTAssertLessThan(state.frame.minY, freeBalance.frame.minY)
        XCTAssertLessThan(freeBalance.frame.minX, purchasedBalance.frame.minX)

        app.terminate()
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
            "--ui-test-monthly-allowance", "first-shield",
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
