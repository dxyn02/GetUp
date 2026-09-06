import Foundation
import Observation

enum ActiveRestrictionReleaseAvailability: Equatable, Sendable {
    case ready
    case noActiveRestriction
    case insufficientBalance
    case iCloudRecoveryRequired
    case ledgerResetRequired
    case reconciliationRequired
    case releaseFailed
}

enum ActiveRestrictionReleasePhase: Equatable, Sendable {
    case idle
    case confirmationRequested
    case processing
    case released(ReleaseFundingSource)
    case blocked(ActiveRestrictionReleaseAvailability)
}

enum ActiveRestrictionReleaseExecutionResult: Equatable, Sendable {
    case released(
        fundingSource: ReleaseFundingSource,
        balance: CoinBalanceSnapshot,
        remainingOccurrences: [RestrictionOccurrence]
    )
    case insufficientBalance(CoinBalanceSnapshot)
    case iCloudRecoveryRequired
    case ledgerResetRequired
    case reconciliationRequired
    case rejected
}

@MainActor
@Observable
final class ActiveRestrictionReleaseModel {
    typealias ExecuteRelease = @Sendable (
        RestrictionOccurrence
    ) async -> ActiveRestrictionReleaseExecutionResult

    @ObservationIgnored private let executeRelease: ExecuteRelease
    private var availabilityOverride: ActiveRestrictionReleaseAvailability?

    private(set) var activeOccurrences: [RestrictionOccurrence]
    private(set) var selectedOccurrence: RestrictionOccurrence?
    private(set) var balance: CoinBalanceSnapshot
    private(set) var hasPendingReconciliation: Bool
    private(set) var phase: ActiveRestrictionReleasePhase = .idle

    var availability: ActiveRestrictionReleaseAvailability {
        if let availabilityOverride {
            return availabilityOverride
        }
        if hasPendingReconciliation {
            return .reconciliationRequired
        }
        guard selectedOccurrence != nil else {
            return .noActiveRestriction
        }

        switch balance.syncState {
        case .current:
            return balance.freeAvailable > 0 || balance.purchasedAvailable > 0
                ? .ready
                : .insufficientBalance
        case .deletionConfirmed, .resetRequired:
            return .ledgerResetRequired
        case .setupRequired, .syncing, .stale, .unavailable:
            return .iCloudRecoveryRequired
        }
    }

    var previewFundingSource: ReleaseFundingSource? {
        guard availability == .ready else { return nil }
        return balance.freeAvailable > 0 ? .monthlyFree : .purchased
    }

    var canRequestConfirmation: Bool {
        phase == .idle && availability == .ready
    }

    init(
        snapshot: ActiveRestrictionSnapshot?,
        currentRuleRevisions: [UUID: Int],
        balance: CoinBalanceSnapshot,
        hasPendingReconciliation: Bool,
        now: @escaping @Sendable () -> Date = Date.init,
        executeRelease: @escaping ExecuteRelease
    ) {
        let occurrences = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: snapshot,
            currentRuleRevisions: currentRuleRevisions,
            now: now()
        ).orderedOccurrences
        self.activeOccurrences = occurrences
        self.selectedOccurrence = occurrences.first
        self.balance = balance
        self.hasPendingReconciliation = hasPendingReconciliation
        self.executeRelease = executeRelease
    }

    @discardableResult
    func selectOccurrence(id: String) -> Bool {
        guard phase == .idle,
              let occurrence = activeOccurrences.first(where: { $0.id == id })
        else {
            return false
        }
        selectedOccurrence = occurrence
        return true
    }

    @discardableResult
    func requestConfirmation() -> Bool {
        guard canRequestConfirmation else { return false }
        phase = .confirmationRequested
        return true
    }

    func cancelConfirmation() {
        guard phase == .confirmationRequested else { return }
        phase = .idle
    }

    func confirmRelease() async {
        guard phase == .confirmationRequested,
              let occurrence = selectedOccurrence
        else {
            return
        }
        phase = .processing

        switch await executeRelease(occurrence) {
        case .released(let fundingSource, let balance, let remainingOccurrences):
            self.balance = balance
            activeOccurrences = remainingOccurrences.sorted(by: Self.occurrenceOrder)
            selectedOccurrence = activeOccurrences.first
            availabilityOverride = nil
            hasPendingReconciliation = false
            phase = .released(fundingSource)
        case .insufficientBalance(let balance):
            self.balance = balance
            block(with: .insufficientBalance)
        case .iCloudRecoveryRequired:
            block(with: .iCloudRecoveryRequired)
        case .ledgerResetRequired:
            block(with: .ledgerResetRequired)
        case .reconciliationRequired:
            hasPendingReconciliation = true
            block(with: .reconciliationRequired)
        case .rejected:
            block(with: .releaseFailed)
        }
    }

    func refresh(
        snapshot: ActiveRestrictionSnapshot?,
        currentRuleRevisions: [UUID: Int],
        balance: CoinBalanceSnapshot,
        hasPendingReconciliation: Bool,
        now: Date
    ) {
        guard phase != .processing else { return }
        activeOccurrences = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: snapshot,
            currentRuleRevisions: currentRuleRevisions,
            now: now
        ).orderedOccurrences
        selectedOccurrence = activeOccurrences.first
        self.balance = balance
        self.hasPendingReconciliation = hasPendingReconciliation
        availabilityOverride = nil
        phase = .idle
    }

    private func block(with availability: ActiveRestrictionReleaseAvailability) {
        availabilityOverride = availability
        phase = .blocked(availability)
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
