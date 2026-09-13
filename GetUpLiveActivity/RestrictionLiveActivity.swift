import ActivityKit
import SwiftUI
import WidgetKit

struct RestrictionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestrictionLiveActivityAttributes.self) { context in
            RestrictionLockScreenView(contentState: context.state)
                .activityBackgroundTint(Color.black.opacity(0.88))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RestrictionRuleLabel(name: context.state.ruleDisplayName)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    RestrictionCountdown(endsAt: context.state.endsAt)
                        .font(.headline.monospacedDigit())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        RestrictionDistanceLabel(
                            distance: context.state.remainingDistance
                        )

                        Spacer(minLength: 0)

                        if context.state.hasAdditionalRestrictions {
                            AdditionalRestrictionsLabel()
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                RestrictionDistanceLabel(
                    distance: context.state.remainingDistance,
                    compact: true
                )
            } compactTrailing: {
                RestrictionCountdown(endsAt: context.state.endsAt)
                    .font(.caption.monospacedDigit())
                    .frame(maxWidth: 54)
            } minimal: {
                RestrictionCountdown(endsAt: context.state.endsAt)
                    .font(.caption2.monospacedDigit())
            }
            .keylineTint(.mint)
        }
    }
}

#if DEBUG
#Preview(
    "Lock Screen · Known",
    as: .content,
    using: RestrictionLiveActivityPreviewFixtures.attributes
) {
    RestrictionLiveActivity()
} contentStates: {
    RestrictionLiveActivityPreviewFixtures.known
}

#Preview(
    "Dynamic Island · Minimal",
    as: .dynamicIsland(.minimal),
    using: RestrictionLiveActivityPreviewFixtures.attributes
) {
    RestrictionLiveActivity()
} contentStates: {
    RestrictionLiveActivityPreviewFixtures.unavailable
}

#Preview(
    "Dynamic Island · Compact",
    as: .dynamicIsland(.compact),
    using: RestrictionLiveActivityPreviewFixtures.attributes
) {
    RestrictionLiveActivity()
} contentStates: {
    RestrictionLiveActivityPreviewFixtures.known
}

#Preview(
    "Dynamic Island · Expanded",
    as: .dynamicIsland(.expanded),
    using: RestrictionLiveActivityPreviewFixtures.attributes
) {
    RestrictionLiveActivity()
} contentStates: {
    RestrictionLiveActivityPreviewFixtures.multipleRestrictions
}
#endif
