import Foundation

struct CoinLedgerRecoverySnapshot: Equatable, Sendable {
    let epoch: LedgerEpoch
    let account: CoinAccount
    let allowance: MonthlyAllowance
    let purchaseGrants: [PurchaseGrant]
    let events: [CoinLedgerEvent]
}

struct CoinLedgerRecoveryResult: Equatable, Sendable {
    let mirror: CoinBalanceSnapshot
    let purchaseGrants: [PurchaseGrant]
    let events: [CoinLedgerEvent]
}

enum CoinLedgerRecoveryServiceError: Error, Equatable, Sendable {
    case remoteLedgerMissing
    case ledgerNotCurrent
    case invalidProjection
}

struct CoinLedgerRecoveryService: Sendable {
    func recoverFreshInstall(
        snapshot: CoinLedgerRecoverySnapshot?,
        ledgerState: CoinBalanceSyncState,
        syncedAt: Date
    ) throws -> CoinLedgerRecoveryResult {
        guard let snapshot else {
            throw CoinLedgerRecoveryServiceError.remoteLedgerMissing
        }
        guard ledgerState == .current else {
            throw CoinLedgerRecoveryServiceError.ledgerNotCurrent
        }

        do {
            try Self.validate(snapshot: snapshot, syncedAt: syncedAt)
            let mirror = try CoinBalanceSnapshot(
                purchasedAvailable: snapshot.account.purchasedAvailable,
                currentMonthID: snapshot.allowance.monthID,
                freeAvailable: snapshot.allowance.available,
                syncState: .current,
                syncedAt: syncedAt,
                ledgerEpochID: snapshot.epoch.epochID,
                hadConfirmedLedger: true
            )
            return CoinLedgerRecoveryResult(
                mirror: mirror,
                purchaseGrants: snapshot.purchaseGrants,
                events: snapshot.events
            )
        } catch let error as CoinLedgerRecoveryServiceError {
            throw error
        } catch {
            throw CoinLedgerRecoveryServiceError.invalidProjection
        }
    }

    private static func validate(
        snapshot: CoinLedgerRecoverySnapshot,
        syncedAt: Date
    ) throws {
        guard
            syncedAt.timeIntervalSince1970.isFinite,
            snapshot.epoch.schemaVersion == LedgerEpoch.currentSchemaVersion,
            snapshot.epoch.createdAt.timeIntervalSince1970.isFinite,
            snapshot.epoch.disclosureVersion > 0,
            snapshot.account.schemaVersion == CoinAccount.currentSchemaVersion,
            snapshot.account.updatedAt.timeIntervalSince1970.isFinite,
            snapshot.account.purchasedReserved == 0,
            snapshot.allowance.schemaVersion == MonthlyAllowance.currentSchemaVersion,
            snapshot.allowance.creationDate.timeIntervalSince1970.isFinite,
            snapshot.allowance.updatedAt.timeIntervalSince1970.isFinite,
            snapshot.allowance.monthID == MonthlyAllowancePolicy.monthID(containing: syncedAt),
            Set(snapshot.events.map(\.eventID)).count == snapshot.events.count,
            Set(snapshot.purchaseGrants.map(\.transactionID)).count
                == snapshot.purchaseGrants.count,
            Set(snapshot.purchaseGrants.map(\.environment)).count <= 1,
            validatesEpochPolicy(snapshot.epoch, allowance: snapshot.allowance)
        else {
            throw CoinLedgerRecoveryServiceError.invalidProjection
        }

        let grantsByTransaction = Dictionary(
            uniqueKeysWithValues: snapshot.purchaseGrants.map { ($0.transactionID, $0) }
        )
        let eventsByID = Dictionary(
            uniqueKeysWithValues: snapshot.events.map { ($0.eventID, $0) }
        )
        var purchaseTotal = 0
        var purchasedSpendTotal = 0
        var refundTotals: [UInt64: Int] = [:]
        var reversalTotals: [UInt64: Int] = [:]
        var purchaseEventCount: [UInt64: Int] = [:]

        for grant in snapshot.purchaseGrants {
            guard
                grant.schemaVersion == PurchaseGrant.currentSchemaVersion,
                grant.purchaseDate.timeIntervalSince1970.isFinite
            else {
                throw CoinLedgerRecoveryServiceError.invalidProjection
            }
            purchaseTotal = try adding(purchaseTotal, grant.quantity)
        }

        for event in snapshot.events {
            guard
                event.schemaVersion == CoinLedgerEvent.currentSchemaVersion,
                event.createdAt.timeIntervalSince1970.isFinite
            else {
                throw CoinLedgerRecoveryServiceError.invalidProjection
            }
            try validateShape(of: event)
            switch event.kind {
            case .purchaseGrant:
                guard
                    let transactionID = event.relatedTransactionID,
                    let grant = grantsByTransaction[transactionID],
                    event.eventID == CoinLedgerDeterministicID.purchase(
                        environment: grant.environment,
                        transactionID: transactionID
                    ),
                    event.quantity == grant.quantity
                else {
                    throw CoinLedgerRecoveryServiceError.invalidProjection
                }
                purchaseEventCount[transactionID] = try adding(
                    purchaseEventCount[transactionID, default: 0],
                    1
                )

            case .refundAdjustment:
                guard let transactionID = event.relatedTransactionID,
                      grantsByTransaction[transactionID] != nil else {
                    throw CoinLedgerRecoveryServiceError.invalidProjection
                }
                refundTotals[transactionID] = try adding(
                    refundTotals[transactionID, default: 0],
                    event.quantity
                )

            case .reversal:
                guard let transactionID = event.relatedTransactionID,
                      grantsByTransaction[transactionID] != nil,
                      event.eventID.hasPrefix("reversal:"),
                      let refund = eventsByID[String(event.eventID.dropFirst("reversal:".count))],
                      refund.kind == .refundAdjustment,
                      refund.relatedTransactionID == transactionID,
                      refund.quantity == event.quantity
                else {
                    throw CoinLedgerRecoveryServiceError.invalidProjection
                }
                reversalTotals[transactionID] = try adding(
                    reversalTotals[transactionID, default: 0],
                    event.quantity
                )

            case .spend where event.source == .purchased:
                purchasedSpendTotal = try adding(purchasedSpendTotal, event.quantity)

            case .freeGrant, .reservation, .spend, .release:
                break
            }
        }

        var totalAdjustment = 0
        for grant in snapshot.purchaseGrants {
            let adjustment = try subtracting(
                refundTotals[grant.transactionID, default: 0],
                reversalTotals[grant.transactionID, default: 0]
            )
            guard
                purchaseEventCount[grant.transactionID] == 1,
                adjustment == grant.adjustedQuantity
            else {
                throw CoinLedgerRecoveryServiceError.invalidProjection
            }
            totalAdjustment = try adding(totalAdjustment, adjustment)
        }

        let afterAdjustments = try subtracting(purchaseTotal, totalAdjustment)
        let projectedAvailable = try subtracting(afterAdjustments, purchasedSpendTotal)
        guard projectedAvailable == snapshot.account.purchasedAvailable else {
            throw CoinLedgerRecoveryServiceError.invalidProjection
        }
    }

