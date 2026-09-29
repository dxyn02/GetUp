import ActivityKit
import SwiftUI
import WidgetKit

private enum LiveActivityColor {
    static let background = Color(red: 8 / 255, green: 9 / 255, blue: 11 / 255)
    static let surface = Color(red: 21 / 255, green: 23 / 255, blue: 27 / 255)
    static let surfaceElevated = Color(red: 32 / 255, green: 35 / 255, blue: 41 / 255)
    static let accent = Color(red: 244 / 255, green: 214 / 255, blue: 0)
    static let primary = Color.white
    static let secondary = Color(red: 166 / 255, green: 168 / 255, blue: 173 / 255)
}

struct RestrictionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestrictionLiveActivityAttributes.self) { context in
            RestrictionLockScreenView(contentState: context.state)
                .activityBackgroundTint(LiveActivityColor.surface)
                .activitySystemActionForegroundColor(LiveActivityColor.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    RestrictionRuleLabel(name: context.state.ruleDisplayName)
                }
                .contentMargins(.leading, 24)

                DynamicIslandExpandedRegion(.trailing) {
                    RestrictionCountdown(endsAt: context.state.endsAt)
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .contentMargins(.trailing, 24)

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        RestrictionDistanceLabel(distance: context.state.remainingDistance)
                        Spacer(minLength: 0)
                        if context.state.hasAdditionalRestrictions {
                            AdditionalRestrictionsLabel()
                        }
                    }
                    .font(.system(size: 15, weight: .regular))
                    .padding(.top, 8)
                }
                .contentMargins(.horizontal, 14)
            } compactLeading: {
                RestrictionDistanceLabel(
                    distance: context.state.remainingDistance,
                    compact: true,
                    hasAdditionalRestrictions: context.state.hasAdditionalRestrictions
                )
            } compactTrailing: {
                RestrictionCountdown(endsAt: context.state.endsAt, compact: true)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .frame(maxWidth: 66, alignment: .leading)
            } minimal: {
                RestrictionCountdown(endsAt: context.state.endsAt, minimal: true)
                    .font(.system(size: 9, weight: .bold).monospacedDigit())
            }
            .contentMargins(.leading, 10, for: .compactLeading)
            .contentMargins(.trailing, 0, for: .compactLeading)
            .contentMargins(.leading, 0, for: .compactTrailing)
            .contentMargins(.trailing, 10, for: .compactTrailing)
            .keylineTint(LiveActivityColor.accent)
        }
    }
}

private struct RestrictionLockScreenView: View {
    let contentState: RestrictionLiveActivityAttributes.ContentState

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var ruleSize: CGFloat = 17
    @ScaledMetric(relativeTo: .headline) private var timeSize: CGFloat = 17
    @ScaledMetric(relativeTo: .body) private var detailSize: CGFloat = 15

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                RestrictionRuleLabel(name: contentState.ruleDisplayName, allowsWrapping: true)
                    .font(.system(size: min(ruleSize, 24), weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                RestrictionCountdown(endsAt: contentState.endsAt)
                    .font(.system(
                        size: dynamicTypeSize.isAccessibilitySize ? 22 : timeSize,
                        weight: .bold
                    ).monospacedDigit())
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? 120 : 105, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
            if dynamicTypeSize.isAccessibilitySize {
                RestrictionDistanceLabel(distance: contentState.remainingDistance)
                    .font(.system(size: min(detailSize, 18), weight: .semibold))
                if contentState.hasAdditionalRestrictions {
                    AdditionalRestrictionsLabel()
                        .font(.system(size: min(detailSize, 18), weight: .semibold))
                }
            } else {
                RestrictionDistanceLabel(distance: contentState.remainingDistance)
                    .font(.system(size: detailSize))
                if contentState.hasAdditionalRestrictions {
                    AdditionalRestrictionsLabel()
                        .font(.system(size: detailSize))
                }
            }
        }
        .foregroundStyle(LiveActivityColor.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            LiveActivityColor.surface,
            in: RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? 28 : 18)
        )
    }
}

private struct RestrictionRuleLabel: View {
    let name: String
    var allowsWrapping = false

    var body: some View {
        Text(name)
            .lineLimit(allowsWrapping ? 2 : 1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(LiveActivityColor.primary)
            .accessibilityLabel(Text("제한 규칙: \(name)"))
    }
}

private struct RestrictionCountdown: View {
    let endsAt: Date
    var compact = false
    var minimal = false

    var body: some View {
        let now = Date.now
        let interval = now...max(now, endsAt)
        Group {
            if minimal || compact {
                Text(timerInterval: interval, countsDown: true, showsHours: false)
            } else {
                Text(timerInterval: interval, countsDown: true, showsHours: true)
            }
        }
        .multilineTextAlignment(compact ? .leading : .trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .foregroundStyle(LiveActivityColor.accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남은 시간")
        .accessibilityValue(
            Text(timerInterval: interval, countsDown: true, showsHours: true)
        )
    }
}

private struct RestrictionDistanceLabel: View {
    let distance: RestrictionLiveActivityDistance
    var compact = false
    var hasAdditionalRestrictions = false

    var body: some View {
        HStack(spacing: compact ? 3 : 6) {
            if !compact {
                Image(systemName: "location.fill")
                    .foregroundStyle(LiveActivityColor.accent)
                    .accessibilityHidden(true)
            }
            switch distance {
            case .known(let meters):
                if compact {
                    Text("\(meters) m")
                        .monospacedDigit()
                } else {
                    Text("남은 거리 \(meters) m")
                        .monospacedDigit()
                }
            case .unavailable:
                if compact {
                    Text("?")
                        .foregroundStyle(LiveActivityColor.accent)
                } else {
                    Text("거리 확인 불가")
                }
            }
        }
        .foregroundStyle(LiveActivityColor.primary)
        .lineLimit(compact ? 1 : 2)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        switch distance {
        case .known(let meters):
            if compact && hasAdditionalRestrictions {
                Text("\(Text("남은 거리 \(meters)미터")), \(Text("다른 제한도 활성화되어 있어요"))")
            } else {
                Text("남은 거리 \(meters)미터")
            }
        case .unavailable:
            if compact && hasAdditionalRestrictions {
                Text("\(Text("거리 확인 불가")), \(Text("다른 제한도 활성화되어 있어요"))")
            } else {
                Text(compact ? "거리 확인 불가" : "남은 거리 확인 불가")
            }
        }
    }
}

private struct AdditionalRestrictionsLabel: View {
    var body: some View {
        Text("다른 제한 있음")
            .foregroundStyle(LiveActivityColor.secondary)
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("다른 제한도 활성화되어 있어요")
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
    "Lock Screen · Multiple",
    as: .content,
    using: RestrictionLiveActivityPreviewFixtures.attributes
) {
    RestrictionLiveActivity()
} contentStates: {
    RestrictionLiveActivityPreviewFixtures.multipleRestrictions
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
    "Dynamic Island · Compact Multiple",
    as: .dynamicIsland(.compact),
    using: RestrictionLiveActivityPreviewFixtures.attributes
) {
    RestrictionLiveActivity()
} contentStates: {
    RestrictionLiveActivityPreviewFixtures.multipleRestrictions
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
