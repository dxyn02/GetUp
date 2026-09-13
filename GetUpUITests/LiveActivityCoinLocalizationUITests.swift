import XCTest

final class LiveActivityCoinLocalizationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testKoreanLiveActivityAppAndShieldUseEquivalentReleaseLanguage() {
        assertLocalizedSurfaces(
            language: "ko",
            locale: "ko_KR",
            expected: .korean
        )
    }

    @MainActor
    func testEnglishLiveActivityAppAndShieldUseEquivalentReleaseLanguage() {
        assertLocalizedSurfaces(
            language: "en",
            locale: "en_US",
            expected: .english
        )
    }

    @MainActor
    func testLiveActivityAppAndShieldRemainUsableInLightAndDarkAppearances() {
        for appearance in ["Light", "Dark"] {
            var app = launchApp(
                scenario: "live-activity-preview",
                storeID: "\(#function).\(appearance).liveActivity",
                additionalArguments: [
                    "--ui-test-live-activity", "unavailable",
                    "-AppleInterfaceStyle", appearance,
                ]
            )
            XCTAssertTrue(
                app.otherElements["liveActivity.preview"]
                    .waitForExistence(timeout: 5),
                "Live Activity preview must render in \(appearance) appearance."
            )
            XCTAssertEqual(
                app.descendants(matching: .any)["liveActivity.distance"].label,
                "남은 거리 확인 불가"
            )
            app.terminate()

            app = launchApp(
                scenario: "coin-store",
                storeID: "\(#function).\(appearance).app",
                additionalArguments: [
                    "--ui-test-coin-ledger-state", "current",
                    "--ui-test-free-balance", "1",
                    "--ui-test-purchased-balance", "3",
                    "-AppleInterfaceStyle", appearance,
                ]
            )
            openCoinStore(in: app)
            XCTAssertTrue(app.staticTexts["coinStore.balance.free"].exists)
            XCTAssertTrue(app.buttons["coinStore.history.open"].isHittable)
            app.terminate()

            app = launchRelease(
                storeID: "\(#function).\(appearance).shield",
                language: "ko",
                locale: "ko_KR",
                appearance: appearance
            )
            openShield(in: app)
            XCTAssertTrue(app.buttons["restrictionProbe.shield.release"].isHittable)
            XCTAssertTrue(app.buttons["restrictionProbe.shield.close"].isHittable)
            app.terminate()
        }
    }

    @MainActor
    private func assertLocalizedSurfaces(
        language: String,
        locale: String,
        expected: ExpectedCopy
    ) {
        var app = launchApp(
            scenario: "live-activity-preview",
            storeID: "\(#function).\(language).liveActivity",
            language: language,
            locale: locale,
            additionalArguments: [
                "--ui-test-live-activity", "multiple-restrictions",
            ]
        )
        XCTAssertTrue(app.otherElements["liveActivity.preview"].waitForExistence(timeout: 5))
        let liveActivityElements = app.descendants(matching: .any)
        XCTAssertEqual(liveActivityElements["liveActivity.rule"].label, expected.liveActivityRule)
        XCTAssertEqual(liveActivityElements["liveActivity.distance"].label, expected.liveActivityDistance)
        XCTAssertEqual(
            liveActivityElements["liveActivity.additionalRestrictions"].label,
            expected.liveActivityAdditionalRestrictions
        )
        app.terminate()

        app = launchApp(
            scenario: "coin-store",
            storeID: "\(#function).\(language).app",
            language: language,
            locale: locale,
            additionalArguments: [
                "--ui-test-coin-ledger-state", "current",
                "--ui-test-free-balance", "1",
                "--ui-test-purchased-balance", "3",
            ]
        )
        openCoinStore(in: app)
        XCTAssertEqual(app.staticTexts["coinStore.monthly.title"].label, expected.monthlyTitle)
        XCTAssertEqual(app.staticTexts["coinStore.balance.free"].value as? String, expected.freeBalance)
        XCTAssertEqual(
            app.staticTexts["coinStore.balance.purchased"].value as? String,
            expected.purchasedBalance
        )
        app.terminate()

        app = launchRelease(
            storeID: "\(#function).\(language).shield",
            language: language,
            locale: locale
        )
        openShield(in: app)
        XCTAssertEqual(app.staticTexts["restrictionProbe.shield.cost"].label, expected.shieldCost)
        XCTAssertEqual(app.buttons["restrictionProbe.shield.release"].label, expected.releaseAction)
        XCTAssertEqual(app.buttons["restrictionProbe.shield.close"].label, expected.closeAction)
        app.terminate()
    }

    @MainActor
    private func launchRelease(
        storeID: String,
        language: String,
        locale: String,
        appearance: String? = nil
    ) -> XCUIApplication {
        var additionalArguments = [
            "--ui-test-now", "2026-08-24T07:00:00Z",
            "--ui-test-location-state", "inside",
            "--ui-test-coin-release", "overlapping",
            "--ui-test-coin-release-result", "held-success",
        ]
        if let appearance {
            additionalArguments += ["-AppleInterfaceStyle", appearance]
        }
        return launchApp(
            scenario: "restriction-activation",
            storeID: storeID,
            language: language,
            locale: locale,
            additionalArguments: additionalArguments
        )
    }

    @MainActor
    private func launchApp(
        scenario: String,
        storeID: String,
        language: String = "ko",
        locale: String = "ko_KR",
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-test-store-id", storeID,
            "--ui-test-reset-store",
            "--ui-test-scenario", scenario,
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", locale,
        ] + additionalArguments
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
    private func openShield(in app: XCUIApplication) {
        let open = app.buttons["restrictionProbe.selectedApplication.open"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.otherElements["restrictionProbe.shield"].waitForExistence(timeout: 2))
    }
}

private struct ExpectedCopy {
    let liveActivityRule: String
    let liveActivityDistance: String
    let liveActivityAdditionalRestrictions: String
    let monthlyTitle: String
    let freeBalance: String
    let purchasedBalance: String
    let shieldCost: String
    let releaseAction: String
    let closeAction: String

    static let korean = ExpectedCopy(
        liveActivityRule: "제한 규칙: 업무 집중",
        liveActivityDistance: "남은 거리 80미터",
        liveActivityAdditionalRestrictions: "다른 제한도 활성화되어 있어요",
        monthlyTitle: "이번 달 무료 해제권",
        freeBalance: "1회",
        purchasedBalance: "3개",
        shieldCost: "이번 달 무료 해제권 우선 · 없으면 코인 1개",
        releaseAction: "해제권 1회 사용",
        closeAction: "앱 닫기"
    )

    static let english = ExpectedCopy(
        liveActivityRule: "Restriction rule: 업무 집중",
        liveActivityDistance: "80 meters remaining",
        liveActivityAdditionalRestrictions: "Other restrictions are also active",
        monthlyTitle: "Monthly Free Releases",
        freeBalance: "1 release",
        purchasedBalance: "3 coins",
        shieldCost: "Monthly free release first · otherwise 1 purchased coin",
        releaseAction: "Use 1 Release",
        closeAction: "Close App"
    )
}
