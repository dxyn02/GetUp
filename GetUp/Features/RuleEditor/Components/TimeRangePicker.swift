import Foundation
import SwiftUI

enum TimeRangeBoundary: Equatable, Sendable {
    case start
    case end
}

struct TimeRangePicker: View {
    @Binding private var startTime: TimeOfDay
    @Binding private var endTime: TimeOfDay

    private let boundary: TimeRangeBoundary

    init(
        boundary: TimeRangeBoundary,
        startTime: Binding<TimeOfDay>,
        endTime: Binding<TimeOfDay>
    ) {
        self.boundary = boundary
        self._startTime = startTime
        self._endTime = endTime
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            wheelLabels

            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(RuleEditorColor.accent)
                    .frame(height: 58)
                    .accessibilityHidden(true)

                HStack(spacing: 0) {
                    wheelPicker(
                        title: "시",
                        selection: hourSelection,
                        values: Array(1...12),
                        label: String.init,
                        isSelectable: { canSelect(hour: $0) },
                        identifier: "hour"
                    )

                    wheelPicker(
                        title: "분",
                        selection: minuteSelection,
                        values: Array(0...59),
                        label: { String(format: "%02d", $0) },
                        isSelectable: { canSelect(minute: $0) },
                        identifier: "minute"
                    )

                    wheelPicker(
                        title: "오전 또는 오후",
                        selection: periodSelection,
                        values: TimePickerPeriod.allCases,
                        label: \.displayName,
                        isSelectable: { canSelect(period: $0) },
                        identifier: "period"
                    )
                }
                .colorScheme(.dark)
            }
            .frame(maxWidth: .infinity, minHeight: 300)
            .padding(.horizontal, 16)
            .background(RuleEditorColor.surface, in: .rect(cornerRadius: 28))

            if boundary == .end {
                Text(minimumDurationMessage)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(RuleEditorColor.error)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("ruleEditor.endTime.minimumDuration")
            }
        }
    }

    private var wheelLabels: some View {
        HStack(spacing: 0) {
            Text("시")
                .frame(maxWidth: .infinity)
            Text("분")
                .frame(maxWidth: .infinity)
            Text("AM/PM")
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
        isSelectable: @escaping (Value) -> Bool,
        identifier: String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(label(value))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .tag(value)
                    .disabled(!isSelectable(value))
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
        .accessibilityLabel(title)
        .accessibilityIdentifier("ruleEditor.\(boundary.identifier).\(identifier)")
    }

    private var hourSelection: Binding<Int> {
        Binding(
            get: { components.hour },
            set: { updateSelection(hour: $0) }
        )
    }

    private var minuteSelection: Binding<Int> {
        Binding(
            get: { components.minute },
            set: { updateSelection(minute: $0) }
        )
    }

    private var periodSelection: Binding<TimePickerPeriod> {
        Binding(
            get: { components.period },
            set: { updateSelection(period: $0) }
        )
    }

    private var selectedTime: TimeOfDay {
        boundary == .start ? startTime : endTime
    }

    private var components: TimePickerComponents {
        TimePickerComponents(time: selectedTime)
    }

    private var minimumDurationMessage: String {
        "\(TimePickerComponents(time: startTime).displayName)부터 최소 15분 이후만 선택할 수 있어요"
    }

    private func canSelect(
        hour: Int? = nil,
        minute: Int? = nil,
        period: TimePickerPeriod? = nil
    ) -> Bool {
        guard boundary == .end else {
            return true
        }

        return ScheduleEvaluator.isEndTimeSelectable(
            startTime: startTime,
            endTime: candidateTime(hour: hour, minute: minute, period: period)
        )
    }

    private func updateSelection(
        hour: Int? = nil,
        minute: Int? = nil,
        period: TimePickerPeriod? = nil
    ) {
        let candidateTime = candidateTime(hour: hour, minute: minute, period: period)
        guard boundary == .start || ScheduleEvaluator.isEndTimeSelectable(
            startTime: startTime,
            endTime: candidateTime
        ) else {
            return
        }

        switch boundary {
        case .start:
            startTime = candidateTime
        case .end:
            endTime = candidateTime
        }
    }

    private func candidateTime(
        hour: Int?,
        minute: Int?,
        period: TimePickerPeriod?
    ) -> TimeOfDay {
        var candidate = components
        candidate.hour = hour ?? candidate.hour
        candidate.minute = minute ?? candidate.minute
        candidate.period = period ?? candidate.period
        return candidate.time
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

private extension TimeRangeBoundary {
    var identifier: String {
        switch self {
        case .start:
            "startTime"
        case .end:
            "endTime"
        }
    }
}
