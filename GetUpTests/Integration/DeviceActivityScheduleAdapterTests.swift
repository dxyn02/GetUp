@preconcurrency import DeviceActivity
import Foundation
import Testing
@testable import GetUp

@MainActor
@Suite("Device activity schedule adapter")
struct DeviceActivityScheduleAdapterTests {
    @Test("A repeating schedule is registered for every selected weekday")
    func registersEverySelectedWeekday() async throws {
        let center = FakeDeviceActivityScheduling()
        let adapter = DeviceActivityScheduleAdapter(center: center)
        let rule = TestFixtures.makeRule(
            weekdays: [.monday, .wednesday, .friday],
            startTime: TimeOfDay(hour: 6, minute: 15),
            endTime: TimeOfDay(hour: 9, minute: 45)
        )

        try await adapter.replaceSchedules(for: rule)

        let registrations = center.registrations
        #expect(registrations.count == 3)
        #expect(Set(registrations.map(\.activity.rawValue)) == Set([
            activityName(ruleID: rule.id, weekday: .monday).rawValue,
            activityName(ruleID: rule.id, weekday: .wednesday).rawValue,
            activityName(ruleID: rule.id, weekday: .friday).rawValue,
        ]))
        #expect(Set(registrations.compactMap(\.schedule.intervalStart.weekday)) == [2, 4, 6])
        #expect(registrations.allSatisfy { registration in
            registration.schedule.intervalStart.hour == 6
                && registration.schedule.intervalStart.minute == 15
                && registration.schedule.intervalEnd.hour == 9
                && registration.schedule.intervalEnd.minute == 45
                && registration.schedule.intervalEnd.weekday
                    == registration.schedule.intervalStart.weekday
                && registration.schedule.repeats
        })
    }

    @Test("A 14-minute interval is rejected before existing schedules are changed")
    func rejectsIntervalShorterThanFifteenMinutes() async {
        let existing = activityName(
            ruleID: TestFixtures.makeRule().id,
            weekday: .monday
        )
        let center = FakeDeviceActivityScheduling(monitoredActivities: [existing])
        let adapter = DeviceActivityScheduleAdapter(center: center)
        let rule = TestFixtures.makeRule(
            startTime: TimeOfDay(hour: 6, minute: 0),
            endTime: TimeOfDay(hour: 6, minute: 14)
        )

        await #expect(throws: DeviceActivityScheduleAdapterError.intervalTooShort) {
            try await adapter.replaceSchedules(for: rule)
        }

        #expect(center.registrations.isEmpty)
        #expect(center.stoppedActivities.isEmpty)
        #expect(center.monitoredActivities() == [existing])
    }

    @Test("A cross-midnight schedule ends on the following weekday")
    func crossMidnightEndsOnFollowingWeekday() async throws {
        let center = FakeDeviceActivityScheduling()
        let adapter = DeviceActivityScheduleAdapter(center: center)
        let rule = TestFixtures.makeRule(
            weekdays: [.sunday],
            startTime: TimeOfDay(hour: 23, minute: 30),
            endTime: TimeOfDay(hour: 6, minute: 0)
        )

        try await adapter.replaceSchedules(for: rule)

        let registration = try #require(center.registrations.first)
        #expect(registration.schedule.intervalStart.weekday == 1)
        #expect(registration.schedule.intervalStart.hour == 23)
        #expect(registration.schedule.intervalStart.minute == 30)
        #expect(registration.schedule.intervalEnd.weekday == 2)
        #expect(registration.schedule.intervalEnd.hour == 6)
        #expect(registration.schedule.intervalEnd.minute == 0)
        #expect(registration.schedule.repeats)
    }

    @Test("Replacing a rule removes only that rule's prior weekday schedules")
    func replacesOnlyTheTargetRulesExistingSchedules() async throws {
        let rule = TestFixtures.makeRule(
            weekdays: [.monday, .wednesday],
            startTime: TimeOfDay(hour: 7, minute: 0),
            endTime: TimeOfDay(hour: 8, minute: 0)
        )
        let oldMonday = activityName(ruleID: rule.id, weekday: .monday)
        let oldTuesday = activityName(ruleID: rule.id, weekday: .tuesday)
        let otherRule = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
        )
        let otherActivity = activityName(ruleID: otherRule.id, weekday: .monday)
        let center = FakeDeviceActivityScheduling(
            monitoredActivities: [oldMonday, oldTuesday, otherActivity]
        )
        let adapter = DeviceActivityScheduleAdapter(center: center)

        try await adapter.replaceSchedules(for: rule)

        #expect(Set(center.stoppedActivities) == [oldMonday, oldTuesday])
        #expect(Set(center.monitoredActivities()) == Set([
            otherActivity,
            activityName(ruleID: rule.id, weekday: .monday),
            activityName(ruleID: rule.id, weekday: .wednesday),
        ]))
    }

    private func activityName(
        ruleID: UUID,
        weekday: Weekday
    ) -> DeviceActivityName {
        DeviceActivityName(
            "\(SharedIdentifiers.deviceActivityNamePrefix)."
                + "\(ruleID.uuidString.lowercased()).\(weekday.rawValue)"
        )
    }
}

@MainActor
private final class FakeDeviceActivityScheduling: DeviceActivityScheduling {
    struct Registration {
        let activity: DeviceActivityName
        let schedule: DeviceActivitySchedule
    }

    private var monitored: Set<DeviceActivityName>
    private(set) var registrations: [Registration] = []
    private(set) var stoppedActivities: [DeviceActivityName] = []

    init(monitoredActivities: Set<DeviceActivityName> = []) {
        monitored = monitoredActivities
    }

    func monitoredActivities() -> [DeviceActivityName] {
        Array(monitored)
    }

    func startMonitoring(
        _ activity: DeviceActivityName,
        during schedule: DeviceActivitySchedule
    ) throws {
        registrations.append(
            Registration(activity: activity, schedule: schedule)
        )
        monitored.insert(activity)
    }

    func stopMonitoring(_ activities: [DeviceActivityName]) {
        stoppedActivities.append(contentsOf: activities)
        monitored.subtract(activities)
    }
}
