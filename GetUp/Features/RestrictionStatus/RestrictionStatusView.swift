import SwiftUI

struct RestrictionStatusView: View {
    let item: HomeRuleItem
    let rulePosition: Int
    let ruleCount: Int

    @State private var isGuardAlertPresented = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(RestrictionCopy.activeStatus)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(HomeColor.accent)
                .accessibilityIdentifier("restrictionStatus.active")

            Text(item.rule.name ?? displayPlaceName)
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                Text("RULE \(rulePosition) OF \(ruleCount) · \(weekdayLabel)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(HomeColor.textTertiary)
                    .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID).schedule")

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
                        Text("\(displayPlaceName)에서 \(radiusLabel) 밖으로 나서면")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(item.applicationReleaseDescription)
                            .font(.subheadline)
                            .foregroundStyle(HomeColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                conditionRow(
                    label: "LOCATION",
                    value: "\(displayPlaceName) · \(radiusLabel)",
                    identifier: "home.ruleCard.\(item.accessibilityID).location"
                )
                conditionRow(
                    label: "BLOCKED",
                    value: item.applicationSummary,
                    identifier: "home.ruleCard.\(item.accessibilityID).applications"
                )
                Spacer(minLength: 0)

                Button {
                    isGuardAlertPresented = true
                } label: {
                    Text(RestrictionCopy.editDisabled)
                        .font(.footnote)
                        .fontWeight(.semibold)
                        .foregroundStyle(HomeColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 14))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(RestrictionCopy.editDisabled)
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
            Text(RestrictionCopy.guardTitle),
            isPresented: $isGuardAlertPresented
        ) {
            Button(RestrictionCopy.guardConfirm, role: .cancel) {}
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

    private var displayPlaceName: String {
        AppLocalizedCopy.savedPlaceName(item.savedPlace.name)
    }

    private var modificationGuard: RestrictionModificationGuard {
        RestrictionModificationGuard(
            savedPlaceName: displayPlaceName,
            radius: item.rule.radius,
            endTime: item.rule.endTime
        )
    }

    private var weekdayLabel: String {
        HomeWeekdayFormatter.label(for: item.rule.weekdays)
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

extension HomeRuleItem {
    var restrictionSelectionSummary: RestrictionSelectionSummary {
        rule.activitySelection.restrictionSelectionSummary(
            countedTargets: applicationCount
        )
    }

    var applicationSummary: String {
        switch restrictionSelectionSummary {
        case .none:
            AppLocalizedCopy.string("앱 없음")
        case .exact(let count):
            count == 1
                ? AppLocalizedCopy.string("1개 앱")
                : AppLocalizedCopy.format("%@개 앱", String(count))
        case .multiple:
            AppLocalizedCopy.string("여러 앱")
        }
    }

    var applicationReleaseDescription: String {
        switch restrictionSelectionSummary {
        case .none:
            AppLocalizedCopy.string("선택한 앱이 없어요")
        case .exact(let count):
            count == 1
                ? AppLocalizedCopy.string("선택한 앱 1개를\n다시 사용할 수 있어요")
                : AppLocalizedCopy.format(
                    "선택한 앱 %@개를\n다시 사용할 수 있어요",
                    String(count)
                )
        case .multiple:
            AppLocalizedCopy.string("선택한 여러 앱을\n다시 사용할 수 있어요")
        }
    }
}

enum HomeWeekdayFormatter {
    static func label(for weekdays: Set<Weekday>) -> String {
        var runs: [[Weekday]] = []
        var currentRun: [Weekday] = []

        for weekday in Weekday.allCases {
            if weekdays.contains(weekday) {
                currentRun.append(weekday)
            } else if !currentRun.isEmpty {
                runs.append(currentRun)
                currentRun = []
            }
        }

        if !currentRun.isEmpty {
            runs.append(currentRun)
        }

        return runs.map { run in
            guard let first = run.first else { return "" }
            guard run.count > 1, let last = run.last else {
                return first.shortEnglishName
            }
            return "\(first.shortEnglishName)-\(last.shortEnglishName)"
        }
        .joined(separator: " · ")
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
