import Foundation
import SwiftUI
import WidgetKit
#if GETUP_PRESENTATION_TESTS
@testable import GetUp
#endif

#if DEBUG || GETUP_PRESENTATION_TESTS
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
        case stale
        case multipleRestrictions
    }

    enum Language: String, CaseIterable, Sendable {
        case korean = "ko"
        case english = "en"
    }

    enum Appearance: String, CaseIterable, Sendable {
        case light
        case dark
    }

    enum TextSize: String, CaseIterable, Sendable {
        case standard
        case accessibility5
    }

    struct Scenario: Sendable {
        let surface: Surface
        let variant: Variant
        let language: Language
        let appearance: Appearance
        let textSize: TextSize
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

    // A previously known distance has crossed the five-minute freshness boundary.
    // The presentation must no longer expose its old numeric value.
    static let stale = makeContentState(
        occurrenceID: "preview-stale",
        ruleDisplayName: "집중 시간",
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

    static let scenarios: [Scenario] = Surface.allCases.flatMap { surface in
        Variant.allCases.flatMap { variant in
            Language.allCases.flatMap { language in
                Appearance.allCases.flatMap { appearance in
                    TextSize.allCases.map { textSize in
                        Scenario(
                            surface: surface,
                            variant: variant,
                            language: language,
                            appearance: appearance,
                            textSize: textSize,
                            attributes: attributes,
                            contentState: contentState(for: variant)
                        )
                    }
                }
            }
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
        case .stale:
            stale
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

#if DEBUG && !GETUP_PRESENTATION_TESTS
#Preview(
    "Lock Screen · Stale",
    as: .content,
    using: RestrictionLiveActivityPreviewFixtures.attributes
) {
    RestrictionLiveActivity()
} contentStates: {
    RestrictionLiveActivityPreviewFixtures.stale
}
#endif
