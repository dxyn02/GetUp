import Foundation

protocol Clock: Sendable {
    var now: Date { get }
}

protocol RuleRepository: Sendable {
    func loadRuleCollection() async throws -> RestrictionRuleCollectionSnapshot?
    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) async throws
    func deleteRuleCollection() async throws
}

protocol SavedPlaceRepository: Sendable {
    func loadSavedPlaceCollection() async throws -> SavedPlaceCollectionSnapshot?
    func saveSavedPlaceCollection(_ collection: SavedPlaceCollectionSnapshot) async throws
    func deleteSavedPlaceCollection() async throws
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
