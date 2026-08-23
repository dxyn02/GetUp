import Foundation

protocol Clock: Sendable {
    var now: Date { get }
}

protocol RuleRepository: Sendable {
    func loadRule() async throws -> RestrictionRuleSnapshot?
    func saveRule(_ rule: RestrictionRuleSnapshot) async throws
    func deleteRule() async throws
}

protocol LocationConditionRepository: Sendable {
    func loadLocationCondition() async throws -> LocationConditionSnapshot?
    func saveLocationCondition(_ condition: LocationConditionSnapshot) async throws
    func deleteLocationCondition() async throws
}

protocol AuthorizationProviding: Sendable {
    func authorizationSnapshot() async -> AuthorizationSnapshot
}

protocol ScheduleManaging: Sendable {
    func replaceSchedules(for rule: RestrictionRuleSnapshot) async throws
    func removeSchedules() async throws
}

protocol LocationMonitoring: Sendable {
    func replaceMonitoring(for rule: RestrictionRuleSnapshot) async throws
    func stopMonitoring() async throws
    func refreshLocationCondition(
        for rule: RestrictionRuleSnapshot,
        source: LocationConditionSource
    ) async -> LocationConditionSnapshot
}

struct AppliedRestrictionState: Equatable, Sendable {
    let isApplied: Bool
    let ruleRevision: Int?
}

protocol RestrictionApplying: Sendable {
    func currentAppliedState() async -> AppliedRestrictionState
    func applyRestriction(for rule: RestrictionRuleSnapshot) async throws
    func removeRestriction() async throws
}
