import SwiftUI

struct RestrictionStatusView: View {
    let item: HomeRuleItem
    let rulePosition: Int
    let ruleCount: Int

    @State private var isGuardAlertPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("restriction_status.active")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(HomeColor.accent)
                .accessibilityIdentifier("restrictionStatus.active")

            Text(item.rule.name ?? item.savedPlace.name)
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                Text("RULE \(rulePosition) OF \(ruleCount) · \(weekdayLabel)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(HomeColor.textTertiary)

                timeText
                    .fixedSize(horizontal: false, vertical: true)

                Divider().overlay(HomeColor.disabled)

                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "door.left.hand.open")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(HomeColor.accent)
                        .frame(width: 78, height: 78)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(item.savedPlace.name)에서 \(radiusLabel) 나가면")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("선택한 앱 \(item.applicationCount)개를\n다시 사용할 수 있어요")
                            .font(.subheadline)
                            .foregroundStyle(HomeColor.textSecondary)
                    }
                }

                conditionRow(
                    label: "LOCATION",
                    value: "\(item.savedPlace.name) · \(radiusLabel)",
                    identifier: "home.ruleCard.\(item.accessibilityID).location"
                )
                conditionRow(
                    label: "BLOCKED",
                    value: "\(item.applicationCount)개 앱",
                    identifier: "home.ruleCard.\(item.accessibilityID).applications"
                )
                Spacer(minLength: 0)

                Button {
                    isGuardAlertPresented = true
                } label: {
                    Text("restriction_status.edit_disabled")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(HomeColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("restriction_status.edit_disabled"))
                .accessibilityHint("수정할 수 있는 위치와 시간을 안내합니다.")
                .accessibilityIdentifier("restrictionStatus.editDisabled")
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 456, alignment: .topLeading)
            .background(HomeColor.surface, in: .rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(HomeColor.accent, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID)")
        .alert(
            Text("restriction_guard.title"),
            isPresented: $isGuardAlertPresented
        ) {
            Button("restriction_guard.confirm", role: .cancel) {}
        } message: {
            Text(modificationGuard.message)
        }
    }

    private func conditionRow(
        label: String,
        value: String,
        identifier: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: label == "LOCATION" ? "scope" : "square.grid.3x3.fill")
                .foregroundStyle(HomeColor.accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption2).fontWeight(.bold).foregroundStyle(HomeColor.textTertiary)
                Text(value).font(.subheadline).fontWeight(.bold).accessibilityIdentifier(identifier)
            }
            Spacer()
        }
        .frame(minHeight: 54)
    }

    private var radiusLabel: String {
        RadiusPicker.displayName(for: item.rule.radius)
    }

    private var modificationGuard: RestrictionModificationGuard {
        RestrictionModificationGuard(
            savedPlaceName: item.savedPlace.name,
            radius: item.rule.radius,
            endTime: item.rule.endTime
        )
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

    private var timeText: Text {
        Text(
            "\(Text(Self.clock(item.rule.startTime)).font(.system(size: 38, weight: .bold))) \(Text(Self.period(item.rule.startTime)).font(.caption).foregroundColor(HomeColor.textSecondary)) \(Text("→").font(.title2).foregroundColor(HomeColor.accent)) \(Text(Self.clock(item.rule.endTime)).font(.system(size: 38, weight: .bold))) \(Text(Self.period(item.rule.endTime)).font(.caption).foregroundColor(HomeColor.textSecondary))"
        )
    }

    private static func clock(_ time: TimeOfDay) -> String {
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        return String(format: "%02d:%02d", hour, time.minute)
    }

    private static func period(_ time: TimeOfDay) -> String { time.hour < 12 ? "AM" : "PM" }
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
