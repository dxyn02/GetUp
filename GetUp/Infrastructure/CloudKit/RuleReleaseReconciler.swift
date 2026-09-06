import Foundation

struct RuleReleaseReconciliationResult: Sendable {
    let command: ReleaseCommand
    let liveActivityResult: LiveActivityCoordinationResult
}

struct RuleReleaseReconciler: Sendable {
    let exceptionRepository: any ReleaseExceptionRepository
    let ledgerRepository: any CoinLedgerRepository
    /// Re-reads current rules and exceptions and verifies the applied restriction union.
    let applyRestrictions: @Sendable (RuleReleaseLocalLease) async throws -> RuleReleaseApplication
    let reconcileLiveActivity: @Sendable (RestrictionLiveActivitySnapshot?) async -> LiveActivityCoordinationResult
    let clock: any Clock
    let coordinationDirectory: URL

    /// The caller must await this successfully before starting a new release.
    /// Pending IDs remain durable in the caller until their terminal result is confirmed.
    func reconcilePending(commandIDs: [UUID]) async throws -> [RuleReleaseReconciliationResult] {
        var results: [RuleReleaseReconciliationResult] = []
        var seen: Set<UUID> = []
        for id in commandIDs where seen.insert(id).inserted {
            results.append(try await reconcile(commandID: id))
        }
        return results
    }

    func reconcile(commandID: UUID) async throws -> RuleReleaseReconciliationResult {
        let unresolved = RuleReleaseCoordinationError.reconciliationRequired(commandID: commandID)
        do {
            try Task.checkCancellation()
            let lease = try RuleReleaseLocalLease(directory: coordinationDirectory)
            defer { withExtendedLifetime(lease) {} }
            guard clock.now.timeIntervalSince1970.isFinite,
                  let command = try await ledgerRepository.fetchReleaseCommand(commandID: commandID),
                  command.commandID == commandID, command.fundingSource != nil else { throw unresolved }
            let exceptions = try await exceptionRepository.loadReleaseExceptions()
            let evidence = exceptions.first { $0.commandID == commandID }
            if let evidence {
                guard evidence.ruleID == command.ruleID, evidence.occurrenceID == command.occurrenceID else {
                    throw unresolved
                }
            }

            let terminal: ReleaseCommand
            let application: RuleReleaseApplication
            switch command.state {
            case .committed:
                // The interval may already have expired and been cleaned; never recreate an exception.
                application = try await applyRestrictions(lease)
                terminal = command
            case .compensated, .compensating:
                if evidence != nil {
                    _ = try await exceptionRepository.removeReleaseException(
                        commandID: commandID, occurrenceID: command.occurrenceID)
                }
                application = try await applyRestrictions(lease)
                terminal = command.state == .compensated ? command
                    : try await ledgerRepository.compensateRelease(commandID: commandID, at: clock.now)
                try validate(terminal, against: command, expected: .compensated)
            case .reserved, .applied, .reconciliationRequired:
                // A different owner is not evidence of this command's application.
                guard !exceptions.contains(where: {
                    $0.occurrenceID == command.occurrenceID && $0.commandID != commandID
                }) else { throw unresolved }
                application = try await applyRestrictions(lease)
                if evidence != nil {
                    if command.state == .reserved {
                        let applied = try await ledgerRepository.markReleaseApplied(commandID: commandID, at: clock.now)
                        // A concurrent remote replay can already have committed the same command.
                        if applied.state == .committed {
                            try validate(applied, against: command, expected: .committed)
                            terminal = applied
                        } else {
                            try validate(applied, against: command, expected: .applied)
                            terminal = try await ledgerRepository.commitRelease(commandID: commandID, at: clock.now)
                        }
                    } else {
                        terminal = try await ledgerRepository.commitRelease(commandID: commandID, at: clock.now)
                    }
                    try validate(terminal, against: command, expected: .committed)
                } else {
                    terminal = try await ledgerRepository.compensateRelease(commandID: commandID, at: clock.now)
                    try validate(terminal, against: command, expected: .compensated)
                }
            case .requested, .rejected:
                throw unresolved
            }
            let activity = await reconcileLiveActivity(application.desiredLiveActivity)
            return RuleReleaseReconciliationResult(command: terminal, liveActivityResult: activity)
        } catch {
            // Failed/unknown confirmation never triggers the opposite financial operation.
            throw unresolved
        }
    }

    private func validate(_ result: ReleaseCommand, against original: ReleaseCommand, expected: ReleaseCommandState) throws {
        guard result.commandID == original.commandID, result.occurrenceID == original.occurrenceID,
              result.ruleID == original.ruleID, result.fundingSource == original.fundingSource,
              result.state == expected else {
            throw RuleReleaseCoordinationError.reconciliationRequired(commandID: original.commandID)
        }
    }
}
