import XCTest

final class UserStory1RuleConfigurationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testRequiredInputValidationAndApplicationSelection() {
        let app = launchApp(
            scenario: "empty-editor",
            storeID: #function,
            resetStore: true,
            familyPickerResult: "one-application"
        )

        let saveButton = app.buttons["ruleEditor.save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 2))
        XCTAssertEqual(saveButton.frame.height, 56, accuracy: 1)
        XCTAssertFalse(saveButton.isEnabled)
        XCTAssertTrue(app.staticTexts["ruleEditor.weekday.validation"].exists)
        XCTAssertTrue(app.staticTexts["ruleEditor.location.validation"].exists)
        XCTAssertTrue(app.staticTexts["ruleEditor.application.validation"].exists)

        let ruleName = app.textFields["ruleEditor.name"]
        ruleName.tap()
        ruleName.typeText("Morning Focus")

        let monday = app.buttons["ruleEditor.weekday.monday"]
        monday.tap()
        XCTAssertTrue(monday.isSelected)

        app.buttons["ruleEditor.locationRow"].tap()
        XCTAssertTrue(app.buttons["locationPicker.savedPlace.home"].exists)
        XCTAssertTrue(app.buttons["locationPicker.savedPlace.work"].exists)
        let placeNameValidation = app.staticTexts["locationPicker.placeName.validation"]
        XCTAssertEqual(placeNameValidation.label, "장소 이름을 입력해 주세요.")
        XCTAssertEqual(app.staticTexts.matching(identifier: "locationPicker.placeName.validation").count, 1)

        let radius = app.sliders["locationPicker.radius"]
        XCTAssertTrue(radius.exists)
        XCTAssertEqual(radius.value as? String, "1km")
        radius.adjust(toNormalizedSliderPosition: 0)
        XCTAssertEqual(radius.value as? String, "100m")
        radius.adjust(toNormalizedSliderPosition: 1.0 / 3.0)
        XCTAssertEqual(radius.value as? String, "250m")
        radius.adjust(toNormalizedSliderPosition: 2.0 / 3.0)
        XCTAssertEqual(radius.value as? String, "500m")
        radius.adjust(toNormalizedSliderPosition: 1)
        XCTAssertEqual(radius.value as? String, "1km")

        let customPlace = app.buttons["locationPicker.customPlace"]
        customPlace.tap()
        XCTAssertTrue(customPlace.isSelected)
        XCTAssertEqual(app.staticTexts.matching(identifier: "locationPicker.placeName.validation").count, 1)
        let placeName = app.textFields["locationPicker.placeName"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 2))
        placeName.typeText("12345678901")
        let cappedValue = expectation(
            for: NSPredicate(format: "value == %@", "1234567890"),
            evaluatedWith: placeName
        )
        wait(for: [cappedValue], timeout: 2)

        let home = app.buttons["locationPicker.savedPlace.home"]
        home.tap()
        XCTAssertTrue(home.isSelected)
        XCTAssertFalse(customPlace.isSelected)
        XCTAssertFalse(placeNameValidation.exists)
        let applyButton = app.buttons["locationPicker.confirm"]
        XCTAssertGreaterThan(applyButton.frame.width, 300)
        applyButton.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        XCTAssertEqual(app.staticTexts["ruleEditor.locationSummary"].label, "집 · 1km")

        app.buttons["ruleEditor.applicationRow"].tap()
        let applicationSummary = app.staticTexts["ruleEditor.applicationSummary"]
        XCTAssertTrue(applicationSummary.waitForExistence(timeout: 2))
        XCTAssertEqual(applicationSummary.label, "1개 앱 선택됨")

