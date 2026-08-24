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
    let transitionMeasurement: RestrictionTransitionMeasurement?
}

struct RestrictionTransitionMeasurement: Equatable, Sendable {
    let effect: RestrictionEffect
    let eventConfirmedAt: Date
    let effectCompletedAt: Date

    var latencySeconds: TimeInterval {
        max(0, effectCompletedAt.timeIntervalSince(eventConfirmedAt))
    }
}

struct SystemRestrictionClock: Clock {
    var now: Date { Date() }
}

actor RestrictionCoordinator {
    private static let maximumTrustedLocationAge: TimeInterval = 24 * 60 * 60

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

    func handleTimeEvent(
        confirmedAt: Date? = nil
    ) async throws -> RestrictionCoordinationResult {
        try await evaluate(
            event: .timeChanged,
            eventConfirmedAt: confirmedAt ?? clock.now
        )
    }

    func handleLocationEvent(
        ruleID: UUID,
        confirmedAt: Date? = nil
    ) async throws -> RestrictionCoordinationResult {
        try await evaluate(
            event: .locationChanged(ruleID: ruleID),
            eventConfirmedAt: confirmedAt ?? clock.now
        )
    }

    func restore() async throws -> RestrictionCoordinationResult {
        try await evaluate(event: .restoration, eventConfirmedAt: nil)
    }

    private func evaluate(
        event: RestrictionEvaluationEvent,
        eventConfirmedAt: Date?
    ) async throws -> RestrictionCoordinationResult {
        let rules = try await ruleRepository.loadRuleCollection()?.rules ?? []
        let locationConditions = try await locationConditionRepository
            .loadLocationConditionCollection()?.conditions ?? []
        let authorization = await authorizationProvider.authorizationSnapshot()
        let currentAppliedState = await restrictionAdapter.currentAppliedState()

        var decisions: [UUID: EvaluationDecision] = [:]
        var desiredRules: [RestrictionRuleSnapshot] = []

        for rule in rules.sorted(by: Self.ruleOrder) {
            let storedLocationCondition = locationConditions.first {
                $0.ruleID == rule.id && $0.ruleRevision == rule.revision
            } ?? unavailableLocationCondition(for: rule)
            let locationCondition = trustedLocationCondition(
                storedLocationCondition,
                for: rule
            )
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
        var performedEffect: RestrictionEffect?
        if currentAppliedState.requiresReset
            || desiredRuleRevisions != currentAppliedState.activeRuleRevisions {
            if desiredRules.isEmpty {
                try await restrictionAdapter.removeRestriction()
                performedEffect = .removeShield
            } else {
                try await restrictionAdapter.applyRestriction(for: desiredRules)
                performedEffect = desiredRuleRevisions.isStrictSubset(
                    of: currentAppliedState.activeRuleRevisions
                ) ? .removeShield : .applyShield
            }
        }

        let appliedState = await restrictionAdapter.currentAppliedState()
        let transitionMeasurement = eventConfirmedAt.flatMap { confirmedAt in
            performedEffect.map { effect in
                RestrictionTransitionMeasurement(
                    effect: effect,
                    eventConfirmedAt: confirmedAt,
                    effectCompletedAt: clock.now
                )
            }
        }

        return RestrictionCoordinationResult(
            event: event,
            decisions: decisions,
            appliedState: appliedState,
            transitionMeasurement: transitionMeasurement
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

    private func trustedLocationCondition(
        _ condition: LocationConditionSnapshot,
        for rule: RestrictionRuleSnapshot
    ) -> LocationConditionSnapshot {
        let age = clock.now.timeIntervalSince(condition.observedAt)
        guard age < Self.maximumTrustedLocationAge else {
            return LocationConditionSnapshot(
                ruleID: rule.id,
                ruleRevision: rule.revision,
                state: .unavailable,
                observedAt: condition.observedAt,
                distanceMeters: nil,
                horizontalAccuracyMeters: nil,
                source: condition.source
            )
        }
        return condition
    }

    private static func ruleOrder(
        _ lhs: RestrictionRuleSnapshot,
        _ rhs: RestrictionRuleSnapshot
    ) -> Bool {
        lhs.id.uuidString < rhs.id.uuidString
    }
}

@MainActor
extension DependencyContainer {
    func makeRestrictionCoordinator(
        bundle: Bundle = .main
    ) throws -> RestrictionCoordinator {
        RestrictionCoordinator(
            ruleRepository: ruleRepository,
            locationConditionRepository: locationConditionRepository,
            authorizationProvider: SystemAuthorizationProvider(),
            restrictionAdapter: try makeRestrictionAdapter(bundle: bundle)
        )
    }
}
