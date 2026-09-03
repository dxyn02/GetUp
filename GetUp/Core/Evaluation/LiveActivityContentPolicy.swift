import Foundation

enum LiveActivityContentPolicy {
    static let maximumLocationAge: TimeInterval = 5 * 60

    static func makeContentState(
        occurrence: RestrictionOccurrence,
        ruleDisplayName: String,
        radiusMeters: Double,
        locationCondition: LocationConditionSnapshot?,
        hasAdditionalRestrictions: Bool,
        now: Date
    ) throws -> RestrictionLiveActivityAttributes.ContentState {
        let distancePresentation = distancePresentation(
            occurrence: occurrence,
            radiusMeters: radiusMeters,
            locationCondition: locationCondition,
            now: now
        )

        return try RestrictionLiveActivityAttributes.ContentState(
            occurrenceID: occurrence.id,
            ruleDisplayName: ruleDisplayName,
            endsAt: occurrence.endAt,
            remainingDistance: distancePresentation.distance,
            distanceObservedAt: distancePresentation.observedAt,
            hasAdditionalRestrictions: hasAdditionalRestrictions
        )
    }

    private static func distancePresentation(
        occurrence: RestrictionOccurrence,
        radiusMeters: Double,
        locationCondition: LocationConditionSnapshot?,
        now: Date
    ) -> (
        distance: RestrictionLiveActivityDistance,
        observedAt: Date?
    ) {
        guard
            radiusMeters.isFinite,
            radiusMeters >= 0,
            let locationCondition,
            locationCondition.ruleID == occurrence.ruleID,
            locationCondition.ruleRevision == occurrence.ruleRevision,
            locationCondition.state == .inside,
            let centerDistance = locationCondition.distanceMeters,
            centerDistance.isFinite,
            centerDistance >= 0,
            let horizontalAccuracy = locationCondition.horizontalAccuracyMeters,
            horizontalAccuracy.isFinite,
            horizontalAccuracy >= 0
        else {
            return (.unavailable, nil)
        }

        let age = now.timeIntervalSince(locationCondition.observedAt)
        guard age >= 0, age <= maximumLocationAge else {
            return (.unavailable, nil)
        }

        let remainingMeters = max(0, radiusMeters - centerDistance)
        let roundedMeters = Int(
            (remainingMeters / 10).rounded(.toNearestOrAwayFromZero)
        ) * 10
        return (
            .known(meters: roundedMeters),
            locationCondition.observedAt
        )
    }
}
