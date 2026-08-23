import FamilyControls
import Foundation
@testable import GetUp

struct FixedClock: Clock {
    let now: Date
}

enum TestFixtures {
    static let timeZone = TimeZone(secondsFromGMT: 0)!
    static let now = Date(timeIntervalSince1970: 1_786_950_000)

    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = timeZone
        return calendar
    }

    static func makeRule(
        schemaVersion: Int = RestrictionRuleSnapshot.currentSchemaVersion,
        revision: Int = 1,
        isEnabled: Bool = true,
        weekdays: Set<Weekday> = [.monday],
        startTime: TimeOfDay = TimeOfDay(hour: 6, minute: 0),
        endTime: TimeOfDay = TimeOfDay(hour: 9, minute: 0),
        referenceLocation: ReferenceLocation = ReferenceLocation(
            latitude: 37.5665,
            longitude: 126.9780
        ),
        radius: RadiusOption = .meters500,
        activitySelection: FamilyActivitySelection = FamilyActivitySelection(),
        createdAt: Date = now,
        updatedAt: Date = now
    ) -> RestrictionRuleSnapshot {
        RestrictionRuleSnapshot(
            schemaVersion: schemaVersion,
            revision: revision,
            isEnabled: isEnabled,
            weekdays: weekdays,
            startTime: startTime,
            endTime: endTime,
            referenceLocation: referenceLocation,
            radius: radius,
            activitySelection: activitySelection,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    static func makeLocationCondition(
        schemaVersion: Int = LocationConditionSnapshot.currentSchemaVersion,
        ruleRevision: Int = 1,
        state: LocationConditionState = .inside,
        observedAt: Date = now,
        distanceMeters: Double? = 100,
        horizontalAccuracyMeters: Double? = 10,
        source: LocationConditionSource = .freshFix
    ) -> LocationConditionSnapshot {
        LocationConditionSnapshot(
            schemaVersion: schemaVersion,
            ruleRevision: ruleRevision,
            state: state,
            observedAt: observedAt,
            distanceMeters: distanceMeters,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            source: source
        )
    }

    static func makeAuthorization(
        familyControls: FamilyControlsAuthorizationStatus = .approved,
        locationAuthorization: LocationAuthorizationStatus = .always,
        locationAccuracy: LocationAccuracyStatus = .full,
        backgroundRefresh: BackgroundRefreshStatus = .available
    ) -> AuthorizationSnapshot {
        AuthorizationSnapshot(
            familyControls: familyControls,
            locationAuthorization: locationAuthorization,
            locationAccuracy: locationAccuracy,
            backgroundRefresh: backgroundRefresh
        )
    }

    static func makeAppliedRestriction(
        isApplied: Bool = false,
        ruleRevision: Int? = nil
    ) -> AppliedRestrictionState {
        AppliedRestrictionState(
            isApplied: isApplied,
            ruleRevision: ruleRevision
        )
    }
}
