import FamilyControls
import Foundation
import Testing
@testable import GetUp

@Suite("Restriction status model")
struct RestrictionStatusModelTests {
    @Test("Only the exact active rule revision is shown as active")
    func matchesActiveRuleRevision() {
        let rule = makeRule(revision: 3)
        let model = RestrictionStatusModel(
            appliedState: AppliedRestrictionState(
                activeRuleRevisions: [
                    ActiveRuleRevision(ruleID: rule.id, revision: rule.revision),
                ]
            )
        )

        #expect(model.isActive(rule))
        #expect(!model.isActive(makeRule(revision: 2)))
    }

    @Test("An empty applied state keeps every rule inactive")
    func emptyStateIsInactive() {
        let model = RestrictionStatusModel()

        #expect(!model.hasActiveRestriction)
        #expect(!model.isActive(makeRule(revision: 1)))
    }

    @Test("Home weekday labels collapse every consecutive run")
    func homeWeekdayLabelsCollapseConsecutiveRuns() {
        #expect(
            HomeWeekdayFormatter.label(
                for: [.monday, .tuesday, .wednesday, .thursday, .friday]
            ) == "MON-FRI"
        )
        #expect(HomeWeekdayFormatter.label(for: Set(Weekday.allCases)) == "MON-SUN")
        #expect(HomeWeekdayFormatter.label(for: [.saturday, .sunday]) == "SAT-SUN")
        #expect(
            HomeWeekdayFormatter.label(for: [.wednesday, .thursday, .friday]) == "WED-FRI"
        )
        #expect(
            HomeWeekdayFormatter.label(for: [.monday, .wednesday, .friday])
                == "MON · WED · FRI"
        )
        #expect(
            HomeWeekdayFormatter.label(
                for: [.monday, .tuesday, .thursday, .saturday, .sunday]
            ) == "MON-TUE · THU · SAT-SUN"
        )
    }

    private func makeRule(revision: Int) -> RestrictionRuleSnapshot {
        RestrictionRuleSnapshot(
            id: Self.ruleID,
            revision: revision,
            name: "출근 준비",
            isEnabled: true,
            weekdays: [.monday],
            startTime: TimeOfDay(hour: 6, minute: 0),
            endTime: TimeOfDay(hour: 9, minute: 0),
            savedPlaceID: Self.placeID,
            radius: .meters1000,
            activitySelection: FamilyActivitySelection(),
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    private static let ruleID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000601"
    )!
    private static let placeID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000602"
    )!
}
