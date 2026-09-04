import Foundation
import Testing
@testable import GetUp

@Suite("Restriction occurrence evaluator")
struct RestrictionOccurrenceEvaluatorTests {
    @Test("The earliest activation is the representative occurrence")
    func earliestActivationWins() throws {
        let later = try occurrence(
            ruleID: Self.laterRuleID,
            startAt: Self.baseDate,
            activatedAt: Self.baseDate.addingTimeInterval(20)
        )
        let earlier = try occurrence(
            ruleID: Self.earlierRuleID,
            startAt: Self.baseDate.addingTimeInterval(60),
            activatedAt: Self.baseDate.addingTimeInterval(10)
        )

        let result = evaluate([later, earlier])

        #expect(result.orderedOccurrences.map(\.id) == [earlier.id, later.id])
        #expect(result.representative == earlier)
        #expect(result.hasAdditionalRestrictions)
    }

    @Test("Start time breaks an activation time tie")
    func startTimeBreaksActivationTie() throws {
        let laterStart = try occurrence(
            ruleID: Self.earlierRuleID,
            startAt: Self.baseDate.addingTimeInterval(60),
            activatedAt: Self.baseDate.addingTimeInterval(10)
        )
        let earlierStart = try occurrence(
            ruleID: Self.laterRuleID,
            startAt: Self.baseDate,
            activatedAt: Self.baseDate.addingTimeInterval(10)
        )

        let result = evaluate([laterStart, earlierStart])

        #expect(result.orderedOccurrences.map(\.id) == [earlierStart.id, laterStart.id])
        #expect(result.representative == earlierStart)
    }

    @Test("Rule ID breaks activation and start time ties")
    func ruleIDBreaksRemainingTie() throws {
        let laterRule = try occurrence(
            ruleID: Self.laterRuleID,
            startAt: Self.baseDate,
            activatedAt: Self.baseDate.addingTimeInterval(10)
        )
        let earlierRule = try occurrence(
            ruleID: Self.earlierRuleID,
            startAt: Self.baseDate,
            activatedAt: Self.baseDate.addingTimeInterval(10)
        )

        let result = evaluate([laterRule, earlierRule])

        #expect(result.orderedOccurrences.map(\.id) == [earlierRule.id, laterRule.id])
        #expect(result.representative == earlierRule)
    }

    @Test("An ended representative is replaced at its exclusive end boundary")
    func endedRepresentativeIsReplaced() throws {
        let ended = try occurrence(
            ruleID: Self.earlierRuleID,
            startAt: Self.baseDate,
            endAt: Self.now,
            activatedAt: Self.baseDate
        )
        let remaining = try occurrence(
            ruleID: Self.laterRuleID,
            startAt: Self.baseDate,
            activatedAt: Self.baseDate.addingTimeInterval(10)
        )

        let result = evaluate([ended, remaining])

        #expect(result.orderedOccurrences == [remaining])
        #expect(result.representative == remaining)
        #expect(!result.hasAdditionalRestrictions)
    }

    @Test("An occurrence with a stale rule revision is removed before selection")
    func revisionMismatchIsRemoved() throws {
        let stale = try occurrence(
            ruleID: Self.earlierRuleID,
            revision: 1,
            startAt: Self.baseDate,
            activatedAt: Self.baseDate
        )
        let current = try occurrence(
            ruleID: Self.laterRuleID,
            revision: 2,
            startAt: Self.baseDate,
            activatedAt: Self.baseDate.addingTimeInterval(10)
        )

        let result = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: try snapshot([stale, current]),
            currentRuleRevisions: [
                Self.earlierRuleID: 2,
                Self.laterRuleID: 2,
            ],
            now: Self.now
        )

        #expect(result.orderedOccurrences == [current])
        #expect(result.representative == current)
    }

    @Test("A missing snapshot has no representative")
    func missingSnapshotIsEmpty() {
        let result = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: nil,
            currentRuleRevisions: [:],
            now: Self.now
        )

        #expect(result.orderedOccurrences.isEmpty)
        #expect(result.representative == nil)
        #expect(!result.hasAdditionalRestrictions)
    }

    private func evaluate(
        _ occurrences: [RestrictionOccurrence]
    ) -> RestrictionOccurrenceEvaluation {
        RestrictionOccurrenceEvaluator.evaluate(
            snapshot: try! snapshot(occurrences),
            currentRuleRevisions: Dictionary(
                uniqueKeysWithValues: occurrences.map { ($0.ruleID, $0.ruleRevision) }
            ),
            now: Self.now
        )
    }

    private func snapshot(
        _ occurrences: [RestrictionOccurrence]
    ) throws -> ActiveRestrictionSnapshot {
        try ActiveRestrictionSnapshot(
            revision: 1,
            occurrences: occurrences,
            observedAt: Self.now
        )
    }

    private func occurrence(
        ruleID: UUID,
        revision: Int = 1,
        startAt: Date,
        endAt: Date = Self.now.addingTimeInterval(3_600),
        activatedAt: Date
    ) throws -> RestrictionOccurrence {
        try RestrictionOccurrence(
            ruleID: ruleID,
            ruleRevision: revision,
            startAt: startAt,
            endAt: endAt,
            activatedAt: activatedAt
        )
    }

    private static let baseDate = Date(timeIntervalSince1970: 1_788_192_000)
    private static let now = baseDate.addingTimeInterval(300)
    private static let earlierRuleID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000001"
    )!
    private static let laterRuleID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000002"
    )!
}
