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

struct RestrictionRuleSetEvaluation: Sendable {
    let decisions: [UUID: EvaluationDecision]
    let desiredRules: [RestrictionRuleSnapshot]
}

enum RestrictionRuleSetEvaluator {
    private static let maximumTrustedLocationAge: TimeInterval = 24 * 60 * 60

    static func evaluate(
        rules: [RestrictionRuleSnapshot],
        locationConditions: [LocationConditionSnapshot],
        authorization: AuthorizationSnapshot,
        currentAppliedState: AppliedRestrictionState,
        now: Date,
        calendar: Calendar,
        timeZone: TimeZone
    ) -> RestrictionRuleSetEvaluation {
        var decisions: [UUID: EvaluationDecision] = [:]
        var desiredRules: [RestrictionRuleSnapshot] = []

        for rule in rules.sorted(by: ruleOrder) {
            let storedLocationCondition = locationConditions.first {
                $0.ruleID == rule.id && $0.ruleRevision == rule.revision
            } ?? unavailableLocationCondition(for: rule, now: now)
            let locationCondition = trustedLocationCondition(
                storedLocationCondition,
                for: rule,
                now: now
            )
            let ruleAppliedState = AppliedRestrictionState(
                activeRuleRevisions: currentAppliedState.activeRuleRevisions.filter {
                    $0.ruleID == rule.id && $0.revision == rule.revision
                }
            )
            let decision = RestrictionStateMachine.evaluate(
                EvaluationInput(
                    rule: rule,
                    now: now,
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

        return RestrictionRuleSetEvaluation(
            decisions: decisions,
            desiredRules: desiredRules
        )
    }

    private static func unavailableLocationCondition(
        for rule: RestrictionRuleSnapshot,
        now: Date
    ) -> LocationConditionSnapshot {
        LocationConditionSnapshot(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            state: .unavailable,
            observedAt: now,
            distanceMeters: nil,
            horizontalAccuracyMeters: nil,
            source: .restoration
        )
    }

    private static func trustedLocationCondition(
        _ condition: LocationConditionSnapshot,
        for rule: RestrictionRuleSnapshot,
        now: Date
    ) -> LocationConditionSnapshot {
        let age = now.timeIntervalSince(condition.observedAt)
        guard age < maximumTrustedLocationAge else {
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

actor RestrictionCoordinator {

    private let ruleRepository: any RuleRepository
    private let locationConditionRepository: any LocationConditionRepository
    private let authorizationProvider: any AuthorizationProviding
    private let restrictionAdapter: any RestrictionApplying
    private let activeRestrictionSnapshotRepository:
        (any ActiveRestrictionSnapshotRepository)?
    private let clock: any Clock
    private let calendar: Calendar
    private let timeZone: TimeZone

    init(
        ruleRepository: any RuleRepository,
        locationConditionRepository: any LocationConditionRepository,
        authorizationProvider: any AuthorizationProviding,
        restrictionAdapter: any RestrictionApplying,
        activeRestrictionSnapshotRepository:
            (any ActiveRestrictionSnapshotRepository)? = nil,
        clock: any Clock = SystemRestrictionClock(),
        calendar: Calendar = .current,
        timeZone: TimeZone = .current
    ) {
        self.ruleRepository = ruleRepository
        self.locationConditionRepository = locationConditionRepository
        self.authorizationProvider = authorizationProvider
        self.restrictionAdapter = restrictionAdapter
        self.activeRestrictionSnapshotRepository =
            activeRestrictionSnapshotRepository
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
        let evaluatedAt = clock.now

        let evaluation = RestrictionRuleSetEvaluator.evaluate(
            rules: rules,
            locationConditions: locationConditions,
            authorization: authorization,
            currentAppliedState: currentAppliedState,
            now: evaluatedAt,
            calendar: calendar,
            timeZone: timeZone
        )
        let decisions = evaluation.decisions
        let desiredRules = evaluation.desiredRules

        let desiredRuleRevisions = Set(
            desiredRules.map {
                ActiveRuleRevision(ruleID: $0.id, revision: $0.revision)
            }
        )
        var performedEffect: RestrictionEffect?
        let logicalStateChanged = currentAppliedState.requiresReset
            || desiredRuleRevisions != currentAppliedState.activeRuleRevisions
        if desiredRules.isEmpty {
            if logicalStateChanged {
                try await restrictionAdapter.removeRestriction()
                performedEffect = .removeShield
            }
        } else {
            // The persisted revision set can remain active even when iOS has
            // dropped the underlying Managed Settings shield. The adapter
            // performs a store read-back and writes only when reconciliation
            // is actually needed.
            try await restrictionAdapter.applyRestriction(for: desiredRules)
            if logicalStateChanged {
                performedEffect = desiredRuleRevisions.isStrictSubset(
                    of: currentAppliedState.activeRuleRevisions
                ) ? .removeShield : .applyShield
            }
        }

        let appliedState = await restrictionAdapter.currentAppliedState()
        try await saveActiveRestrictionSnapshot(
            desiredRules: desiredRules,
            appliedState: appliedState,
            observedAt: evaluatedAt
        )
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

    private func saveActiveRestrictionSnapshot(
        desiredRules: [RestrictionRuleSnapshot],
        appliedState: AppliedRestrictionState,
        observedAt: Date
    ) async throws {
        guard let activeRestrictionSnapshotRepository else {
            return
        }

        let previous = try await activeRestrictionSnapshotRepository
            .loadActiveRestrictionSnapshot()
        let previousOccurrences = Dictionary(
            uniqueKeysWithValues: (previous?.occurrences ?? []).map {
                ($0.id, $0)
            }
        )
        var occurrences: [RestrictionOccurrence] = []

        for rule in desiredRules where appliedState.contains(rule) {
            guard let interval = ScheduleEvaluator.activeInterval(
                weekdays: rule.weekdays,
                startTime: rule.startTime,
                endTime: rule.endTime,
                at: observedAt,
                calendar: calendar,
                timeZone: timeZone
            ) else {
                continue
            }

            let occurrenceID = RestrictionOccurrence.deterministicID(
                ruleID: rule.id,
                ruleRevision: rule.revision,
                startAt: interval.lowerBound,
                endAt: interval.upperBound
            )
            let activatedAt = previousOccurrences[occurrenceID]?.activatedAt
                ?? observedAt
            occurrences.append(
                try RestrictionOccurrence(
                    ruleID: rule.id,
                    ruleRevision: rule.revision,
                    startAt: interval.lowerBound,
                    endAt: interval.upperBound,
                    activatedAt: activatedAt
                )
            )
        }

        occurrences.sort(by: occurrenceOrder)
        let occurrenceIDs = occurrences.map(\.id)
        let previousOccurrenceIDs = previous?.occurrences
            .sorted(by: occurrenceOrder)
            .map(\.id) ?? []
        let revision: Int
        if let previous {
            revision = occurrenceIDs == previousOccurrenceIDs
                ? previous.revision
                : previous.revision + 1
        } else {
            revision = 1
        }

        try await activeRestrictionSnapshotRepository.saveActiveRestrictionSnapshot(
            try ActiveRestrictionSnapshot(
                revision: revision,
                occurrences: occurrences,
                observedAt: observedAt
            )
        )
    }

    private func occurrenceOrder(
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

@MainActor
extension DependencyContainer {
    func makeRestrictionCoordinator(
        bundle: Bundle = .main,
        authorizationProvider: any AuthorizationProviding = SystemAuthorizationProvider()
    ) throws -> RestrictionCoordinator {
        RestrictionCoordinator(
            ruleRepository: ruleRepository,
            locationConditionRepository: locationConditionRepository,
            authorizationProvider: authorizationProvider,
            restrictionAdapter: try makeRestrictionAdapter(bundle: bundle),
            activeRestrictionSnapshotRepository: sharedSnapshotRepository
        )
    }
}
