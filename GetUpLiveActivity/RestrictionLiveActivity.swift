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

                DynamicIslandExpandedRegion(.trailing) {
                    RestrictionCountdown(endsAt: context.state.endsAt)
                        .font(.system(size: 17, weight: .bold).monospacedDigit())
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 12) {
                        RestrictionDistanceLabel(distance: context.state.remainingDistance)
                        Spacer(minLength: 0)
                        if context.state.hasAdditionalRestrictions {
                            AdditionalRestrictionsLabel()
                        }
                    }
                    .font(.system(size: 15, weight: .regular))
                    .padding(.top, 12)
                }
            } compactLeading: {
                if context.state.hasAdditionalRestrictions {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 4) {
                            RestrictionDistanceLabel(
                                distance: context.state.remainingDistance,
                                compact: true
                            )
                            AdditionalRestrictionsLabel(compact: true)
                        }
                        RestrictionDistanceLabel(
                            distance: context.state.remainingDistance,
                            compact: true
                        )
                    }
                } else {
                    RestrictionDistanceLabel(
                        distance: context.state.remainingDistance,
                        compact: true
                    )
                }
            } compactTrailing: {
                RestrictionCountdown(endsAt: context.state.endsAt, compact: true)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
                    .frame(maxWidth: 65)
            } minimal: {
                RestrictionCountdown(endsAt: context.state.endsAt, compact: true)
                    .font(.system(size: 12, weight: .bold).monospacedDigit())
            }
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
            if dynamicTypeSize.isAccessibilitySize {
                RestrictionRuleLabel(name: contentState.ruleDisplayName)
                    .font(.system(size: ruleSize, weight: .semibold))
                RestrictionCountdown(endsAt: contentState.endsAt)
                    .font(.system(size: timeSize, weight: .bold).monospacedDigit())
                RestrictionDistanceLabel(distance: contentState.remainingDistance)
                    .font(.system(size: detailSize, weight: .semibold))
                if contentState.hasAdditionalRestrictions {
                    AdditionalRestrictionsLabel()
                        .font(.system(size: detailSize, weight: .semibold))
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    RestrictionRuleLabel(name: contentState.ruleDisplayName)
                        .font(.system(size: ruleSize, weight: .semibold))
                    Spacer(minLength: 0)
                    RestrictionCountdown(endsAt: contentState.endsAt)
                        .font(.system(size: timeSize, weight: .bold).monospacedDigit())
                }
                HStack(spacing: 12) {
                    RestrictionDistanceLabel(distance: contentState.remainingDistance)
                    Spacer(minLength: 0)
                    if contentState.hasAdditionalRestrictions {
                        AdditionalRestrictionsLabel()
                    }
                }
                .font(.system(size: detailSize))
            }
        }
        .foregroundStyle(LiveActivityColor.primary)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LiveActivityColor.surface,
            in: RoundedRectangle(cornerRadius: dynamicTypeSize.isAccessibilitySize ? 28 : 18)
        )
    }
}

private struct RestrictionRuleLabel: View {
    let name: String

    var body: some View {
        Text(name)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(LiveActivityColor.primary)
            .accessibilityLabel(Text("제한 규칙: \(name)"))
    }
}

private struct RestrictionCountdown: View {
    let endsAt: Date
    var compact = false

    @Environment(\.locale) private var locale

    var body: some View {
        let now = Date.now
        let interval = now...max(now, endsAt)
        Group {
            if compact {
                Text(
                    .currentDate,
                    format: CompactMinuteTimerStyle(
                        startedAt: now,
                        endsAt: endsAt,
                        languageCode: locale.language.languageCode?.identifier ?? "ko"
                    )
                )
            } else {
                Text(timerInterval: interval, countsDown: true, showsHours: true)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.72)
        .foregroundStyle(LiveActivityColor.primary)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("남은 시간")
        .accessibilityValue(
            Text(timerInterval: interval, countsDown: true, showsHours: true)
        )
    }
}

/// Keeps the system timer's minute update schedule while using the approved short units.
private struct CompactMinuteTimerStyle: DiscreteFormatStyle {
    let startedAt: Date
    let endsAt: Date
    let languageCode: String

    private var systemStyle: SystemFormatStyle.Timer {
        SystemFormatStyle.Timer(
            countingDownIn: startedAt..<max(startedAt.addingTimeInterval(1), endsAt),
            showsHours: false,
            maxFieldCount: 1,
            maxPrecision: .seconds(60)
        )
    }

    func format(_ value: Date) -> String {
        let minutes = max(0, Int(ceil(endsAt.timeIntervalSince(value) / 60)))
        return languageCode == "ko" ? "\(minutes)분" : "\(minutes) min"
    }

    func discreteInput(before input: Date) -> Date? {
        systemStyle.discreteInput(before: input)
    }

    func discreteInput(after input: Date) -> Date? {
        systemStyle.discreteInput(after: input)
    }
}

private struct RestrictionDistanceLabel: View {
    let distance: RestrictionLiveActivityDistance
    var compact = false

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
        .lineLimit(1)
        .minimumScaleFactor(0.75)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: Text {
        switch distance {
        case .known(let meters):
            Text("남은 거리 \(meters)미터")
        case .unavailable:
            Text(compact ? "거리 확인 불가" : "남은 거리 확인 불가")
        }
    }
}

private struct AdditionalRestrictionsLabel: View {
    var compact = false

    var body: some View {
        Group {
            if compact {
                Text("+")
            } else {
                Text("다른 제한 있음")
            }
        }
        .foregroundStyle(LiveActivityColor.secondary)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("다른 제한 있음")
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
