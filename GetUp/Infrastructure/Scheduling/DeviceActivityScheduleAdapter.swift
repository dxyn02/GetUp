@preconcurrency import DeviceActivity
import Foundation

enum DeviceActivityScheduleAdapterError: Error, Equatable, Sendable {
    case intervalTooShort
}

@MainActor
protocol DeviceActivityScheduling {
    func monitoredActivities() -> [DeviceActivityName]
    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule
    ) throws
    func stopMonitoring(_ activities: [DeviceActivityName])
}

@MainActor
struct SystemDeviceActivityScheduler: DeviceActivityScheduling {
    private let center: DeviceActivityCenter

    init(center: DeviceActivityCenter = DeviceActivityCenter()) {
        self.center = center
    }

    func monitoredActivities() -> [DeviceActivityName] {
        center.activities
    }

    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule
    ) throws {
        try center.startMonitoring(activity, during: schedule)
    }

    func stopMonitoring(_ activities: [DeviceActivityName]) {
        center.stopMonitoring(activities)
    }
}

@MainActor
final class DeviceActivityScheduleAdapter: ScheduleManaging {
    private struct Registration {
        let activity: DeviceActivityName
        let schedule: DeviceActivitySchedule
    }

    private let center: any DeviceActivityScheduling

    init(
        center: any DeviceActivityScheduling = SystemDeviceActivityScheduler()
    ) {
        self.center = center
    }

    func replaceSchedules(for rule: RestrictionRuleSnapshot) async throws {
        let registrations = try registrations(for: rule)
        let rulePrefix = activityNamePrefix(for: rule.id)
        let existingActivities = center.monitoredActivities().filter {
            $0.rawValue.hasPrefix(rulePrefix)
        }

        if !existingActivities.isEmpty {
            center.stopMonitoring(existingActivities)
        }

        for registration in registrations {
            try center.startMonitoring(
                registration.activity,
                during: registration.schedule
            )
        }
    }

    func removeSchedules() async throws {
        let getUpPrefix = "\(SharedIdentifiers.deviceActivityNamePrefix)."
        let activities = center.monitoredActivities().filter {
            $0.rawValue.hasPrefix(getUpPrefix)
        }

        if !activities.isEmpty {
            center.stopMonitoring(activities)
        }
    }

    private func registrations(
        for rule: RestrictionRuleSnapshot
    ) throws -> [Registration] {
        let startMinutes = rule.startTime.hour * 60 + rule.startTime.minute
        let endMinutes = rule.endTime.hour * 60 + rule.endTime.minute
        let duration = (endMinutes - startMinutes + 24 * 60) % (24 * 60)

        guard duration >= 15 else {
            throw DeviceActivityScheduleAdapterError.intervalTooShort
        }

        let crossesMidnight = endMinutes < startMinutes

        return Weekday.allCases.compactMap { weekday in
            guard rule.weekdays.contains(weekday) else {
                return nil
            }

            let startWeekday = calendarWeekday(for: weekday)
            let endWeekday = crossesMidnight
                ? nextCalendarWeekday(after: startWeekday)
                : startWeekday
            let schedule = DeviceActivitySchedule(
                intervalStart: DateComponents(
                    hour: rule.startTime.hour,
                    minute: rule.startTime.minute,
                    weekday: startWeekday
                ),
                intervalEnd: DateComponents(
                    hour: rule.endTime.hour,
                    minute: rule.endTime.minute,
                    weekday: endWeekday
                ),
                repeats: true
            )

            return Registration(
                activity: DeviceActivityName(
                    "\(activityNamePrefix(for: rule.id))\(weekday.rawValue)"
                ),
                schedule: schedule
            )
        }
    }

    private func activityNamePrefix(for ruleID: UUID) -> String {
        "\(SharedIdentifiers.deviceActivityNamePrefix)."
            + "\(ruleID.uuidString.lowercased())."
    }

    private func calendarWeekday(for weekday: Weekday) -> Int {
        switch weekday {
        case .sunday:
            1
        case .monday:
            2
        case .tuesday:
            3
        case .wednesday:
            4
        case .thursday:
            5
        case .friday:
            6
        case .saturday:
            7
        }
    }

    private func nextCalendarWeekday(after weekday: Int) -> Int {
        weekday == 7 ? 1 : weekday + 1
    }
}
