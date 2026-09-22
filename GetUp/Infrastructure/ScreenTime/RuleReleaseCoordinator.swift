import Foundation

struct RuleReleaseCoordinationResult: Sendable {
    let committedCommand: ReleaseCommand
    let liveActivityResult: LiveActivityCoordinationResult
}

struct RuleReleaseCoordinator: Sendable {
    let exceptionRepository: any ReleaseExceptionRepository
    let ledgerRepository: any CoinLedgerRepository
    /// Reads current saved rules and current exceptions, reevaluates the union and verifies read-back.
    /// All participating restriction writers must use the same coordination directory.
    let applyRestrictions: @Sendable (RuleReleaseLocalLease) async throws -> RuleReleaseApplication
    let reconcileLiveActivity: @Sendable (RestrictionLiveActivitySnapshot?) async -> LiveActivityCoordinationResult
    let clock: any Clock
    let coordinationDirectory: URL

    func coordinate(
        reservation: CoinReleaseReservation,
        exception: ReleaseException
    ) async throws -> RuleReleaseCoordinationResult {
        let requested = reservation.command
        let id = requested.commandID
        let unresolved = RuleReleaseCoordinationError.reconciliationRequired(commandID: id)
        guard requested.commandID == exception.commandID,
              requested.occurrenceID == exception.occurrenceID,
              requested.ruleID == exception.ruleID,
              requested.fundingSource != nil else {
            throw RuleReleaseCoordinationError.invalidReservation
        }
        let lease: RuleReleaseLocalLease
        do { lease = try RuleReleaseLocalLease(directory: coordinationDirectory) }
        catch { throw unresolved }
        defer { withExtendedLifetime(lease) {} }

        // Never trust a stale reservation after a prior attempt committed or compensated.
        let current: ReleaseCommand
        do {
            guard let fetched = try await ledgerRepository.fetchReleaseCommand(commandID: id),
                  fetched.commandID == id, fetched.occurrenceID == exception.occurrenceID,
                  fetched.ruleID == exception.ruleID, fetched.fundingSource == requested.fundingSource else {
                throw unresolved
            }
            current = fetched
        } catch { throw unresolved }
        guard current.state == .reserved else { throw unresolved }

        let before: [ReleaseException]
        do { before = try await exceptionRepository.loadReleaseExceptions() }
        catch { throw unresolved }
        // Existing local evidence belongs to reconciliation, not a fresh attempt or rollback.
        guard !before.contains(where: { $0.commandID == id || $0.occurrenceID == exception.occurrenceID }) else {
            throw unresolved
        }
        guard clock.now.timeIntervalSince1970.isFinite,
              exception.effectiveAt <= clock.now, clock.now < exception.expiresAt,
              !Task.isCancelled else {
            try await compensate(id)
            throw RuleReleaseCoordinationError.applicationFailed
        }

        do { _ = try await exceptionRepository.insertReleaseException(exception) }
        catch ReleaseExceptionRepositoryError.writeFailed {
            try await compensate(id)
            throw RuleReleaseCoordinationError.applicationFailed
        } catch { throw unresolved }

        let application: RuleReleaseApplication
        do {
            try Task.checkCancellation()
            guard clock.now < exception.expiresAt else { throw RuleReleaseCoordinationError.applicationFailed }
            application = try await applyRestrictions(lease)
        } catch {
            try await rollback(exception, using: lease)
            throw RuleReleaseCoordinationError.applicationFailed
        }

        let committed: ReleaseCommand
        do {
            let applied = try await ledgerRepository.markReleaseApplied(commandID: id, at: clock.now)
            guard applied.commandID == id, applied.state == .applied else { throw unresolved }
            committed = try await ledgerRepository.commitRelease(commandID: id, at: clock.now)
            guard committed.commandID == id, committed.state == .committed else { throw unresolved }
        } catch {
            // Only an explicitly definite server rejection permits undoing local application.
            guard case CoinLedgerRepositoryError.database(.serverUnavailable) = error else { throw unresolved }
            try await rollback(exception, using: lease)
            throw RuleReleaseCoordinationError.applicationFailed
        }
        let activity = await reconcileLiveActivity(application.desiredLiveActivity)
        return RuleReleaseCoordinationResult(committedCommand: committed, liveActivityResult: activity)
    }

    private func rollback(
        _ exception: ReleaseException,
        using lease: RuleReleaseLocalLease
    ) async throws {
        do {
            _ = try await exceptionRepository.removeReleaseException(
                commandID: exception.commandID, occurrenceID: exception.occurrenceID
            )
            _ = try await applyRestrictions(lease)
        } catch {
            throw RuleReleaseCoordinationError.reconciliationRequired(commandID: exception.commandID)
        }
        try await compensate(exception.commandID)
    }

