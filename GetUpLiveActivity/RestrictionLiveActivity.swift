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

private struct RestrictionLockScreenView: View {
    let contentState: RestrictionLiveActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                RestrictionRuleLabel(name: contentState.ruleDisplayName)

                Spacer(minLength: 0)

                RestrictionCountdown(endsAt: contentState.endsAt)
                    .font(.title2.bold().monospacedDigit())
            }

            HStack(spacing: 12) {
                RestrictionDistanceLabel(distance: contentState.remainingDistance)

                Spacer(minLength: 0)

                if contentState.hasAdditionalRestrictions {
                    AdditionalRestrictionsLabel()
                }
            }
            .font(.subheadline)
        }
        .foregroundStyle(.white)
        .padding()
    }
}

private struct RestrictionRuleLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.mint)

            Text(name)
                .font(.headline)
                .lineLimit(1)
        }
    }
}

private struct RestrictionCountdown: View {
    let endsAt: Date

    var body: some View {
        let now = Date.now
        Text(
            timerInterval: now...max(now, endsAt),
            countsDown: true,
            showsHours: true
        )
        .lineLimit(1)
        .minimumScaleFactor(0.72)
    }
}

private struct RestrictionDistanceLabel: View {
    let distance: RestrictionLiveActivityDistance
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 3 : 6) {
            Image(systemName: "location.fill")
                .foregroundStyle(.mint)

            switch distance {
            case .known(let meters):
                Text("\(meters) m")
                    .monospacedDigit()
            case .unavailable:
                if compact {
                    Image(systemName: "questionmark")
                } else {
                    Text("거리 확인 불가")
                }
            }
        }
        .lineLimit(1)
    }
}

private struct AdditionalRestrictionsLabel: View {
    var body: some View {
        Label("추가 제한 있음", systemImage: "square.stack.3d.up.fill")
            .lineLimit(1)
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
