import XCTest

/// Simulator contract for the US3 coin store seam, not a real App Store purchase.
/// T074–T077 must connect these identifiers to the production model, views, and localized copy.
/// The fixture uses StoreKit-provided Korean prices and an injected ledger; diagnostic counters
/// observe setup, reset, and purchase actions without synthesizing a successful balance change.
final class UserStory3CoinPurchaseUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testFirstActivationExplainsRecoveryLimitsAndChangesNothingUntilConsent() {
        let app = launchApp(storeID: #function, ledgerState: "setup-required")
        openCoinStore(in: app)

        let setup = app.otherElements["coinStore.setup.disclosure"]
        XCTAssertTrue(setup.waitForExistence(timeout: 2))
        assertRecoveryLimitDisclosure(in: setup)
        XCTAssertFalse(app.otherElements["coinStore.reset.disclosure"].exists)
        XCTAssertEqual(app.staticTexts["coinStore.test.setupCount"].label, "0")
        XCTAssertTrue(app.buttons["coinStore.product.1.purchase"].exists)
        XCTAssertFalse(app.buttons["coinStore.product.1.purchase"].isEnabled)

        app.buttons["coinStore.setup.confirm"].tap()

        XCTAssertTrue(app.otherElements["coinStore.catalog"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].label, "2")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "0")
        XCTAssertEqual(app.staticTexts["coinStore.test.setupCount"].label, "1")
    }

    @MainActor
    func testConfirmedDeletionUsesSeparateResetAndStartsCurrentMonthAtZero() {
        let app = launchApp(storeID: #function, ledgerState: "deletion-confirmed")
        openCoinStore(in: app)

        let reset = app.otherElements["coinStore.reset.disclosure"]
        XCTAssertTrue(reset.waitForExistence(timeout: 2))
        XCTAssertFalse(app.otherElements["coinStore.setup.disclosure"].exists)
        XCTAssertTrue(reset.staticTexts["coinStore.reset.loss"].label.contains("복원"))
        XCTAssertEqual(app.staticTexts["coinStore.test.resetCount"].label, "0")

        app.buttons["coinStore.reset.requestConfirmation"].tap()
        let dialog = app.alerts["새 장부를 시작할까요?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 2))
        dialog.buttons["취소"].tap()
        XCTAssertEqual(app.staticTexts["coinStore.test.resetCount"].label, "0")

        app.buttons["coinStore.reset.requestConfirmation"].tap()
        XCTAssertTrue(dialog.waitForExistence(timeout: 2))
        dialog.buttons["새 장부 시작"].tap()

        XCTAssertTrue(app.otherElements["coinStore.catalog"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].label, "0")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "0")
        XCTAssertEqual(app.staticTexts["coinStore.test.resetCount"].label, "1")
    }

    @MainActor
    func testCatalogShowsAllowedBundlesAndStoreKitLocalizedPrices() {
        let app = launchApp(storeID: #function, ledgerState: "current")
        openCoinStore(in: app)

        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].label, "1")
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "3")
        assertProduct(in: app, quantity: 1, localizedPrice: "₩1,100")
        assertProduct(in: app, quantity: 3, localizedPrice: "₩2,900")
        assertProduct(in: app, quantity: 5, localizedPrice: "₩4,400")
    }

    @MainActor
    func testEveryPurchaseRequiresDeletionRiskConfirmationAndCancelPreservesBalance() {
        let app = launchApp(storeID: #function, ledgerState: "current")
        openCoinStore(in: app)

        for quantity in [1, 3, 5] {
            app.buttons["coinStore.product.\(quantity).purchase"].tap()
            let dialog = app.alerts["코인을 구매할까요?"]
            XCTAssertTrue(dialog.waitForExistence(timeout: 2))
            assertRecoveryLimitDisclosure(in: dialog)
            XCTAssertEqual(app.staticTexts["coinStore.test.purchaseCount"].label, "0")
            dialog.buttons["취소"].tap()
            XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "3")
        }
    }

    @MainActor
    func testVerifiedPurchaseAddsBalanceOnceAndRecordsHistory() {
        let app = launchApp(
            storeID: #function,
            ledgerState: "current",
            purchaseResult: "verified-success"
        )
        openCoinStore(in: app)
        confirmPurchase(quantity: 3, in: app)

        let balance = app.staticTexts["coinStore.balance.purchased"]
        let credited = expectation(for: NSPredicate(format: "label == '6'"), evaluatedWith: balance)
        wait(for: [credited], timeout: 5)
        XCTAssertEqual(app.staticTexts["coinStore.test.purchaseCount"].label, "1")

        app.buttons["coinStore.history.open"].tap()
        let purchase = app.otherElements["coinStore.history.purchaseGrant"]
        XCTAssertTrue(purchase.waitForExistence(timeout: 2))
        XCTAssertEqual(purchase.staticTexts["coinStore.history.quantity"].label, "+3")
        XCTAssertEqual(purchase.staticTexts["coinStore.history.status"].label, "지급 완료")
        XCTAssertFalse(purchase.staticTexts["coinStore.history.timestamp"].label.isEmpty)
    }

    @MainActor
    func testPendingPurchaseIsVisibleAfterReopenAndDoesNotCreditBalance() {
        let storeID = #function
        var app = launchApp(
            storeID: storeID,
            ledgerState: "current",
            purchaseResult: "pending"
        )
        openCoinStore(in: app)
        confirmPurchase(quantity: 1, in: app)
        XCTAssertTrue(app.staticTexts["coinStore.purchase.pending"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "3")

        app.terminate()
        app = launchApp(
            storeID: storeID,
            ledgerState: "current",
            purchaseResult: "pending",
            resetStore: false
        )
        openCoinStore(in: app)
        XCTAssertTrue(app.staticTexts["coinStore.purchase.pending"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "3")
    }

    @MainActor
    func testCancelledAndFailedPurchasesPreserveBalance() {
        for result in ["user-cancelled", "failed"] {
            let app = launchApp(
                storeID: "\(#function)-\(result)",
                ledgerState: "current",
                purchaseResult: result
            )
            openCoinStore(in: app)
            confirmPurchase(quantity: 5, in: app)

            let statusID = result == "failed"
                ? "coinStore.purchase.error"
                : "coinStore.purchase.cancelled"
            XCTAssertTrue(app.staticTexts[statusID].waitForExistence(timeout: 2))
            XCTAssertEqual(app.staticTexts["coinStore.balance.purchased"].label, "3")
            app.terminate()
        }
    }

    @MainActor
    func testHistoryShowsEveryLedgerChangeWithQuantityStatusAndTime() {
        let app = launchApp(
            storeID: #function,
            ledgerState: "current",
            historyFixture: "full-ledger-events"
        )
        openCoinStore(in: app)
        app.buttons["coinStore.history.open"].tap()

        assertHistoryRow(in: app, id: "purchaseGrant", quantity: "+5", status: "구매 지급")
        assertHistoryRow(in: app, id: "freeGrant", quantity: "+2", status: "무료 지급")
        assertHistoryRow(in: app, id: "spend", quantity: "-1", status: "사용 완료")
        assertHistoryRow(in: app, id: "release", quantity: "+1", status: "원상 복구")
        assertHistoryRow(in: app, id: "refundAdjustment", quantity: "-2", status: "환불 보정")
        assertHistoryRow(in: app, id: "reversal", quantity: "+2", status: "환불 취소")
    }

    @MainActor
    func testUnavailableLedgerDisablesPurchasesAndGuidesICloudRetry() {
        let app = launchApp(storeID: #function, ledgerState: "unavailable")
        openCoinStore(in: app)

        XCTAssertTrue(app.staticTexts["coinStore.ledger.unavailable"].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["coinStore.ledger.unavailable"].label.contains("iCloud"))
        XCTAssertTrue(app.buttons["coinStore.ledger.retry"].exists)
        for quantity in [1, 3, 5] {
            XCTAssertTrue(app.buttons["coinStore.product.\(quantity).purchase"].exists)
            XCTAssertFalse(app.buttons["coinStore.product.\(quantity).purchase"].isEnabled)
        }
        XCTAssertEqual(app.staticTexts["coinStore.test.purchaseCount"].label, "0")
    }

    @MainActor
    func testKoreanActivationAndEveryPurchaseDiscloseRecoveryAndRefundLimits() {
        let app = launchApp(
            storeID: #function,
            ledgerState: "setup-required",
            language: "ko"
        )
        openCoinStore(in: app)

        assertCompleteLimitDisclosure(
            app.staticTexts["coinStore.disclosure.recoveryLimit"],
            language: "ko"
        )
        app.buttons["coinStore.setup.confirm"].tap()
        XCTAssertTrue(app.otherElements["coinStore.catalog"].waitForExistence(timeout: 5))

        for quantity in [1, 3, 5] {
            app.buttons["coinStore.product.\(quantity).purchase"].tap()
            let dialog = app.alerts["코인을 구매할까요?"]
            XCTAssertTrue(dialog.waitForExistence(timeout: 2))
            assertCompleteLimitDisclosure(
                dialog.staticTexts["coinStore.disclosure.recoveryLimit"],
                language: "ko"
            )
            dialog.buttons["취소"].tap()
        }
    }

    @MainActor
    func testEnglishActivationAndEveryPurchaseDiscloseRecoveryAndRefundLimits() {
        let app = launchApp(
            storeID: #function,
            ledgerState: "setup-required",
            language: "en"
        )
        openCoinStore(in: app)

        assertCompleteLimitDisclosure(
            app.staticTexts["coinStore.disclosure.recoveryLimit"],
            language: "en"
        )
        app.buttons["coinStore.setup.confirm"].tap()
        XCTAssertTrue(app.otherElements["coinStore.catalog"].waitForExistence(timeout: 5))

        for quantity in [1, 3, 5] {
            app.buttons["coinStore.product.\(quantity).purchase"].tap()
            let dialog = app.alerts["Purchase coins?"]
            XCTAssertTrue(dialog.waitForExistence(timeout: 2))
            assertCompleteLimitDisclosure(
                dialog.staticTexts["coinStore.disclosure.recoveryLimit"],
                language: "en"
            )
            dialog.buttons["Cancel"].tap()
        }
    }

    @MainActor
    private func launchApp(
        storeID: String,
        ledgerState: String,
        purchaseResult: String? = nil,
        historyFixture: String? = nil,
        resetStore: Bool = true,
        language: String = "ko"
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing", "--ui-test-store-id", storeID,
            "--ui-test-scenario", "coin-store",
            "--ui-test-coin-ledger-state", ledgerState,
            "--ui-test-free-balance", "1",
            "--ui-test-purchased-balance", "3",
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "ko" ? "ko_KR" : "en_US",
        ]
        if resetStore {
            app.launchArguments.append("--ui-test-reset-store")
        }
        if let purchaseResult {
            app.launchArguments += ["--ui-test-purchase-result", purchaseResult]
        }
        if let historyFixture {
            app.launchArguments += ["--ui-test-coin-history", historyFixture]
        }
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

    @MainActor
    private func assertProduct(in app: XCUIApplication, quantity: Int, localizedPrice: String) {
        XCTAssertEqual(
            app.staticTexts["coinStore.product.\(quantity).name"].label,
            "코인 \(quantity)개"
        )
        XCTAssertFalse(
            app.staticTexts["coinStore.product.\(quantity).description"].label.isEmpty
        )
        XCTAssertEqual(app.staticTexts["coinStore.product.\(quantity).price"].label, localizedPrice)
        XCTAssertTrue(app.buttons["coinStore.product.\(quantity).purchase"].isEnabled)
    }

    @MainActor
    private func confirmPurchase(quantity: Int, in app: XCUIApplication) {
        app.buttons["coinStore.product.\(quantity).purchase"].tap()
        let dialog = app.alerts["코인을 구매할까요?"]
        XCTAssertTrue(dialog.waitForExistence(timeout: 2))
        assertRecoveryLimitDisclosure(in: dialog)
        dialog.buttons["구매"].tap()
    }

    @MainActor
    private func assertRecoveryLimitDisclosure(in element: XCUIElement) {
        let disclosure = element.staticTexts["coinStore.disclosure.recoveryLimit"].label
        XCTAssertTrue(disclosure.contains("iCloud"))
        XCTAssertTrue(disclosure.contains("장부"))
        XCTAssertTrue(disclosure.contains("삭제"))
        XCTAssertTrue(disclosure.contains("구매 잔액"))
        XCTAssertTrue(disclosure.contains("무료"))
        XCTAssertTrue(disclosure.contains("복원"))
    }

    @MainActor
    private func assertCompleteLimitDisclosure(
        _ element: XCUIElement,
        language: String
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: 2))
        let requiredPhrases = language == "ko"
            ? [
                "현재 구간", "다른 규칙", "만료되지", "같은 iCloud", "App Store 구매 복원",
                "구매 잔액", "이번 달 무료", "0", "서울", "무료 2회", "서버", "환불",
                "미사용", "실시간", "계정이 다르면",
            ]
            : [
                "current occurrence", "other rules", "do not expire", "same iCloud",
                "App Store purchase restoration", "purchased balance", "monthly free",
                "zero", "Seoul", "2 free releases", "server", "refund", "unused",
                "real time", "accounts differ",
            ]
        for phrase in requiredPhrases {
            XCTAssertTrue(
                element.label.localizedCaseInsensitiveContains(phrase),
                "Missing '\(phrase)' in \(language) disclosure: \(element.label)"
            )
        }
    }

    @MainActor
    private func assertHistoryRow(
        in app: XCUIApplication,
        id: String,
        quantity: String,
        status: String
    ) {
        let row = app.otherElements["coinStore.history.\(id)"]
        XCTAssertTrue(row.waitForExistence(timeout: 2))
        XCTAssertEqual(row.staticTexts["coinStore.history.quantity"].label, quantity)
        XCTAssertEqual(row.staticTexts["coinStore.history.status"].label, status)
        XCTAssertFalse(row.staticTexts["coinStore.history.timestamp"].label.isEmpty)
    }
}
