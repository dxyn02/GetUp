import SwiftUI

struct WeekdayPicker: View {
    @Binding private var selection: Set<Weekday>

    init(selection: Binding<Set<Weekday>>) {
        self._selection = selection
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 7) {
                ForEach(Weekday.allCases, id: \.self) { weekday in
                    weekdayButton(weekday)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("반복 요일")
    }

    private func weekdayButton(_ weekday: Weekday) -> some View {
        let isSelected = selection.contains(weekday)

        return Button {
            if isSelected {
                selection.remove(weekday)
            } else {
                selection.insert(weekday)
            }
        } label: {
            Text(weekday.shortName)
                .font(.subheadline)
                .fontWeight(.bold)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background(
                    isSelected ? RuleEditorColor.accent : RuleEditorColor.surfaceElevated,
                    in: .circle
                )
                .foregroundStyle(
                    isSelected ? RuleEditorColor.background : RuleEditorColor.textSecondary
                )
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .accessibilityLabel(weekday.fullName)
        .accessibilityValue(
            isSelected
                ? AppLocalizedCopy.string("선택됨")
                : AppLocalizedCopy.string("선택 안 됨")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(
            isSelected
                ? AppLocalizedCopy.string("반복 요일에서 제외합니다.")
                : AppLocalizedCopy.string("반복 요일에 추가합니다.")
        )
        .accessibilityIdentifier("ruleEditor.weekday.\(weekday.rawValue)")
    }
}

private extension Weekday {
    var shortName: String {
        switch self {
        case .monday: "M"
        case .tuesday: "T"
        case .wednesday: "W"
        case .thursday: "T"
        case .friday: "F"
        case .saturday: "S"
        case .sunday: "S"
        }
    }

    var fullName: String {
        switch self {
        case .monday: AppLocalizedCopy.string("월요일")
        case .tuesday: AppLocalizedCopy.string("화요일")
        case .wednesday: AppLocalizedCopy.string("수요일")
        case .thursday: AppLocalizedCopy.string("목요일")
        case .friday: AppLocalizedCopy.string("금요일")
        case .saturday: AppLocalizedCopy.string("토요일")
        case .sunday: AppLocalizedCopy.string("일요일")
        }
    }
}