    private func compensate(_ id: UUID) async throws {
        do {
            let command = try await ledgerRepository.compensateRelease(commandID: id, at: clock.now)
            guard command.commandID == id, command.state == .compensated else {
                throw RuleReleaseCoordinationError.applicationFailed
            }
        } catch { throw RuleReleaseCoordinationError.reconciliationRequired(commandID: id) }
    }
}

extension CoinRuleReleaseLiveExecutor {
    static func classifyReservationPolicyError(
        _ error: CoinReservationPolicyError
    ) -> ReleaseHandoffExecutionResult {
        switch error {
        case .insufficientBalance:
            return .failed(.insufficientBalance)
        case .ledgerNotCurrent, .ledgerEpochMismatch:
            return .failed(.accountOrLedgerRecovery)
        }
    }

    /// App-only handoff path. Reconcile durable commands before deciding whether
    /// the command has never reserved, then revalidate the occurrence from disk.
    func executeHandoff(
        route: PendingAppRoute,
        context: ReleaseHandoffProcessingContext
    ) async -> ReleaseHandoffExecutionResult {
        guard route.destination == .releaseProcessing,
              let commandID = route.commandID,
              let occurrenceID = route.occurrenceID else {
            return .failed(.accountOrLedgerRecovery)
        }
        do {
            recordHandoffStage("refreshForAppStarted")
            let ledger = try await runtime.refreshForApp { commandIDs in
                try await reconcilePending(commandIDs)
            }
            recordHandoffStage("refreshForAppCompleted")
            guard ledger.balance.syncState == .current,
                  !ledger.hasPendingReconciliation else {
                return .failed(.accountOrLedgerRecovery)
            }

            recordHandoffStage("fetchCommandStarted")
            if let command = try await runtime.repository.fetchReleaseCommand(commandID: commandID) {
                recordHandoffStage("fetchCommandCompleted")
                guard command.occurrenceID == occurrenceID else {
                    return .failed(.accountOrLedgerRecovery)
                }
                switch command.state {
                case .committed, .reserved, .applied, .reconciliationRequired:
                    try await reconcilePending([commandID])
                    guard let verified = try await runtime.repository.fetchReleaseCommand(
                        commandID: commandID
                    ) else {
                        return .interruptedUnresolved
                    }
                    guard verified.state == .committed,
                          let funding = verified.fundingSource else {
                        return verified.state == .compensated
                            ? .failed(.accountOrLedgerRecovery)
                            : .interruptedUnresolved
                    }
                    let remaining = try await activeOccurrences(at: clock.now)
                    return .completed(
                        fundingSource: funding,
                        remainingRestrictionCount: remaining.count
                    )
                case .compensated, .compensating, .rejected, .requested:
                    // A compensated command cannot be reserved a second time with
                    // this ID. Never advertise a retry that would double-spend.
                    return .failed(.accountOrLedgerRecovery)
                }
            }
            recordHandoffStage("commandAbsent")

            guard context == .initialClaim else {
                return .interruptedUnresolved
            }
            recordHandoffStage("activeOccurrencesStarted")
            guard let occurrence = try await activeOccurrences(at: clock.now).first(where: {
                $0.id == occurrenceID
            }) else {
                return .failed(.transientRetryable(retryAfter: nil))
            }
            recordHandoffStage("activeOccurrencesCompleted")
            let result = try await execute(
                occurrence: occurrence,
                commandID: commandID,
                source: .shield
            )
            return .completed(
                fundingSource: result.fundingSource,
                remainingRestrictionCount: result.remainingOccurrences.count
            )
        } catch CoinLedgerRepositoryError.insufficientMonthlyAllowance,
                CoinLedgerRepositoryError.insufficientPurchasedBalance {
            return .failed(.insufficientBalance)
        } catch CoinLedgerRepositoryError.ledgerNotCurrent,
                CoinLedgerRepositoryError.ledgerEpochMismatch,
                CoinLedgerRepositoryError.database(.accountUnavailable) {
            return .failed(.accountOrLedgerRecovery)
        } catch CoinLedgerRepositoryError.database(.serverUnavailable),
                CoinLedgerRepositoryError.database(.accountTemporarilyUnavailable) {
            return .failed(.transientRetryable(retryAfter: nil))
        } catch CoinLedgerRepositoryError.reconciliationRequired,
                RuleReleaseCoordinationError.reconciliationRequired,
                CoinLedgerRepositoryError.database(.serverRecordChanged),
                CoinLedgerRepositoryError.database(.resultUnknown) {
            return .failed(.outcomeUnknown)
        } catch let error as RuleReleaseServiceError {
            recordHandoffStage("ruleReleaseServiceError.\(String(describing: error))")
            return .failed(.outcomeUnknown)
        } catch let error as CoinReservationPolicyError {
            recordHandoffStage("coinReservationPolicyError.\(String(describing: error))")
            return Self.classifyReservationPolicyError(error)
        } catch {
            recordHandoffStage("unexpectedError.\(String(describing: type(of: error)))")
            return .failed(.outcomeUnknown)
        }
    }
}
