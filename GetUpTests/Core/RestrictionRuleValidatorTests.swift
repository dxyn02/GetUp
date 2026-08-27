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

    @Test("The selected saved place must have a valid coordinate")
    func invalidSavedPlaceCoordinateFailsValidation() {
        let missingCoordinateErrors = RestrictionRuleValidator.errors(
            in: validInput(referenceLocation: nil)
        )
        #expect(missingCoordinateErrors.contains(.invalidReferenceLocation))

        let invalidCoordinates = [
            ReferenceLocation(latitude: 91, longitude: 127),
            ReferenceLocation(latitude: 37, longitude: -181),
            ReferenceLocation(latitude: .infinity, longitude: 127),
            ReferenceLocation(latitude: 37, longitude: .nan),
        ]

        for coordinate in invalidCoordinates {
            let errors = RestrictionRuleValidator.errors(
                in: validInput(referenceLocation: coordinate)
            )

            #expect(errors.contains(.invalidReferenceLocation))
        }
    }

    @Test("Every selectable radius is accepted", arguments: [100, 250, 500, 1_000])
    func supportedRadiusPassesValidation(radiusMeters: Int) {
        let errors = RestrictionRuleValidator.errors(
            in: validInput(radiusMeters: radiusMeters)
        )

        #expect(!errors.contains(.unsupportedRadius))
    }

    @Test("A radius outside the four slider values is rejected", arguments: [750, 2_000])
    func unsupportedRadiusFailsValidation(radiusMeters: Int) {
        let errors = RestrictionRuleValidator.errors(in: validInput(radiusMeters: radiusMeters))

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

    @Test("Hours and minutes outside their model ranges are invalid")
    func invalidTimeComponentsFailValidation() {
        let invalidTimes = [
            TimeOfDay(hour: -1, minute: 0),
            TimeOfDay(hour: 24, minute: 0),
            TimeOfDay(hour: 6, minute: -1),
            TimeOfDay(hour: 6, minute: 60),
        ]

        for time in invalidTimes {
            let errors = RestrictionRuleValidator.errors(
                in: validInput(startTime: time)
            )

            #expect(errors.contains(.invalidTimeOfDay))
        }
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

    @Test("A rule accepts at most twelve hours")
    func maximumDurationBoundary() {
        let twelveHours = RestrictionRuleValidator.errors(
            in: validInput(startTime: TimeOfDay(hour: 18, minute: 0), endTime: TimeOfDay(hour: 6, minute: 0))
        )
        let overTwelveHours = RestrictionRuleValidator.errors(
            in: validInput(startTime: TimeOfDay(hour: 18, minute: 0), endTime: TimeOfDay(hour: 6, minute: 1))
        )

        #expect(!twelveHours.contains(.timeRangeTooLong))
        #expect(overTwelveHours.contains(.timeRangeTooLong))
    }

    private func validInput(
        weekdays: Set<Weekday> = [.monday],
        startTime: TimeOfDay = TimeOfDay(hour: 6, minute: 0),
        endTime: TimeOfDay = TimeOfDay(hour: 9, minute: 0),
        savedPlaceID: UUID? = RestrictionRuleValidatorTests.knownSavedPlaceID,
        referenceLocation: ReferenceLocation? = ReferenceLocation(
            latitude: 37.5665,
            longitude: 126.9780
        ),
        radiusMeters: Int = 500,
        applicationTokenCount: Int = 1
    ) -> RestrictionRuleValidationInput {
        RestrictionRuleValidationInput(
            weekdays: weekdays,
            startTime: startTime,
            endTime: endTime,
            savedPlaceID: savedPlaceID,
            availableSavedPlaceIDs: [Self.knownSavedPlaceID],
            referenceLocation: referenceLocation,
            radiusMeters: radiusMeters,
            applicationTokenCount: applicationTokenCount
        )
    }

    private static let knownSavedPlaceID = UUID(
        uuidString: "A7A6F68F-44D7-4EB0-900A-42D730B7EAA1"
    )!
}
