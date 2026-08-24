import Foundation

struct RestrictionStatusModel: Equatable, Sendable {
    private let appliedState: AppliedRestrictionState

    init(
        appliedState: AppliedRestrictionState = AppliedRestrictionState(
            activeRuleRevisions: []
        )
    ) {
        self.appliedState = appliedState
    }

    var hasActiveRestriction: Bool {
        !appliedState.activeRuleRevisions.isEmpty
    }

    func isActive(_ rule: RestrictionRuleSnapshot) -> Bool {
        appliedState.contains(rule)
    }
}