        XCTAssertTrue(saveButton.isEnabled)
    }

    @MainActor
    func testCustomPlaceChipUsesEnteredNameAndCanReopenTheNameField() {
        let app = launchApp(
            scenario: "empty-editor",
            storeID: #function,
            resetStore: true
        )

        app.buttons["ruleEditor.locationRow"].tap()
        let customPlace = app.buttons["locationPicker.customPlace"]
        customPlace.tap()

        let placeName = app.textFields["locationPicker.placeName"]
        XCTAssertTrue(placeName.waitForExistence(timeout: 2))
        placeName.typeText("Study")
        XCTAssertEqual(customPlace.label, "Study")

        placeName.typeText("\n")
        XCTAssertFalse(placeName.exists)

        customPlace.tap()
        XCTAssertTrue(placeName.waitForExistence(timeout: 2))
        placeName.typeText("2")
        XCTAssertEqual(customPlace.label, "Study2")
    }

    @MainActor
    func testSelectedPlaceRemainsSelectedAfterLeavingAndReenteringLocationPicker() {
        let app = launchApp(
            scenario: "empty-editor",
            storeID: #function,
            resetStore: true
        )

        app.buttons["ruleEditor.locationRow"].tap()
        let home = app.buttons["locationPicker.savedPlace.home"]
        XCTAssertTrue(home.waitForExistence(timeout: 2))
        home.tap()
        XCTAssertTrue(home.isSelected)

        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["ruleEditor.locationRow"].waitForExistence(timeout: 2))
        app.buttons["ruleEditor.locationRow"].tap()

        XCTAssertTrue(home.waitForExistence(timeout: 2))
        XCTAssertTrue(home.isSelected)
    }

    @MainActor
    func testDeletingUnusedCustomPlaceRequiresConfirmationAndPersists() {
        let storeID = #function
        let customID = "locationPicker.savedPlace.00000000-0000-4000-8000-000000000503"
        var app = launchApp(
            scenario: "unused-custom-place-editor",
            storeID: storeID,
            resetStore: true
        )

        app.buttons["ruleEditor.locationRow"].tap()
        let customPlace = app.buttons[customID]
        XCTAssertTrue(customPlace.waitForExistence(timeout: 2))
        app.buttons["\(customID).delete"].tap()

        let confirmation = app.alerts["도서관을 삭제할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["삭제"].tap()
        XCTAssertFalse(customPlace.waitForExistence(timeout: 1))

        app.terminate()
        app = launchApp(
            scenario: "unused-custom-place-editor",
            storeID: storeID
        )
        app.buttons["ruleEditor.locationRow"].tap()
        XCTAssertFalse(app.buttons[customID].waitForExistence(timeout: 1))
    }

    @MainActor
    func testDeletingCustomPlaceImmediatelyAfterAddingItRemovesTheDraftPlace() {
        let app = launchApp(
            scenario: "empty-editor",
            storeID: #function,
            resetStore: true
        )

        app.buttons["ruleEditor.locationRow"].tap()
        app.buttons["locationPicker.customPlace"].tap()
        let nameField = app.textFields["locationPicker.placeName"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 2))
        nameField.typeText("Study")
        nameField.typeText("\n")
        let applyButton = app.buttons["locationPicker.confirm"]
        XCTAssertTrue(applyButton.isEnabled)
        applyButton.tap()

        XCTAssertTrue(app.buttons["ruleEditor.locationRow"].waitForExistence(timeout: 2))
        app.buttons["ruleEditor.locationRow"].tap()
        let deleteButton = app.buttons["Study 삭제"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 2))
        deleteButton.tap()

        let confirmation = app.alerts["Study을 삭제할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["삭제"].tap()

        XCTAssertFalse(deleteButton.waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["Study"].exists)
        XCTAssertFalse(app.alerts["장소를 삭제하지 못했어요"].exists)
        XCTAssertFalse(app.buttons["locationPicker.confirm"].isEnabled)
    }

    @MainActor
    func testApplicationSelectionWithoutScreenTimePermissionPresentsPermissionGuide() {
        let app = launchApp(
            scenario: "empty-editor-family-controls-undetermined",
            storeID: #function,
            resetStore: true
        )

        let applicationRow = app.buttons["ruleEditor.applicationRow"]
        XCTAssertTrue(applicationRow.waitForExistence(timeout: 2))
        applicationRow.tap()

        let permissionTitle = app.staticTexts["permissionGuide.title"]
        XCTAssertTrue(permissionTitle.waitForExistence(timeout: 2))
        XCTAssertEqual(permissionTitle.label, "앱 사용 제한 권한이 필요해요")
        XCTAssertTrue(
            app.buttons["permissionGuide.requestFamilyControlsAuthorization"].exists
        )
    }

    @MainActor
    func testCategorySelectionUsesNonNumericApplicationSummary() {
        let app = launchApp(
            scenario: "empty-editor",
            storeID: #function,
            resetStore: true,
            familyPickerResult: "one-category"
        )

        app.buttons["ruleEditor.applicationRow"].tap()

        let applicationSummary = app.staticTexts["ruleEditor.applicationSummary"]
        XCTAssertTrue(applicationSummary.waitForExistence(timeout: 2))
        XCTAssertEqual(applicationSummary.label, "여러 앱 선택됨")
    }

    @MainActor
    func testValidRuleSavesAndReloadsFromPersistentStore() {
        let storeID = #function
        var app = launchApp(
            scenario: "valid-rule-draft",
            storeID: storeID,
            resetStore: true,
            familyPickerResult: "one-application"
        )

        XCTAssertEqual(app.buttons["ruleEditor.startTime"].value as? String, "06:00 AM")
        XCTAssertEqual(app.buttons["ruleEditor.endTime"].value as? String, "09:00 AM")
        XCTAssertEqual(app.staticTexts["ruleEditor.applicationSummary"].label, "1개 앱 선택됨")

        app.buttons["ruleEditor.save"].tap()

        assertFirstRuleCard(in: app)

        app.terminate()
        app = launchApp(storeID: storeID)

        assertFirstRuleCard(in: app)
    }

    @MainActor
    func testHomeAppearsWithoutWaitingForRuntimeRecovery() {
        let app = launchApp(
            scenario: "startup-slow-recovery",
            storeID: #function,
            resetStore: true
        )

        XCTAssertTrue(app.otherElements["home.rulePager"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.label, "나서")
        XCTAssertEqual(app.staticTexts["home.brandName"].label, "나서")
        XCTAssertFalse(app.staticTexts["규칙을 불러오는 중"].exists)
    }

    @MainActor
    func testEmptyHomeExplainsThatRestrictedAppsReopenOutside() {
        let app = launchApp(
            storeID: #function,
            resetStore: true
        )

        let message = app.staticTexts["home.emptyState.description"]
        XCTAssertTrue(message.waitForExistence(timeout: 2))
        XCTAssertEqual(message.label, "밖으로 나가면 제한된 앱이 다시 열려요")
    }

    @MainActor
    func testTimePickerUsesFixedSequentialFlow() {
        let app = launchApp(
            scenario: "valid-rule-draft",
            storeID: #function,
            resetStore: true
        )
        let window = app.windows.firstMatch

        app.buttons["ruleEditor.startTime"].tap()

        let startTitle = app.staticTexts["ruleEditor.startTime.pickerTitle"]
        XCTAssertTrue(startTitle.waitForExistence(timeout: 2))
        XCTAssertEqual(startTitle.label, "시작 시각")
        let navigationBar = app.navigationBars.firstMatch
        XCTAssertTrue(navigationBar.exists)
        XCTAssertTrue(navigationBar.buttons.firstMatch.exists)
        XCTAssertFalse(app.buttons["ruleEditor.timePicker.back"].exists)
        XCTAssertEqual(
            app.staticTexts["ruleEditor.timePicker.instructions"].label,
            "시·분·AM/PM을 위아래로 밀어 선택해요"
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["ruleEditor.startTime.pickerCard"].exists
        )

        let startPickerScreenshot = XCTAttachment(screenshot: app.screenshot())
        startPickerScreenshot.name = "T103-start-time-fixed-wheel"
        startPickerScreenshot.lifetime = .keepAlways
        add(startPickerScreenshot)

        let done = app.buttons["ruleEditor.timePicker.done"]
        XCTAssertTrue(done.exists)
        XCTAssertEqual(done.frame.height, 64, accuracy: 1)
        XCTAssertEqual(done.frame.width, window.frame.width - 40, accuracy: 1)
        done.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()

        let endTitle = app.staticTexts["ruleEditor.endTime.pickerTitle"]
        XCTAssertTrue(endTitle.waitForExistence(timeout: 2))
        XCTAssertEqual(endTitle.label, "종료 시각")
        XCTAssertTrue(app.staticTexts["ruleEditor.endTime.minimumDuration"].exists)

        app.buttons["ruleEditor.timePicker.done"]
            .coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5))
            .tap()
        XCTAssertTrue(app.buttons["ruleEditor.endTime"].waitForExistence(timeout: 2))
    }

    @MainActor
    func testEndTimeWheelComponentsChangeIndependently() {
        let app = launchApp(
            scenario: "valid-rule-draft",
            storeID: #function,
            resetStore: true
        )

        app.buttons["ruleEditor.startTime"].tap()
        let startHour = app.pickerWheels.element(boundBy: 0)
        XCTAssertTrue(startHour.waitForExistence(timeout: 2))
        startHour.adjust(toPickerWheelValue: "10")
        app.buttons["ruleEditor.timePicker.done"].tap()

        let endHour = app.pickerWheels.element(boundBy: 0)
        let endMinute = app.pickerWheels.element(boundBy: 1)
        let endPeriod = app.pickerWheels.element(boundBy: 2)
        XCTAssertTrue(endHour.waitForExistence(timeout: 2))
        XCTAssertEqual(endHour.value as? String, "10")
        XCTAssertEqual(endMinute.value as? String, "15")
        XCTAssertEqual(endPeriod.value as? String, "AM")

        endMinute.adjust(toPickerWheelValue: "16")
        XCTAssertEqual(endHour.value as? String, "10")
        XCTAssertEqual(endMinute.value as? String, "16")
        XCTAssertEqual(endPeriod.value as? String, "AM")

        endPeriod.adjust(toPickerWheelValue: "PM")
        XCTAssertEqual(endHour.value as? String, "10")
        XCTAssertEqual(endMinute.value as? String, "16")
        XCTAssertEqual(endPeriod.value as? String, "PM")
    }

    @MainActor
    func testHomePagerShowsEverySavedRuleAndSupportsBidirectionalSwipe() {
        let app = launchApp(
            scenario: "three-saved-rules",
            storeID: #function,
            resetStore: true
        )
        let pager = app.otherElements["home.rulePager"]
        let pagerViewport = app.descendants(matching: .any)["home.rulePager.viewport"]
        let window = app.windows.firstMatch

        XCTAssertTrue(pager.waitForExistence(timeout: 2))
        XCTAssertTrue(pagerViewport.exists)
        XCTAssertEqual(pagerViewport.frame.minX, window.frame.minX, accuracy: 1)
        XCTAssertEqual(pagerViewport.frame.maxX, window.frame.maxX, accuracy: 1)
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-1"].exists)
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "1 / 3")

        pager.swipeLeft()
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-2"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "2 / 3")

        pager.swipeLeft()
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-3"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "3 / 3")

        pager.swipeRight()
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-2"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "2 / 3")
    }

    @MainActor
    func testEditingAHomeCardPreservesThatRulesValues() {
        let app = launchApp(
            scenario: "three-saved-rules",
            storeID: #function,
            resetStore: true
        )
        let pager = app.otherElements["home.rulePager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 2))

        pager.swipeLeft()
        let edit = app.buttons["home.ruleCard.rule-2.edit"]
        XCTAssertGreaterThan(edit.frame.width, 250)
        edit.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()

        XCTAssertEqual(app.textFields["ruleEditor.name"].value as? String, "퇴근 준비")
        XCTAssertEqual(app.buttons["ruleEditor.startTime"].value as? String, "06:00 PM")
        XCTAssertEqual(app.buttons["ruleEditor.endTime"].value as? String, "08:00 PM")
        XCTAssertEqual(app.staticTexts["ruleEditor.locationSummary"].label, "회사 · 500m")
        XCTAssertEqual(app.staticTexts["ruleEditor.applicationSummary"].label, "2개 앱 선택됨")
    }

    @MainActor
    func testDeletingAHomeRuleRequiresConfirmationAndPersistsAfterRelaunch() {
        let storeID = #function
        var app = launchApp(
            scenario: "three-saved-rules",
            storeID: storeID,
            resetStore: true
        )
        let pager = app.otherElements["home.rulePager"]
        XCTAssertTrue(pager.waitForExistence(timeout: 2))

        pager.swipeLeft()
        app.buttons["home.ruleCard.rule-2.edit"].tap()
        app.buttons["ruleEditor.delete"].tap()

        let confirmation = app.alerts["규칙을 삭제할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["삭제"].tap()

        XCTAssertTrue(app.otherElements["home.rulePager"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "1 / 2")

        app.terminate()
        app = launchApp(storeID: storeID)
        XCTAssertTrue(app.otherElements["home.rulePager"].waitForExistence(timeout: 2))
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "1 / 2")
    }

    @MainActor
    func testDeletingEveryRuleTransitionsFromPagerToEmptyHomeWithoutTerminating() {
        let app = launchApp(
            scenario: "three-saved-rules",
            storeID: #function,
            resetStore: true
        )

        deleteRule(accessibilityID: "rule-1", in: app)
        XCTAssertEqual(app.otherElements["home.rulePageIndicator"].label, "1 / 2")

        deleteRule(accessibilityID: "rule-2", in: app)
        XCTAssertFalse(app.otherElements["home.rulePager"].exists)
        XCTAssertTrue(app.otherElements["home.ruleCard.rule-3"].waitForExistence(timeout: 2))

        deleteRule(accessibilityID: "rule-3", in: app)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(
            app.staticTexts["home.emptyState.description"]
                .waitForExistence(timeout: 2)
        )
        XCTAssertFalse(app.otherElements["home.rulePager"].exists)
        XCTAssertFalse(app.otherElements["home.ruleCard.rule-3"].exists)
    }

    @MainActor
    private func launchApp(
        scenario: String? = nil,
        storeID: String,
        resetStore: Bool = false,
        familyPickerResult: String? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--ui-testing",
            "--ui-test-store-id", storeID,
        ]

        if let scenario {
            app.launchArguments += ["--ui-test-scenario", scenario]
        }
        if resetStore {
            app.launchArguments.append("--ui-test-reset-store")
        }
        if let familyPickerResult {
            app.launchArguments += ["--ui-test-family-picker-result", familyPickerResult]
        }

        app.launch()
        return app
    }

    @MainActor
    private func assertFirstRuleCard(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let card = app.otherElements["home.ruleCard.rule-1"]
        XCTAssertTrue(card.waitForExistence(timeout: 2), file: file, line: line)
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.time"].label,
            "06:00 AM → 09:00 AM",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.schedule"].label,
            "RULE 1 OF 1 · MON · WED · FRI",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.location"].label,
            "집 · 1km",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.staticTexts["home.ruleCard.rule-1.applications"].label,
            "1개 앱",
            file: file,
            line: line
        )
        XCTAssertEqual(
            app.scrollViews.count,
            0,
            file: file,
            line: line
        )
        XCTAssertFalse(app.otherElements["home.rulePager"].exists, file: file, line: line)
        XCTAssertFalse(app.otherElements["home.rulePageIndicator"].exists, file: file, line: line)
        XCTAssertFalse(app.staticTexts["좌우로 밀어 보기"].exists, file: file, line: line)
    }

    @MainActor
    private func deleteRule(accessibilityID: String, in app: XCUIApplication) {
        let edit = app.buttons["home.ruleCard.\(accessibilityID).edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 2))
        edit.tap()

        app.buttons["ruleEditor.delete"].tap()
        let confirmation = app.alerts["규칙을 삭제할까요?"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 2))
        confirmation.buttons["삭제"].tap()
    }
}
