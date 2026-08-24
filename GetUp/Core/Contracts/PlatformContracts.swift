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
    func loadLocationConditionCollection() async throws -> LocationConditionCollectionSnapshot?
    func saveLocationCondition(_ condition: LocationConditionSnapshot) async throws
    func deleteLocationCondition(for ruleID: UUID) async throws
    func deleteLocationConditions() async throws
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

struct ActiveRuleRevision: Codable, Equatable, Hashable, Sendable {
    let ruleID: UUID
    let revision: Int
}

struct AppliedRestrictionState: Equatable, Sendable {
    let activeRuleRevisions: Set<ActiveRuleRevision>
    let requiresReset: Bool

    init(
        activeRuleRevisions: Set<ActiveRuleRevision>,
        requiresReset: Bool = false
    ) {
        self.activeRuleRevisions = activeRuleRevisions
        self.requiresReset = requiresReset
    }

    var isApplied: Bool {
        !activeRuleRevisions.isEmpty || requiresReset
    }

    func contains(_ rule: RestrictionRuleSnapshot) -> Bool {
        activeRuleRevisions.contains(
            ActiveRuleRevision(ruleID: rule.id, revision: rule.revision)
        )
    }
}

protocol RestrictionApplying: Sendable {
    func currentAppliedState() async -> AppliedRestrictionState
    func applyRestriction(for rules: [RestrictionRuleSnapshot]) async throws
    func removeRestriction() async throws
}
