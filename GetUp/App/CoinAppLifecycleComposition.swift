import Foundation

extension DependencyContainer {
    func makeCoinAppLifecycleCoordinator() -> CoinAppLifecycleCoordinator {
        let pendingRouteRepository = PendingAppRouteRepository(
            containerURL: coordinationDirectory
        )
        return CoinAppLifecycleCoordinator(
            startTransactionObservation: startCoinTransactionObservation,
            reconcileLedger: reconcileCoinLedgerOnForeground,
            loadActiveOccurrenceIDs: { now in
                let snapshot = try await sharedSnapshotRepository
                    .loadActiveRestrictionSnapshot()
                let rules = try await sharedSnapshotRepository
                    .loadRuleCollection()?.rules ?? []
                let revisions = Dictionary(
                    uniqueKeysWithValues: rules.map { ($0.id, $0.revision) }
                )
                return Set(
                    RestrictionOccurrenceEvaluator.evaluate(
                        snapshot: snapshot,
                        currentRuleRevisions: revisions,
                        now: now
                    ).orderedOccurrences.map(\.id)
                )
            },
            consumePendingRoute: { now, activeOccurrenceIDs in
                try await pendingRouteRepository.consumeIfEligible(
                    now: now,
                    activeOccurrenceIDs: activeOccurrenceIDs
                )?.destination
            }
        )
    }
}
