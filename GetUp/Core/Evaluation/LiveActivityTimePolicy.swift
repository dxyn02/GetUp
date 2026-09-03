import Foundation

struct LiveActivityTimeEvaluation: Equatable, Sendable {
    let endsAt: Date
    let remainingSeconds: TimeInterval
}

enum LiveActivityTimePolicy {
    static func evaluate(
        endsAt: Date,
        now: Date
    ) -> LiveActivityTimeEvaluation {
        LiveActivityTimeEvaluation(
            endsAt: max(endsAt, now),
            remainingSeconds: max(0, endsAt.timeIntervalSince(now))
        )
    }

    static func clamping(
        contentState: RestrictionLiveActivityAttributes.ContentState,
        now: Date
    ) throws -> RestrictionLiveActivityAttributes.ContentState {
        let time = evaluate(endsAt: contentState.endsAt, now: now)
        return try RestrictionLiveActivityAttributes.ContentState(
            occurrenceID: contentState.occurrenceID,
            ruleDisplayName: contentState.ruleDisplayName,
            endsAt: time.endsAt,
            remainingDistance: contentState.remainingDistance,
            distanceObservedAt: contentState.distanceObservedAt,
            hasAdditionalRestrictions: contentState.hasAdditionalRestrictions
        )
    }

    static func ending(
        contentState: RestrictionLiveActivityAttributes.ContentState,
        now: Date
    ) throws -> RestrictionLiveActivityAttributes.ContentState {
        try RestrictionLiveActivityAttributes.ContentState(
            occurrenceID: contentState.occurrenceID,
            ruleDisplayName: contentState.ruleDisplayName,
            endsAt: now,
            remainingDistance: contentState.remainingDistance,
            distanceObservedAt: contentState.distanceObservedAt,
            hasAdditionalRestrictions: contentState.hasAdditionalRestrictions
        )
    }
}
