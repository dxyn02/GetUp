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
                        values: selectableHours,
                        label: String.init,
                        identifier: "hour"
                    )

                    wheelPicker(
                        title: "분",
                        selection: minuteSelection,
                        values: selectableMinutes,
                        label: { String(format: "%02d", $0) },
                        identifier: "minute"
                    )

                    wheelPicker(
                        title: "오전 또는 오후",
                        selection: periodSelection,
                        values: selectablePeriods,
                        label: \.displayName,
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
        identifier: String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(values, id: \.self) { value in
                Text(label(value))
                    .font(.title2)
                    .fontWeight(.semibold)
                    .tag(value)
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
        "\(TimePickerComponents(time: startTime).displayName)부터 15분 이상, 12시간 이내만 선택할 수 있어요"
    }

    private var selectableEndTimes: [TimeOfDay] {
        ScheduleEvaluator.selectableEndTimes(startTime: startTime)
    }

    private var selectableHours: [Int] {
        guard boundary == .end else { return Array(1...12) }
        let period = components.period
        let hours = Set(selectableEndTimes.compactMap { time -> Int? in
            let candidate = TimePickerComponents(time: time)
            return candidate.period == period ? candidate.hour : nil
        })
        return Array(1...12).filter(hours.contains)
    }

    private var selectableMinutes: [Int] {
        guard boundary == .end else { return Array(0...59) }
        let current = components
        let minutes = Set(selectableEndTimes.compactMap { time -> Int? in
            let candidate = TimePickerComponents(time: time)
            return candidate.hour == current.hour && candidate.period == current.period
                ? candidate.minute
                : nil
        })
        return Array(0...59).filter(minutes.contains)
    }

    private var selectablePeriods: [TimePickerPeriod] {
        guard boundary == .end else { return TimePickerPeriod.allCases }
        let periods = Set(selectableEndTimes.map { TimePickerComponents(time: $0).period })
        return TimePickerPeriod.allCases.filter(periods.contains)
    }

    private func updateSelection(
        hour: Int? = nil,
        minute: Int? = nil,
        period: TimePickerPeriod? = nil
    ) {
        let candidateTime = candidateTime(hour: hour, minute: minute, period: period)

        switch boundary {
        case .start:
            startTime = candidateTime
            if !ScheduleEvaluator.isEndTimeSelectable(startTime: candidateTime, endTime: endTime) {
                endTime = ScheduleEvaluator.minimumEndTime(startTime: candidateTime)
            }
        case .end:
            let matching = selectableEndTimes.filter { time in
                let value = TimePickerComponents(time: time)
                return (hour == nil || value.hour == hour)
                    && (minute == nil || value.minute == minute)
                    && (period == nil || value.period == period)
            }
            if let nearest = matching.min(by: { clockDistance($0, endTime) < clockDistance($1, endTime) }) {
                endTime = nearest
            }
        }
    }

    private func clockDistance(_ lhs: TimeOfDay, _ rhs: TimeOfDay) -> Int {
        let left = lhs.hour * 60 + lhs.minute
        let right = rhs.hour * 60 + rhs.minute
        let distance = abs(left - right)
        return min(distance, 24 * 60 - distance)
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
