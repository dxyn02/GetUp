import SwiftUI

struct RestrictionStatusView: View {
    let item: HomeRuleItem
    let rulePosition: Int
    let ruleCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("RESTRICTION ACTIVE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(HomeColor.accent)
                    .accessibilityIdentifier("restrictionStatus.active")

                Text(item.rule.name ?? item.savedPlace.name)
                    .font(.title)
                    .fontWeight(.bold)
            }

            Text("RULE \(rulePosition) OF \(ruleCount) · \(weekdayLabel)")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(HomeColor.textSecondary)

            Text("\(Self.time(item.rule.startTime)) → \(Self.time(item.rule.endTime))")
                .font(.title2)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)

            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 29, weight: .light))
                    .foregroundStyle(HomeColor.accent)
                    .frame(width: 42, height: 42)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.savedPlace.name)에서 \(radiusLabel) 나가면")
                        .font(.headline)
                    Text("선택한 앱 \(item.applicationCount)개를 다시 사용할 수 있어요")
                        .font(.subheadline)
                        .foregroundStyle(HomeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: 0) {
                conditionRow(
                    label: "LOCATION",
                    value: "\(item.savedPlace.name) · \(radiusLabel)",
                    identifier: "home.ruleCard.\(item.accessibilityID).location"
                )
                Divider().overlay(HomeColor.surfaceElevated)
                conditionRow(
                    label: "BLOCKED",
                    value: "\(item.applicationCount)개 앱",
                    identifier: "home.ruleCard.\(item.accessibilityID).applications"
                )
            }
            .background(HomeColor.surfaceElevated.opacity(0.52), in: .rect(cornerRadius: 18))

            Label("조건 종료 후 수정 가능", systemImage: "lock.fill")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundStyle(HomeColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(HomeColor.surfaceElevated.opacity(0.42), in: .rect(cornerRadius: 14))
                .accessibilityIdentifier("restrictionStatus.editDisabled")
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 410, alignment: .topLeading)
        .background(HomeColor.surface, in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(HomeColor.accent, lineWidth: 2)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID)")
    }

    private func conditionRow(
        label: String,
        value: String,
        identifier: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(HomeColor.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.body)
                .fontWeight(.semibold)
                .accessibilityIdentifier(identifier)
            Spacer()
        }
        .frame(minHeight: 50)
        .padding(.horizontal, 14)
    }

    private var radiusLabel: String {
        RadiusPicker.displayName(for: item.rule.radius)
    }

    private var weekdayLabel: String {
        let weekdays = item.rule.weekdays
        if weekdays == Set([.monday, .tuesday, .wednesday, .thursday, .friday]) {
            return "MON–FRI"
        }
        return Weekday.allCases
            .filter(weekdays.contains)
            .map(\.shortEnglishName)
            .joined(separator: " · ")
    }

    private static func time(_ time: TimeOfDay) -> String {
        let period = time.hour < 12 ? "AM" : "PM"
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        return String(format: "%02d:%02d %@", hour, time.minute, period)
    }
}

private extension Weekday {
    var shortEnglishName: String {
        switch self {
        case .monday: "MON"
        case .tuesday: "TUE"
        case .wednesday: "WED"
        case .thursday: "THU"
        case .friday: "FRI"
        case .saturday: "SAT"
        case .sunday: "SUN"
        }
    }
}
