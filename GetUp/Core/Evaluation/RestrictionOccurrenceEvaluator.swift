import Foundation

struct RestrictionOccurrenceEvaluation: Equatable, Sendable {
    let orderedOccurrences: [RestrictionOccurrence]

    var representative: RestrictionOccurrence? {
        orderedOccurrences.first
    }

    var hasAdditionalRestrictions: Bool {
        orderedOccurrences.count > 1
    }
}

enum RestrictionOccurrenceEvaluator {
    static func evaluate(
        snapshot: ActiveRestrictionSnapshot?,
        currentRuleRevisions: [UUID: Int],
        now: Date
    ) -> RestrictionOccurrenceEvaluation {
        let orderedOccurrences = (snapshot?.occurrences ?? [])
            .filter { occurrence in
                now < occurrence.endAt
                    && currentRuleRevisions[occurrence.ruleID]
                        == occurrence.ruleRevision
            }
            .sorted(by: occurrenceOrder)

        return RestrictionOccurrenceEvaluation(
            orderedOccurrences: orderedOccurrences
        )
    }

    private static func occurrenceOrder(
        _ lhs: RestrictionOccurrence,
        _ rhs: RestrictionOccurrence
    ) -> Bool {
        if lhs.activatedAt != rhs.activatedAt {
            return lhs.activatedAt < rhs.activatedAt
        }
        if lhs.startAt != rhs.startAt {
            return lhs.startAt < rhs.startAt
        }
        return lhs.ruleID.uuidString < rhs.ruleID.uuidString
    }
}
