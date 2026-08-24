import Foundation

enum RestrictionEvaluationEvent: Equatable, Sendable {
    case timeChanged
    case locationChanged(ruleID: UUID)
    case restoration
}

struct RestrictionCoordinationResult: Equatable, Sendable {
    let event: RestrictionEvaluationEvent
    let decisions: [UUID: EvaluationDecision]
    let appliedState: AppliedRestrictionState
}

struct SystemRestrictionClock: Clock {
    var now: Date { Date() }
}

actor RestrictionCoordinator {
    private let ruleRepository: any RuleRepository
    private let locationConditionRepository: any LocationConditionRepository
    private let authorizationProvider: any AuthorizationProviding
    private let restrictionAdapter: any RestrictionApplying
    private let clock: any Clock
    private let calendar: Calendar
    private let timeZone: TimeZone

    init(
        ruleRepository: any RuleRepository,
        locationConditionRepository: any LocationConditionRepository,
        authorizationProvider: any AuthorizationProviding,
        restrictionAdapter: any RestrictionApplying,
        clock: any Clock = SystemRestrictionClock(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.ruleRepository = ruleRepository
        self.locationConditionRepository = locationConditionRepository
        self.authorizationProvider = authorizationProvider
        self.restrictionAdapter = restrictionAdapter
        self.clock = clock
        self.calendar = calendar
        self.timeZone = timeZone
    }

    func handleTimeEvent() async throws -> RestrictionCoordinationResult {
        try await evaluate(event: .timeChanged)
    }

    func handleLocationEvent(
        ruleID: UUID
    ) async throws -> RestrictionCoordinationResult {
        try await evaluate(event: .locationChanged(ruleID: ruleID))
    }

    func restore() async throws -> RestrictionCoordinationResult {
        try await evaluate(event: .restoration)
    }

    private func evaluate(
        event: RestrictionEvaluationEvent
    ) async throws -> RestrictionCoordinationResult {
        let rules = try await ruleRepository.loadRuleCollection()?.rules ?? []
        let locationConditions = try await locationConditionRepository
            .loadLocationConditionCollection()?.conditions ?? []
        let authorization = await authorizationProvider.authorizationSnapshot()
        let currentAppliedState = await restrictionAdapter.currentAppliedState()

        var decisions: [UUID: EvaluationDecision] = [:]
        var desiredRules: [RestrictionRuleSnapshot] = []

        for rule in rules.sorted(by: Self.ruleOrder) {
            let locationCondition = locationConditions.first {
                $0.ruleID == rule.id && $0.ruleRevision == rule.revision
            } ?? unavailableLocationCondition(for: rule)
            let ruleAppliedState = AppliedRestrictionState(
                activeRuleRevisions: currentAppliedState.activeRuleRevisions.filter {
                    $0.ruleID == rule.id && $0.revision == rule.revision
                }
            )
            let decision = RestrictionStateMachine.evaluate(
                EvaluationInput(
                    rule: rule,
                    now: clock.now,
                    calendar: calendar,
                    timeZone: timeZone,
                    locationCondition: locationCondition,
                    authorization: authorization,
                    appliedRestriction: ruleAppliedState
                )
            )
            decisions[rule.id] = decision

            if decision.desiredRestriction == .active
                || (decision.desiredRestriction == .preserve
                    && currentAppliedState.contains(rule)) {
                desiredRules.append(rule)
            }
        }

        let desiredRuleRevisions = Set(
            desiredRules.map {
                ActiveRuleRevision(ruleID: $0.id, revision: $0.revision)
            }
        )
        if currentAppliedState.requiresReset
            || desiredRuleRevisions != currentAppliedState.activeRuleRevisions {
            if desiredRules.isEmpty {
                try await restrictionAdapter.removeRestriction()
            } else {
                try await restrictionAdapter.applyRestriction(for: desiredRules)
            }
        }

        return RestrictionCoordinationResult(
            event: event,
            decisions: decisions,
            appliedState: await restrictionAdapter.currentAppliedState()
        )
    }

    private func unavailableLocationCondition(
        for rule: RestrictionRuleSnapshot
    ) -> LocationConditionSnapshot {
        LocationConditionSnapshot(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            state: .unavailable,
            observedAt: clock.now,
            distanceMeters: nil,
            horizontalAccuracyMeters: nil,
            source: .restoration
        )
    }

    private static func ruleOrder(
        _ lhs: RestrictionRuleSnapshot,
        _ rhs: RestrictionRuleSnapshot
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}
