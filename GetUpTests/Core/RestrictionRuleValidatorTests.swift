import Foundation
import Testing
@testable import GetUp

@Suite("Restriction rule validator")
struct RestrictionRuleValidatorTests {
    @Test("A complete rule has no validation errors")
    func validRuleHasNoErrors() {
        #expect(RestrictionRuleValidator.errors(in: validInput()) == [])
    }

    @Test("At least one weekday is required")
    func missingWeekdayFailsValidation() {
        let errors = RestrictionRuleValidator.errors(
            in: validInput(weekdays: [])
        )

        #expect(errors.contains(.weekdaysRequired))
    }

    @Test("A saved place selection is required")
    func missingSavedPlaceFailsValidation() {
        let errors = RestrictionRuleValidator.errors(
            in: validInput(savedPlaceID: nil)
        )

        #expect(errors.contains(.savedPlaceRequired))
    }

    @Test("The selected saved place must still exist")
    func unknownSavedPlaceFailsValidation() {
        let errors = RestrictionRuleValidator.errors(
            in: validInput(savedPlaceID: UUID())
        )

        #expect(errors.contains(.savedPlaceNotFound))
    }

    @Test("Every supported radius is accepted", arguments: [500, 1_000, 2_000, 3_000, 4_000, 5_000])
    func supportedRadiusPassesValidation(radiusMeters: Int) {
        let errors = RestrictionRuleValidator.errors(
            in: validInput(radiusMeters: radiusMeters)
        )

        #expect(!errors.contains(.unsupportedRadius))
    }

    @Test("A radius outside the six slider values is rejected")
    func unsupportedRadiusFailsValidation() {
        let errors = RestrictionRuleValidator.errors(
            in: validInput(radiusMeters: 750)
        )

        #expect(errors.contains(.unsupportedRadius))
    }

    @Test("At least one application token is required")
    func missingApplicationTokenFailsValidation() {
        let errors = RestrictionRuleValidator.errors(
            in: validInput(applicationTokenCount: 0)
        )

        #expect(errors.contains(.applicationTokenRequired))
    }

    @Test("Equal start and end times are invalid")
    func equalStartAndEndFailValidation() {
        let errors = RestrictionRuleValidator.errors(
            in: validInput(
                startTime: TimeOfDay(hour: 6, minute: 0),
                endTime: TimeOfDay(hour: 6, minute: 0)
            )
        )

        #expect(errors.contains(.startAndEndMustDiffer))
    }

    @Test("A 14-minute interval fails and a 15-minute interval passes")
    func minimumDurationBoundary() {
        let fourteenMinuteErrors = RestrictionRuleValidator.errors(
            in: validInput(endTime: TimeOfDay(hour: 6, minute: 14))
        )
        let fifteenMinuteErrors = RestrictionRuleValidator.errors(
            in: validInput(endTime: TimeOfDay(hour: 6, minute: 15))
        )

        #expect(fourteenMinuteErrors.contains(.timeRangeTooShort))
        #expect(!fifteenMinuteErrors.contains(.timeRangeTooShort))
    }

    private func validInput(
        weekdays: Set<Weekday> = [.monday],
        startTime: TimeOfDay = TimeOfDay(hour: 6, minute: 0),
        endTime: TimeOfDay = TimeOfDay(hour: 9, minute: 0),
        savedPlaceID: UUID? = RestrictionRuleValidatorTests.knownSavedPlaceID,
        radiusMeters: Int = 500,
        applicationTokenCount: Int = 1
    ) -> RestrictionRuleValidationInput {
        RestrictionRuleValidationInput(
            weekdays: weekdays,
            startTime: startTime,
            endTime: endTime,
            savedPlaceID: savedPlaceID,
            availableSavedPlaceIDs: [Self.knownSavedPlaceID],
            radiusMeters: radiusMeters,
            applicationTokenCount: applicationTokenCount
        )
    }

    private static let knownSavedPlaceID = UUID(
        uuidString: "A7A6F68F-44D7-4EB0-900A-42D730B7EAA1"
    )!
}
