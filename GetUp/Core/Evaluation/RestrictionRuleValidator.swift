import Foundation

struct RestrictionRuleValidationInput: Equatable, Sendable {
    let weekdays: Set<Weekday>
    let startTime: TimeOfDay
    let endTime: TimeOfDay
    let savedPlaceID: UUID?
    let availableSavedPlaceIDs: Set<UUID>
    let referenceLocation: ReferenceLocation?
    let radiusMeters: Int
    let applicationTokenCount: Int
}

enum RestrictionRuleValidationError: Equatable, Hashable, Sendable {
    case weekdaysRequired
    case invalidTimeOfDay
    case startAndEndMustDiffer
    case timeRangeTooShort
    case savedPlaceRequired
    case savedPlaceNotFound
    case invalidReferenceLocation
    case unsupportedRadius
    case applicationTokenRequired
}

enum RestrictionRuleValidator {
    private static let supportedRadiusMeters = Set(
        RadiusOption.allCases.map(\.rawValue)
    )

    static func errors(
        in input: RestrictionRuleValidationInput
    ) -> Set<RestrictionRuleValidationError> {
        var errors: Set<RestrictionRuleValidationError> = []

        if input.weekdays.isEmpty {
            errors.insert(.weekdaysRequired)
        }

        validateTimeRange(input, errors: &errors)
        validateSavedPlace(input, errors: &errors)

        if !supportedRadiusMeters.contains(input.radiusMeters) {
            errors.insert(.unsupportedRadius)
        }

        if input.applicationTokenCount <= 0 {
            errors.insert(.applicationTokenRequired)
        }

        return errors
    }

    private static func validateTimeRange(
        _ input: RestrictionRuleValidationInput,
        errors: inout Set<RestrictionRuleValidationError>
    ) {
        guard isValid(input.startTime), isValid(input.endTime) else {
            errors.insert(.invalidTimeOfDay)
            return
        }

        guard input.startTime != input.endTime else {
            errors.insert(.startAndEndMustDiffer)
            return
        }

        if !ScheduleEvaluator.isEndTimeSelectable(
            startTime: input.startTime,
            endTime: input.endTime
        ) {
            errors.insert(.timeRangeTooShort)
        }
    }

    private static func validateSavedPlace(
        _ input: RestrictionRuleValidationInput,
        errors: inout Set<RestrictionRuleValidationError>
    ) {
        guard let savedPlaceID = input.savedPlaceID else {
            errors.insert(.savedPlaceRequired)
            return
        }

        guard input.availableSavedPlaceIDs.contains(savedPlaceID) else {
            errors.insert(.savedPlaceNotFound)
            return
        }

        guard
            let location = input.referenceLocation,
            location.latitude.isFinite,
            location.longitude.isFinite,
            (-90...90).contains(location.latitude),
            (-180...180).contains(location.longitude)
        else {
            errors.insert(.invalidReferenceLocation)
            return
        }
    }

    private static func isValid(_ time: TimeOfDay) -> Bool {
        (0...23).contains(time.hour) && (0...59).contains(time.minute)
    }
}
