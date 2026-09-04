import Foundation

#if DEBUG
enum RestrictionLiveActivityPreviewFixtures {
    enum Surface: String, CaseIterable, Sendable {
        case lockScreen
        case dynamicIslandMinimal
        case dynamicIslandCompact
        case dynamicIslandExpanded
    }

    enum Variant: String, CaseIterable, Sendable {
        case known
        case unavailable
        case multipleRestrictions
    }

    struct Scenario: Sendable {
        let surface: Surface
        let variant: Variant
        let attributes: RestrictionLiveActivityAttributes
        let contentState: RestrictionLiveActivityAttributes.ContentState
    }

    static let now = Date(timeIntervalSince1970: 1_788_192_000)

    static let attributes = RestrictionLiveActivityAttributes(
        activityID: UUID(uuidString: "00000000-0000-4000-8000-000000000701")!,
        restrictionStartedAt: now.addingTimeInterval(-15 * 60)
    )

    static let known = makeContentState(
        occurrenceID: "preview-known",
        ruleDisplayName: "집중 시간",
        remainingDistance: .known(meters: 320),
        distanceObservedAt: now,
        hasAdditionalRestrictions: false
    )

    static let unavailable = makeContentState(
        occurrenceID: "preview-unavailable",
        ruleDisplayName: "아침 루틴",
        remainingDistance: .unavailable,
        distanceObservedAt: nil,
        hasAdditionalRestrictions: false
    )

    static let multipleRestrictions = makeContentState(
        occurrenceID: "preview-multiple",
        ruleDisplayName: "업무 집중",
        remainingDistance: .known(meters: 80),
        distanceObservedAt: now,
        hasAdditionalRestrictions: true
    )

    static let scenarios = Surface.allCases.flatMap { surface in
        Variant.allCases.map { variant in
            Scenario(
                surface: surface,
                variant: variant,
                attributes: attributes,
                contentState: contentState(for: variant)
            )
        }
    }

    static func contentState(
        for variant: Variant
    ) -> RestrictionLiveActivityAttributes.ContentState {
        switch variant {
        case .known:
            known
        case .unavailable:
            unavailable
        case .multipleRestrictions:
            multipleRestrictions
        }
    }

    private static func makeContentState(
        occurrenceID: String,
        ruleDisplayName: String,
        remainingDistance: RestrictionLiveActivityDistance,
        distanceObservedAt: Date?,
        hasAdditionalRestrictions: Bool
    ) -> RestrictionLiveActivityAttributes.ContentState {
        do {
            return try RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: occurrenceID,
                ruleDisplayName: ruleDisplayName,
                endsAt: now.addingTimeInterval(45 * 60),
                remainingDistance: remainingDistance,
                distanceObservedAt: distanceObservedAt,
                hasAdditionalRestrictions: hasAdditionalRestrictions
            )
        } catch {
            preconditionFailure("Invalid Live Activity preview fixture: \(error)")
        }
    }
}
#endif
