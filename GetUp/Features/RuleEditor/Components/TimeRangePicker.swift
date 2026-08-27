import Foundation
import SwiftUI

enum TimeRangeBoundary: Hashable, Identifiable, Sendable {
    case start
    case end

    var id: Self { self }
}

struct TimeRangePicker: View {
    @Binding private var startTime: TimeOfDay
    @Binding private var endTime: TimeOfDay
    @State private var selectedHour: Int
    @State private var selectedMinute: Int
    @State private var selectedPeriod: TimePickerPeriod

    private let boundary: TimeRangeBoundary

    init(
        boundary: TimeRangeBoundary,
        startTime: Binding<TimeOfDay>,
        endTime: Binding<TimeOfDay>
    ) {
        self.boundary = boundary
        self._startTime = startTime
        self._endTime = endTime
        let initialTime = boundary == .start ? startTime.wrappedValue : endTime.wrappedValue
        let initialComponents = TimePickerComponents(time: initialTime)
        self._selectedHour = State(initialValue: initialComponents.hour)
        self._selectedMinute = State(initialValue: initialComponents.minute)
        self._selectedPeriod = State(initialValue: initialComponents.period)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                wheelLabels
                    .frame(height: 22)

                HStack(spacing: 0) {
                    wheelPicker(
                        title: AppLocalizedCopy.string("시"),
                        selection: $selectedHour,
                        values: selectableHours,
                        label: String.init,
                        identifier: "hour"
                    )

                    wheelPicker(
                        title: AppLocalizedCopy.string("분"),
                        selection: $selectedMinute,
                        values: selectableMinutes,
                        label: { String(format: "%02d", $0) },
                        identifier: "minute"
                    )

                    wheelPicker(
                        title: AppLocalizedCopy.string("오전 또는 오후"),
                        selection: $selectedPeriod,
                        values: selectablePeriods,
                        label: \.displayName,
                        identifier: "period"
                    )
                }
                .colorScheme(.dark)
                .frame(height: 260)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 322)
            .background(RuleEditorColor.surface, in: .rect(cornerRadius: 28))
            .accessibilityIdentifier("ruleEditor.\(boundary.identifier).pickerCard")

            if boundary == .end {
                Text(minimumDurationMessage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(
                        isEndTimeSelectable
                            ? RuleEditorColor.textSecondary
                            : RuleEditorColor.error
                    )
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ruleEditor.endTime.minimumDuration")
            }
        }
        .onChange(of: selectedHour) { _, _ in updateSelection() }
        .onChange(of: selectedMinute) { _, _ in updateSelection() }
        .onChange(of: selectedPeriod) { _, _ in updateSelection() }
    }

    private var wheelLabels: some View {
        HStack(spacing: 0) {
            Text("시")
                .frame(maxWidth: .infinity)
            Text("분")
                .frame(maxWidth: .infinity)
            Color.clear
                .frame(maxWidth: .infinity)
        }
        .font(.caption2)
        .fontWeight(.bold)
        .foregroundStyle(RuleEditorColor.textTertiary)
        .padding(.horizontal, 16)
        .accessibilityHidden(true)
    }

    private func wheelPicker<Value: Hashable>(
        title: String,
        selection: Binding<Value>,
        values: [Value],
        label: @escaping (Value) -> String,
        identifier: String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(label(value))
                    .font(.title2)
                    .fontWeight(.regular)
                    .foregroundStyle(RuleEditorColor.textPrimary)
                    .tag(value)
            }
        }
        .pickerStyle(.wheel)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .accessibilityLabel(title)
        .accessibilityIdentifier("ruleEditor.\(boundary.identifier).\(identifier)")
    }

    private var minimumDurationMessage: String {
        AppLocalizedCopy.format(
            "%@부터 최소 15분 이후, 12시간 이내만 선택할 수 있어요",
            TimePickerComponents(time: startTime).displayName
        )
    }

    private var isEndTimeSelectable: Bool {
        ScheduleEvaluator.isEndTimeSelectable(startTime: startTime, endTime: endTime)
    }

    private var selectableHours: [Int] {
        Array(1...12)
    }

    private var selectableMinutes: [Int] {
        Array(0...59)
    }

    private var selectablePeriods: [TimePickerPeriod] {
        TimePickerPeriod.allCases
    }

    private func updateSelection() {
        let components = TimePickerComponents(
            time: boundary == .start ? startTime : endTime
        )
        let candidateTime = components.updating(
            hour: selectedHour,
            minute: selectedMinute,
            period: selectedPeriod
        ).time

        switch boundary {
        case .start:
            startTime = candidateTime
            if !ScheduleEvaluator.isEndTimeSelectable(startTime: candidateTime, endTime: endTime) {
                endTime = ScheduleEvaluator.minimumEndTime(startTime: candidateTime)
            }
        case .end:
            endTime = candidateTime
        }
    }
}

enum TimePickerPeriod: String, CaseIterable, Hashable, Sendable {
    case am
    case pm

    var displayName: String {
        rawValue.uppercased()
    }
}

struct TimePickerComponents: Equatable, Sendable {
    var hour: Int
    var minute: Int
    var period: TimePickerPeriod

    init(time: TimeOfDay) {
        hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        minute = time.minute
        period = time.hour < 12 ? .am : .pm
    }

    var time: TimeOfDay {
        let normalizedHour = hour % 12
        return TimeOfDay(
            hour: period == .am ? normalizedHour : normalizedHour + 12,
            minute: minute
        )
    }

    var displayName: String {
        String(format: "%02d:%02d %@", hour, minute, period.displayName)
    }

    func updating(
        hour: Int? = nil,
        minute: Int? = nil,
        period: TimePickerPeriod? = nil
    ) -> Self {
        var updated = self
        updated.hour = hour ?? updated.hour
        updated.minute = minute ?? updated.minute
        updated.period = period ?? updated.period
        return updated
    }
}

enum RuleEditorColor {
    static let background = Color(red: 8 / 255, green: 9 / 255, blue: 11 / 255)
    static let surface = Color(red: 21 / 255, green: 23 / 255, blue: 27 / 255)
    static let surfaceElevated = Color(red: 32 / 255, green: 35 / 255, blue: 41 / 255)
    static let accent = Color.accentColor
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 166 / 255, green: 168 / 255, blue: 173 / 255)
    static let textTertiary = Color(red: 126 / 255, green: 130 / 255, blue: 139 / 255)
    static let error = Color(red: 255 / 255, green: 105 / 255, blue: 97 / 255)
}

extension TimeRangeBoundary {
    var identifier: String {
        switch self {
        case .start:
            "startTime"
        case .end:
            "endTime"
        }
    }
}