    private static func validatesEpochPolicy(
        _ epoch: LedgerEpoch,
        allowance: MonthlyAllowance
    ) -> Bool {
        switch epoch.reason {
        case .initialSetup:
            return epoch.suppressedFreeMonthID == nil && allowance.quota == 2
        case .userConfirmedResetAfterDeletion:
            guard let suppressedMonthID = epoch.suppressedFreeMonthID else {
                return false
            }
            return suppressedMonthID
                == MonthlyAllowancePolicy.monthID(containing: epoch.createdAt)
                && suppressedMonthID <= allowance.monthID
                && allowance.quota == (suppressedMonthID == allowance.monthID ? 0 : 2)
        }
    }

    private static func validateShape(of event: CoinLedgerEvent) throws {
        let valid: Bool
        switch event.kind {
        case .purchaseGrant, .refundAdjustment, .reversal:
            valid = event.source == .purchased
                && event.relatedTransactionID != nil
                && event.relatedCommandID == nil
                && event.occurrenceID == nil
        case .freeGrant:
            valid = event.source == .monthlyFree
                && event.relatedTransactionID == nil
                && event.relatedCommandID == nil
                && event.occurrenceID == nil
                && event.eventID == CoinLedgerDeterministicID.freeGrant(
                    monthID: MonthlyAllowancePolicy.monthID(containing: event.createdAt)
                )
        case .reservation:
            valid = event.source != .none
                && event.relatedTransactionID == nil
                && event.relatedCommandID != nil
                && event.occurrenceID?.isEmpty == false
                && event.eventID == event.relatedCommandID.map(
                    CoinLedgerDeterministicID.reservation(commandID:)
                )
        case .spend:
            valid = event.source != .none
                && event.relatedTransactionID == nil
                && event.relatedCommandID != nil
                && event.occurrenceID?.isEmpty == false
                && event.eventID == event.relatedCommandID.map(
                    CoinLedgerDeterministicID.spend(commandID:)
                )
        case .release:
            valid = event.source != .none
                && event.relatedTransactionID == nil
                && event.relatedCommandID != nil
                && event.occurrenceID?.isEmpty == false
                && validatesReleaseEventID(event)
        }
        guard valid else {
            throw CoinLedgerRecoveryServiceError.invalidProjection
        }
    }

    private static func validatesReleaseEventID(_ event: CoinLedgerEvent) -> Bool {
        guard let commandID = event.relatedCommandID else {
            return false
        }
        let prefix = "release:\(commandID.uuidString.lowercased()):"
        guard event.eventID.hasPrefix(prefix) else {
            return false
        }
        guard let attempt = Int(event.eventID.dropFirst(prefix.count)), attempt > 0 else {
            return false
        }
        return event.eventID == CoinLedgerDeterministicID.release(
            commandID: commandID,
            attempt: attempt
        )
    }

    private static func adding(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        guard !overflow else {
            throw CoinLedgerRecoveryServiceError.invalidProjection
        }
        return result
    }

    private static func subtracting(_ lhs: Int, _ rhs: Int) throws -> Int {
        let (result, overflow) = lhs.subtractingReportingOverflow(rhs)
        guard !overflow, result >= 0 else {
            throw CoinLedgerRecoveryServiceError.invalidProjection
        }
        return result
    }
}
