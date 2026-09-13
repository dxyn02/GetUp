import SwiftUI

struct RestrictionLockScreenView: View {
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
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("liveActivity.preview")
    }
}

struct RestrictionRuleLabel: View {
    let name: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock.fill")
                .foregroundStyle(.mint)
                .accessibilityHidden(true)

            Text(name)
                .font(.headline)
                .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("제한 규칙: \(name)"))
        .accessibilityIdentifier("liveActivity.rule")
    }
}

struct RestrictionCountdown: View {
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
        .accessibilityElement()
        .accessibilityLabel("남은 시간")
        .accessibilityValue(
            Text(
                timerInterval: now...max(now, endsAt),
                countsDown: true,
                showsHours: true
            )
        )
        .accessibilityIdentifier("liveActivity.countdown")
    }
}

struct RestrictionDistanceLabel: View {
    let distance: RestrictionLiveActivityDistance
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 3 : 6) {
            Image(systemName: "location.fill")
                .foregroundStyle(.mint)
                .accessibilityHidden(true)

            switch distance {
            case .known(let meters):
                Text("\(meters) m")
                    .monospacedDigit()
            case .unavailable:
                if compact {
                    Image(systemName: "questionmark")
                        .accessibilityHidden(true)
                } else {
                    Text("거리 확인 불가")
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("liveActivity.distance")
    }

    private var accessibilityLabel: Text {
        switch distance {
        case .known(let meters):
            Text("남은 거리 \(meters)미터")
        case .unavailable:
            Text("남은 거리 확인 불가")
        }
    }
}

struct AdditionalRestrictionsLabel: View {
    var body: some View {
        Label("추가 제한 있음", systemImage: "square.stack.3d.up.fill")
            .lineLimit(1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("다른 제한도 활성화되어 있어요")
            .accessibilityIdentifier("liveActivity.additionalRestrictions")
    }
}
