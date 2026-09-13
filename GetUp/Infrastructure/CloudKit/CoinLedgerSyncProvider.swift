@preconcurrency import CloudKit
import Foundation

enum CoinLedgerCloudAccountAvailability: Equatable, Sendable {
    case available(sessionID: String)
    case signedOut
    case temporarilyUnavailable
    case userIdentityTemporarilyUnavailable(errorCode: Int?)
}

protocol CoinLedgerCloudAccountProviding: Sendable {
    func currentAvailability() async -> CoinLedgerCloudAccountAvailability
}

struct SystemCoinLedgerCloudAccountProvider: CoinLedgerCloudAccountProviding,
    @unchecked Sendable
{
    private let container: CKContainer

    init(container: CKContainer = .default()) {
        self.container = container
    }

    func currentAvailability() async -> CoinLedgerCloudAccountAvailability {
        let status: CKAccountStatus
        do {
            status = try await container.accountStatus()
        } catch {
            return .temporarilyUnavailable
        }

        switch status {
        case .available:
            do {
                let recordID = try await container.userRecordID()
                guard !recordID.recordName.isEmpty else {
                    return .userIdentityTemporarilyUnavailable(errorCode: nil)
                }
                return .available(sessionID: recordID.recordName)
            } catch let error as CKError {
                return .userIdentityTemporarilyUnavailable(errorCode: error.errorCode)
            } catch {
                return .userIdentityTemporarilyUnavailable(errorCode: nil)
            }
        case .noAccount, .restricted:
            return .signedOut
        case .couldNotDetermine, .temporarilyUnavailable:
            return .temporarilyUnavailable
        @unknown default:
            return .temporarilyUnavailable
        }
    }
}

struct CoinLedgerSyncCheckpoint: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let accountSessionID: String
    let stateSerialization: Data?
    let records: [CloudKitRecordSnapshot]
    let recordArchives: [String: Data]
    let lastMirror: CoinBalanceSnapshot?
    let hadObservedZone: Bool
    let hasPendingChanges: Bool

    init(
        schemaVersion: Int = CoinLedgerSyncCheckpoint.currentSchemaVersion,
        accountSessionID: String,
        stateSerialization: Data?,
        records: [CloudKitRecordSnapshot],
        recordArchives: [String: Data],
        lastMirror: CoinBalanceSnapshot? = nil,
        hadObservedZone: Bool,
        hasPendingChanges: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.accountSessionID = accountSessionID
        self.stateSerialization = stateSerialization
        self.records = records.sorted { $0.recordName < $1.recordName }
        self.recordArchives = recordArchives
        self.lastMirror = lastMirror
        self.hadObservedZone = hadObservedZone
        self.hasPendingChanges = hasPendingChanges
    }

    func replacingAccountSessionID(_ accountSessionID: String) -> Self {
        Self(
            schemaVersion: schemaVersion,
            accountSessionID: accountSessionID,
            stateSerialization: stateSerialization,
            records: records,
            recordArchives: recordArchives,
            lastMirror: lastMirror,
            hadObservedZone: hadObservedZone,
            hasPendingChanges: hasPendingChanges
        )
    }

    func replacingLastMirror(_ lastMirror: CoinBalanceSnapshot) -> Self {
        Self(
            schemaVersion: schemaVersion,
            accountSessionID: accountSessionID,
            stateSerialization: stateSerialization,
            records: records,
            recordArchives: recordArchives,
            lastMirror: lastMirror,
            hadObservedZone: hadObservedZone,
            hasPendingChanges: hasPendingChanges
        )
    }
}

protocol CoinLedgerSyncCheckpointRepository: Sendable {
    func loadCheckpoint() async throws -> CoinLedgerSyncCheckpoint?
    func saveCheckpoint(_ checkpoint: CoinLedgerSyncCheckpoint) async throws
    func clearCheckpoint() async throws
}

enum CoinLedgerSyncCheckpointRepositoryError: Error, Equatable, Sendable {
    case readFailed
    case decodingFailed
    case unsupportedSchema(found: Int, supported: Int)
    case encodingFailed
    case writeFailed
    case deletionFailed
}

actor FileCoinLedgerSyncCheckpointRepository: CoinLedgerSyncCheckpointRepository {
    private struct SchemaHeader: Decodable {
        let schemaVersion: Int
    }

    private let fileURL: URL
    private let fileWriter: any SnapshotFileWriting

    init(
        containerURL: URL,
        process: CoinLedgerSyncProcess = .app,
        ledgerNamespace: String? = nil,
        fileWriter: any SnapshotFileWriting = AtomicSnapshotFileWriter()
    ) {
        fileURL = containerURL.appendingPathComponent(
            SharedIdentifiers.coinLedgerSyncCheckpointFileName(
                processIdentifier: process.rawValue,
                ledgerNamespace: ledgerNamespace
            )
        )
        self.fileWriter = fileWriter
    }

    func loadCheckpoint() async throws -> CoinLedgerSyncCheckpoint? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw CoinLedgerSyncCheckpointRepositoryError.readFailed
        }

        let decoder = JSONDecoder()
        let header: SchemaHeader
        do {
            header = try decoder.decode(SchemaHeader.self, from: data)
        } catch {
            throw CoinLedgerSyncCheckpointRepositoryError.decodingFailed
        }
        guard header.schemaVersion == CoinLedgerSyncCheckpoint.currentSchemaVersion else {
            throw CoinLedgerSyncCheckpointRepositoryError.unsupportedSchema(
                found: header.schemaVersion,
                supported: CoinLedgerSyncCheckpoint.currentSchemaVersion
            )
        }
        do {
            let checkpoint = try decoder.decode(CoinLedgerSyncCheckpoint.self, from: data)
            guard !checkpoint.accountSessionID.isEmpty,
                  Set(checkpoint.records.map(\.recordName)).count == checkpoint.records.count
            else {
                throw CoinLedgerSyncCheckpointRepositoryError.decodingFailed
            }
            return checkpoint
        } catch let error as CoinLedgerSyncCheckpointRepositoryError {
            throw error
        } catch {
            throw CoinLedgerSyncCheckpointRepositoryError.decodingFailed
        }
    }

    func saveCheckpoint(_ checkpoint: CoinLedgerSyncCheckpoint) async throws {
        guard checkpoint.schemaVersion == CoinLedgerSyncCheckpoint.currentSchemaVersion,
              !checkpoint.accountSessionID.isEmpty else {
            throw CoinLedgerSyncCheckpointRepositoryError.encodingFailed
        }
        let data: Data
        do {
            data = try JSONEncoder().encode(checkpoint)
        } catch {
            throw CoinLedgerSyncCheckpointRepositoryError.encodingFailed
        }
        do {
            try fileWriter.write(data, to: fileURL)
        } catch {
            throw CoinLedgerSyncCheckpointRepositoryError.writeFailed
        }
    }

    func clearCheckpoint() async throws {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw CoinLedgerSyncCheckpointRepositoryError.deletionFailed
        }
    }
}

enum CoinLedgerSyncProcess: String, Sendable {
    case app
    case shieldAction = "shield-action"
}

struct CoinLedgerSyncEngineResult: Equatable, Sendable {
    let checkpoint: CoinLedgerSyncCheckpoint
    let deletionEvidence: CoinLedgerDeletionEvidence
    let zoneExists: Bool

    init(
        checkpoint: CoinLedgerSyncCheckpoint,
        deletionEvidence: CoinLedgerDeletionEvidence,
        zoneExists: Bool = true
    ) {
        self.checkpoint = checkpoint
        self.deletionEvidence = deletionEvidence
        self.zoneExists = zoneExists
    }
}

protocol CoinLedgerSyncEngineDriving: Sendable {
    func synchronize(
        accountSessionID: String,
        checkpoint: CoinLedgerSyncCheckpoint?
    ) async throws -> CoinLedgerSyncEngineResult
}

enum CoinLedgerSyncProviderError: Error, Equatable, Sendable {
    case syncUnavailable
    case accountChanged
    case invalidProjection
}

struct CoinLedgerSyncProviderResult: Equatable, Sendable {
    let outcome: CoinLedgerSyncOutcome
    let remoteRecords: [CloudKitRecordSnapshot]
    let diagnosticReason: CoinLedgerSyncDiagnosticReason?
    let diagnosticDetail: String?

    init(
        outcome: CoinLedgerSyncOutcome,
        remoteRecords: [CloudKitRecordSnapshot],
        diagnosticReason: CoinLedgerSyncDiagnosticReason? = nil,
        diagnosticDetail: String? = nil
    ) {
        self.outcome = outcome
        self.remoteRecords = remoteRecords
        self.diagnosticReason = diagnosticReason
        self.diagnosticDetail = diagnosticDetail
    }
}

enum CoinLedgerSyncDiagnosticReason: String, Equatable, Sendable {
    case signedOut
    case accountTemporarilyUnavailable
    case userIdentityTemporarilyUnavailable
    case emptyAccountSession
    case engineUnavailable
    case emptyRemoteAfterConfirmedLedger
    case invalidProjection
    case staleProjection
}

actor CoinLedgerSyncProvider {
    typealias WallClockNow = @Sendable () -> Date
    typealias MonotonicNow = @Sendable () -> ContinuousClock.Instant

    private let accountProvider: any CoinLedgerCloudAccountProviding
    private let engine: any CoinLedgerSyncEngineDriving
    private let checkpointRepository: any CoinLedgerSyncCheckpointRepository
    private let balanceRepository: any CoinBalanceSnapshotRepository
    private let wallClockNow: WallClockNow
    private let monotonicNow: MonotonicNow
    private let projector = CoinLedgerRemoteProjector()

    private var adapter: CoinLedgerSyncAdapter?
    private var activeAccountSessionID: String?
    private var latestProjection: CoinLedgerRemoteProjection?

    init(
        accountProvider: any CoinLedgerCloudAccountProviding,
        engine: any CoinLedgerSyncEngineDriving,
        checkpointRepository: any CoinLedgerSyncCheckpointRepository,
        balanceRepository: any CoinBalanceSnapshotRepository,
        wallClockNow: @escaping WallClockNow = Date.init,
        monotonicNow: @escaping MonotonicNow = { ContinuousClock().now }
    ) {
        self.accountProvider = accountProvider
        self.engine = engine
        self.checkpointRepository = checkpointRepository
        self.balanceRepository = balanceRepository
        self.wallClockNow = wallClockNow
        self.monotonicNow = monotonicNow
    }

    func synchronize() async throws -> CoinLedgerSyncProviderResult {
        let availability = await accountProvider.currentAvailability()
        switch availability {
        case .signedOut:
            try? await checkpointRepository.clearCheckpoint()
            latestProjection = nil
            return try await applyUnavailable(
                accountSessionID: "signed-out",
                localMirror: nil,
                reason: .signedOut
            )

        case .temporarilyUnavailable:
            let checkpoint = await loadUsableCheckpoint()
            latestProjection = nil
            return try await applyUnavailable(
                accountSessionID: checkpoint?.accountSessionID ?? "account-unavailable",
                localMirror: checkpoint?.lastMirror,
                reason: .accountTemporarilyUnavailable
            )

        case .userIdentityTemporarilyUnavailable(let errorCode):
            let checkpoint = await loadUsableCheckpoint()
            latestProjection = nil
            return try await applyUnavailable(
                accountSessionID: checkpoint?.accountSessionID ?? "identity-unavailable",
                localMirror: checkpoint?.lastMirror,
                reason: .userIdentityTemporarilyUnavailable,
                detail: errorCode.map { "ckErrorCode: \($0)" }
            )

        case .available(let accountSessionID):
            guard !accountSessionID.isEmpty else {
                return try await applyUnavailable(
                    accountSessionID: "account-unavailable",
                    localMirror: nil,
                    reason: .emptyAccountSession
                )
            }
            return try await synchronizeAvailableAccount(accountSessionID)
        }
    }

    func isCurrent() async -> Bool {
        guard let adapter, let latestProjection else { return false }
        guard let context = await adapter.currentContext(
            iCloudAccountAvailable: true,
            projection: latestProjection
        ) else {
            return false
        }
        return CoinLedgerCurrentGate.isCurrent(
            session: await adapter.session,
            now: monotonicNow(),
            context: context
        )
    }
}

private extension CoinLedgerSyncProvider {
    func synchronizeAvailableAccount(
        _ accountSessionID: String
    ) async throws -> CoinLedgerSyncProviderResult {
        let storedCheckpoint = await loadUsableCheckpoint()
        let sameAccountCheckpoint = storedCheckpoint.flatMap {
            $0.accountSessionID == accountSessionID ? $0 : nil
        }
        if storedCheckpoint != nil, sameAccountCheckpoint == nil {
            try await checkpointRepository.clearCheckpoint()
        }
        let localMirror = sameAccountCheckpoint?.lastMirror
        let adapter = adapterForAccount(accountSessionID)

        let engineResult: CoinLedgerSyncEngineResult
        do {
            engineResult = try await engine.synchronize(
                accountSessionID: accountSessionID,
                checkpoint: sameAccountCheckpoint
            )
        } catch {
            latestProjection = nil
            return try await applyUnavailable(
                accountSessionID: accountSessionID,
                localMirror: localMirror,
                reason: .engineUnavailable
            )
        }

        let checkpoint = engineResult.checkpoint.replacingAccountSessionID(accountSessionID)
        let now = wallClockNow()
        let monthID = MonthlyAllowancePolicy.monthID(containing: now)

        let remoteResult: CoinLedgerRemoteFetchResult
        if engineResult.deletionEvidence.confirmsDeletion {
            latestProjection = nil
            remoteResult = .noLedger(deletionEvidence: engineResult.deletionEvidence)
        } else if checkpoint.records.isEmpty {
            let hadConfirmedLedger = localMirror?.hadConfirmedLedger == true
                || sameAccountCheckpoint.map(projector.containsLedger) == true
            if !engineResult.zoneExists, hadConfirmedLedger {
                latestProjection = nil
                remoteResult = .noLedger(deletionEvidence: .zoneDeletionEvent)
            } else if engineResult.zoneExists, hadConfirmedLedger {
                latestProjection = nil
                let unavailable = try await applyUnavailable(
                    accountSessionID: accountSessionID,
                    localMirror: localMirror,
                    reason: .emptyRemoteAfterConfirmedLedger
                )
                try await checkpointRepository.saveCheckpoint(
                    checkpoint.replacingLastMirror(unavailable.outcome.mirror)
                )
                return unavailable
            } else {
                latestProjection = nil
                remoteResult = .noLedger(deletionEvidence: .none)
            }
        } else {
            do {
                let projection = try projector.project(
                    records: checkpoint.records,
                    currentMonthID: monthID,
                    syncedAt: now
                )
                latestProjection = projection
                remoteResult = .ledger(projection)
            } catch {
                latestProjection = nil
                let unavailable = try await applyUnavailable(
                    accountSessionID: accountSessionID,
                    localMirror: localMirror,
                    reason: .invalidProjection
                )
                try await checkpointRepository.saveCheckpoint(
                    checkpoint.replacingLastMirror(unavailable.outcome.mirror)
                )
                return unavailable
            }
        }

        let outcome = try await adapter.applyInitialFetch(
            remoteResult,
            accountSessionID: accountSessionID,
            localMirror: localMirror,
            currentMonthID: monthID,
            fetchedAt: monotonicNow(),
            syncedAt: now,
            pendingLocalChanges: checkpoint.hasPendingChanges
        )
        try await checkpointRepository.saveCheckpoint(
            checkpoint.replacingLastMirror(outcome.mirror)
        )
        try await balanceRepository.saveCoinBalanceSnapshot(outcome.mirror)
        let staleDetail = outcome.mirror.syncState == .stale
            ? [
                "projectionCompleted: \(projectionCompleted(remoteResult))",
                "pendingReconciliation: \(hasPendingReconciliation(remoteResult))",
                "pendingChanges: \(checkpoint.hasPendingChanges)"
            ].joined(separator: ", ")
            : nil
        return CoinLedgerSyncProviderResult(
            outcome: outcome,
            remoteRecords: checkpoint.records,
            diagnosticReason: staleDetail == nil ? nil : .staleProjection,
            diagnosticDetail: staleDetail
        )
    }

    func applyUnavailable(
        accountSessionID: String,
        localMirror: CoinBalanceSnapshot?,
        reason: CoinLedgerSyncDiagnosticReason,
        detail: String? = nil
    ) async throws -> CoinLedgerSyncProviderResult {
        let now = wallClockNow()
        let adapter = adapterForAccount(accountSessionID)
        let outcome = try await adapter.applyInitialFetch(
            .unavailable,
            accountSessionID: accountSessionID,
            localMirror: localMirror,
            currentMonthID: MonthlyAllowancePolicy.monthID(containing: now),
            fetchedAt: monotonicNow(),
            syncedAt: now
        )
        try await balanceRepository.saveCoinBalanceSnapshot(outcome.mirror)
        return CoinLedgerSyncProviderResult(
            outcome: outcome,
            remoteRecords: [],
            diagnosticReason: reason,
            diagnosticDetail: detail
        )
    }

    func adapterForAccount(_ accountSessionID: String) -> CoinLedgerSyncAdapter {
        if activeAccountSessionID != accountSessionID || adapter == nil {
            adapter = CoinLedgerSyncAdapter(accountSessionID: accountSessionID)
            activeAccountSessionID = accountSessionID
        }
        return adapter!
    }

    func loadUsableCheckpoint() async -> CoinLedgerSyncCheckpoint? {
        do {
            return try await checkpointRepository.loadCheckpoint()
        } catch {
            try? await checkpointRepository.clearCheckpoint()
            return nil
        }
    }

    func projectionCompleted(_ result: CoinLedgerRemoteFetchResult) -> Bool {
        guard case .ledger(let projection) = result else { return false }
        return projection.projectionCompleted
    }

    func hasPendingReconciliation(_ result: CoinLedgerRemoteFetchResult) -> Bool {
        guard case .ledger(let projection) = result else { return false }
        return projection.hasPendingReconciliation
    }
}

private struct CoinLedgerRemoteProjector {
    private let mapper = CoinLedgerRecordMapper()

    func containsLedger(_ checkpoint: CoinLedgerSyncCheckpoint) -> Bool {
        checkpoint.records.contains {
            $0.recordName == CoinLedgerRecordID.ledgerEpoch
                || $0.recordName == CoinLedgerRecordID.coinAccount
        }
    }

    func project(
        records: [CloudKitRecordSnapshot],
        currentMonthID: String,
        syncedAt: Date
    ) throws -> CoinLedgerRemoteProjection {
        guard Set(records.map(\.recordName)).count == records.count else {
            throw CoinLedgerSyncProviderError.invalidProjection
        }

        var epochs: [LedgerEpoch] = []
        var accounts: [CoinAccount] = []
        var allowances: [MonthlyAllowance] = []
        var grants: [PurchaseGrant] = []
        var events: [CoinLedgerEvent] = []
        var commands: [ReleaseCommand] = []
        do {
            for record in records {
                switch try mapper.entity(from: record) {
                case .ledgerEpoch(let value): epochs.append(value)
                case .coinAccount(let value): accounts.append(value)
                case .monthlyAllowance(let value): allowances.append(value)
                case .purchaseGrant(let value): grants.append(value)
                case .event(let value): events.append(value)
                case .releaseCommand(let value): commands.append(value)
                case .releaseOccurrenceClaim, .reservationCompatibilityStamp,
                     .reservationMigrationMarker: break
                }
            }
        } catch {
            throw CoinLedgerSyncProviderError.invalidProjection
        }
        guard epochs.count == 1, accounts.count == 1,
              Set(allowances.map(\.monthID)).count == allowances.count else {
            throw CoinLedgerSyncProviderError.invalidProjection
        }

        let epoch = epochs[0]
        let account = accounts[0]
        let currentAllowance = allowances.first { $0.monthID == currentMonthID }
        let hasPendingReconciliation = commands.contains {
            switch $0.state {
            case .rejected, .committed, .compensated: false
            case .requested, .reserved, .applied, .compensating, .reconciliationRequired: true
            }
        }
        let projectionCompleted = !hasPendingReconciliation
            && account.purchasedReserved == 0
            && (currentAllowance?.reserved ?? 0) == 0

        if projectionCompleted {
            let allowance = try currentAllowance ?? syntheticZeroAllowance(
                epoch: epoch,
                monthID: currentMonthID,
                syncedAt: syncedAt
            )
            _ = try CoinLedgerRecoveryService().recoverFreshInstall(
                snapshot: CoinLedgerRecoverySnapshot(
                    epoch: epoch,
                    account: account,
                    allowance: allowance,
                    purchaseGrants: grants,
                    events: events
                ),
                ledgerState: .current,
                syncedAt: syncedAt
            )
        }

        return CoinLedgerRemoteProjection(
            ledgerEpochID: epoch.epochID,
            accountEpochID: epoch.epochID,
            purchasedAvailable: account.purchasedUsable,
            currentMonthID: currentMonthID,
            freeAvailable: currentAllowance?.available ?? 0,
            projectionCompleted: projectionCompleted,
            hasPendingReconciliation: hasPendingReconciliation
        )
    }

    private func syntheticZeroAllowance(
        epoch: LedgerEpoch,
        monthID: String,
        syncedAt: Date
    ) throws -> MonthlyAllowance {
        let quota = epoch.suppressedFreeMonthID == monthID ? 0 : 2
        return try MonthlyAllowance(
            monthID: monthID,
            quota: quota,
            used: quota,
            reserved: 0,
            creationDate: syncedAt,
            updatedAt: syncedAt
        )
    }
}

actor SystemCoinLedgerSyncEngineDriver: CoinLedgerSyncEngineDriving {
    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private let subscriptionID: String

    init(
        container: CKContainer = .default(),
        zoneName: String = SharedIdentifiers.coinLedgerZoneName,
        subscriptionID: String = "getup.coin-ledger.sync"
    ) {
        database = container.privateCloudDatabase
        zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
        self.subscriptionID = subscriptionID
    }

    func synchronize(
        accountSessionID: String,
        checkpoint: CoinLedgerSyncCheckpoint?
    ) async throws -> CoinLedgerSyncEngineResult {
        guard !accountSessionID.isEmpty,
              checkpoint?.schemaVersion == nil
                || checkpoint?.schemaVersion == CoinLedgerSyncCheckpoint.currentSchemaVersion
        else {
            throw CoinLedgerSyncProviderError.syncUnavailable
        }
        let delegate = try SystemCoinLedgerSyncEngineDelegate(
            zoneID: zoneID,
            checkpoint: checkpoint
        )
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: try checkpoint?.stateSerialization.map {
                try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
            },
            delegate: delegate
        )
        configuration.automaticallySync = false
        configuration.subscriptionID = subscriptionID
        let syncEngine = CKSyncEngine(configuration)

        do {
            if !syncEngine.state.pendingDatabaseChanges.isEmpty
                || !syncEngine.state.pendingRecordZoneChanges.isEmpty
                || syncEngine.state.hasPendingUntrackedChanges {
                try await syncEngine.sendChanges()
            }
            var options = CKSyncEngine.FetchChangesOptions(scope: .all)
            options.prioritizedZoneIDs = [zoneID]
            try await syncEngine.fetchChanges(options)
            let captured = try await delegate.capturedState(
                fallbackStateSerialization: checkpoint?.stateSerialization
            )
            if let changedAccount = captured.changedAccountSessionID,
               changedAccount != accountSessionID {
                throw CoinLedgerSyncProviderError.accountChanged
            }
            let hasPending = !syncEngine.state.pendingDatabaseChanges.isEmpty
                || !syncEngine.state.pendingRecordZoneChanges.isEmpty
                || syncEngine.state.hasPendingUntrackedChanges
            let next = CoinLedgerSyncCheckpoint(
                accountSessionID: accountSessionID,
                stateSerialization: captured.stateSerialization,
                records: captured.records,
                recordArchives: captured.recordArchives,
                hadObservedZone: captured.hadObservedZone,
                hasPendingChanges: hasPending
            )
            return CoinLedgerSyncEngineResult(
                checkpoint: next,
                deletionEvidence: captured.deletionEvidence,
                zoneExists: captured.hadObservedZone && !captured.zoneWasDeleted
            )
        } catch let error as CoinLedgerSyncProviderError {
            throw error
        } catch let error as CKError where error.code == .userDeletedZone {
            return deletedResult(
                accountSessionID: accountSessionID,
                checkpoint: checkpoint,
                evidence: .userDeletedZone
            )
        } catch let error as CKError where error.code == .zoneNotFound
            && checkpoint?.hadObservedZone == true {
            return deletedResult(
                accountSessionID: accountSessionID,
                checkpoint: checkpoint,
                evidence: .zoneDeletionEvent
            )
        } catch {
            throw CoinLedgerSyncProviderError.syncUnavailable
        }
    }

    private func deletedResult(
        accountSessionID: String,
        checkpoint: CoinLedgerSyncCheckpoint?,
        evidence: CoinLedgerDeletionEvidence
    ) -> CoinLedgerSyncEngineResult {
        CoinLedgerSyncEngineResult(
            checkpoint: CoinLedgerSyncCheckpoint(
                accountSessionID: accountSessionID,
                stateSerialization: checkpoint?.stateSerialization,
                records: [],
                recordArchives: [:],
                lastMirror: nil,
                hadObservedZone: true,
                hasPendingChanges: false
            ),
            deletionEvidence: evidence,
            zoneExists: false
        )
    }
}

private final class SystemCoinLedgerSyncEngineDelegate: CKSyncEngineDelegate,
    @unchecked Sendable
{
    private let eventStore: SystemCoinLedgerSyncEventStore

    init(zoneID: CKRecordZone.ID, checkpoint: CoinLedgerSyncCheckpoint?) throws {
        eventStore = try SystemCoinLedgerSyncEventStore(zoneID: zoneID, checkpoint: checkpoint)
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        await eventStore.handle(event)
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) {
            await self.eventStore.record(for: $0)
        }
    }

    func capturedState(
        fallbackStateSerialization: Data?
    ) async throws -> SystemCoinLedgerSyncCapturedState {
        try await eventStore.capturedState(
            fallbackStateSerialization: fallbackStateSerialization
        )
    }
}

private struct SystemCoinLedgerSyncCapturedState: Sendable {
    let stateSerialization: Data?
    let records: [CloudKitRecordSnapshot]
    let recordArchives: [String: Data]
    let hadObservedZone: Bool
    let zoneWasDeleted: Bool
    let deletionEvidence: CoinLedgerDeletionEvidence
    let changedAccountSessionID: String?
}

private actor SystemCoinLedgerSyncEventStore {
    private let zoneID: CKRecordZone.ID
    private let codec: SystemCoinLedgerSyncRecordCodec
    private var recordsByName: [String: CKRecord]
    private var snapshotsByName: [String: CloudKitRecordSnapshot]
    private var latestStateSerialization: Data?
    private var hadObservedZone: Bool
    private var zoneWasDeleted = false
    private var deletionEvidence: CoinLedgerDeletionEvidence = .none
    private var changedAccountSessionID: String?
    private var capturedError: Error?

    init(zoneID: CKRecordZone.ID, checkpoint: CoinLedgerSyncCheckpoint?) throws {
        self.zoneID = zoneID
        codec = SystemCoinLedgerSyncRecordCodec(zoneID: zoneID)
        recordsByName = try checkpoint?.recordArchives.reduce(into: [:]) { result, item in
            guard let record = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKRecord.self,
                from: item.value
            ) else {
                throw CoinLedgerSyncProviderError.syncUnavailable
            }
            result[item.key] = record
        } ?? [:]
        snapshotsByName = Dictionary(
            uniqueKeysWithValues: (checkpoint?.records ?? []).map { ($0.recordName, $0) }
        )
        latestStateSerialization = checkpoint?.stateSerialization
        hadObservedZone = checkpoint?.hadObservedZone ?? false
    }

    func handle(_ event: CKSyncEngine.Event) {
        guard capturedError == nil else { return }
        do {
            switch event {
            case .stateUpdate(let update):
                latestStateSerialization = try JSONEncoder().encode(update.stateSerialization)
            case .accountChange(let change):
                switch change.changeType {
                case .signIn(let currentUser):
                    changedAccountSessionID = currentUser.recordName
                case .switchAccounts(_, let currentUser):
                    changedAccountSessionID = currentUser.recordName
                    recordsByName.removeAll()
                    snapshotsByName.removeAll()
                case .signOut:
                    changedAccountSessionID = "signed-out"
                    recordsByName.removeAll()
                    snapshotsByName.removeAll()
                @unknown default:
                    changedAccountSessionID = "account-unknown"
                }
            case .fetchedDatabaseChanges(let changes):
                if changes.modifications.contains(where: { $0.zoneID == zoneID }) {
                    hadObservedZone = true
                    zoneWasDeleted = false
                }
                if changes.deletions.contains(where: { $0.zoneID == zoneID }) {
                    hadObservedZone = true
                    zoneWasDeleted = true
                    deletionEvidence = .zoneDeletionEvent
                    recordsByName.removeAll()
                    snapshotsByName.removeAll()
                }
            case .fetchedRecordZoneChanges(let changes):
                for modification in changes.modifications
                where modification.record.recordID.zoneID == zoneID {
                    let record = modification.record
                    recordsByName[record.recordID.recordName] = record
                    snapshotsByName[record.recordID.recordName] = try codec.snapshot(from: record)
                    hadObservedZone = true
                }
                for deletion in changes.deletions where deletion.recordID.zoneID == zoneID {
                    recordsByName.removeValue(forKey: deletion.recordID.recordName)
                    snapshotsByName.removeValue(forKey: deletion.recordID.recordName)
                }
            case .sentRecordZoneChanges(let changes):
                for record in changes.savedRecords where record.recordID.zoneID == zoneID {
                    recordsByName[record.recordID.recordName] = record
                    snapshotsByName[record.recordID.recordName] = try codec.snapshot(from: record)
                    hadObservedZone = true
                }
                for recordID in changes.deletedRecordIDs where recordID.zoneID == zoneID {
                    recordsByName.removeValue(forKey: recordID.recordName)
                    snapshotsByName.removeValue(forKey: recordID.recordName)
                }
                for failure in changes.failedRecordSaves
                where failure.record.recordID.zoneID == zoneID {
                    markDeletionIfNeeded(failure.error)
                }
                for (recordID, error) in changes.failedRecordDeletes
                where recordID.zoneID == zoneID {
                    markDeletionIfNeeded(error)
                }
            case .sentDatabaseChanges(let changes):
                if changes.savedZones.contains(where: { $0.zoneID == zoneID }) {
                    hadObservedZone = true
                    zoneWasDeleted = false
                }
                if changes.deletedZoneIDs.contains(zoneID) {
                    hadObservedZone = true
                    zoneWasDeleted = true
                    deletionEvidence = .zoneDeletionEvent
                    recordsByName.removeAll()
                    snapshotsByName.removeAll()
                }
                for failure in changes.failedZoneSaves
                where failure.zone.zoneID == zoneID {
                    markDeletionIfNeeded(failure.error)
                }
                if let error = changes.failedZoneDeletes[zoneID] {
                    markDeletionIfNeeded(error)
                }
            case .didFetchRecordZoneChanges(let result) where result.zoneID == zoneID:
                if let error = result.error {
                    markDeletionIfNeeded(error)
                }
            case .willFetchChanges, .willFetchRecordZoneChanges,
                 .didFetchRecordZoneChanges, .didFetchChanges,
                 .willSendChanges, .didSendChanges:
                break
            @unknown default:
                break
            }
        } catch {
            capturedError = error
        }
    }

    func record(for recordID: CKRecord.ID) -> CKRecord? {
        guard recordID.zoneID == zoneID else { return nil }
        return recordsByName[recordID.recordName]
    }

    private func markDeletionIfNeeded(_ error: CKError) {
        guard error.code == .userDeletedZone
            || (error.code == .zoneNotFound && hadObservedZone) else { return }
        hadObservedZone = true
        zoneWasDeleted = true
        deletionEvidence = error.code == .userDeletedZone
            ? .userDeletedZone
            : .zoneDeletionEvent
        recordsByName.removeAll()
        snapshotsByName.removeAll()
    }

    func capturedState(
        fallbackStateSerialization: Data?
    ) throws -> SystemCoinLedgerSyncCapturedState {
        if capturedError != nil {
            throw CoinLedgerSyncProviderError.syncUnavailable
        }
        var archives: [String: Data] = [:]
        for (name, record) in recordsByName {
            archives[name] = try NSKeyedArchiver.archivedData(
                withRootObject: record,
                requiringSecureCoding: true
            )
        }
        return SystemCoinLedgerSyncCapturedState(
            stateSerialization: latestStateSerialization ?? fallbackStateSerialization,
            records: snapshotsByName.values.sorted { $0.recordName < $1.recordName },
            recordArchives: archives,
            hadObservedZone: hadObservedZone,
            zoneWasDeleted: zoneWasDeleted,
            deletionEvidence: deletionEvidence,
            changedAccountSessionID: changedAccountSessionID
        )
    }
}

private struct SystemCoinLedgerSyncRecordCodec {
    private static let uuidFields: Set<String> = [
        "epochID", "commandID", "ruleID", "relatedCommandID",
    ]
    private static let int64Fields: Set<String> = [
        "transactionID", "relatedTransactionID",
    ]

    let zoneID: CKRecordZone.ID

    func snapshot(from record: CKRecord) throws -> CloudKitRecordSnapshot {
        guard record.recordID.zoneID == zoneID,
              !record.recordID.recordName.isEmpty,
              !record.recordType.isEmpty else {
            throw CoinLedgerSyncProviderError.invalidProjection
        }
        var fields: [String: CloudKitRecordValue] = [:]
        for key in record.allKeys() {
            guard let value = record[key] else { continue }
            fields[key] = try cloudValue(value, field: key)
        }
        if record.recordType == CoinLedgerRecordType.monthlyAllowance {
            guard let creationDate = record.creationDate else {
                throw CoinLedgerSyncProviderError.invalidProjection
            }
            fields["creationDate"] = .date(creationDate)
        }
        return CloudKitRecordSnapshot(
            recordType: record.recordType,
            recordName: record.recordID.recordName,
            changeTag: record.recordChangeTag,
            fields: fields
        )
    }

    private func cloudValue(_ value: Any, field: String) throws -> CloudKitRecordValue {
        if let date = value as? Date { return .date(date) }
        if let string = value as? String {
            if Self.uuidFields.contains(field), let identifier = UUID(uuidString: string) {
                return .uuid(identifier)
            }
            if Self.uuidFields.contains(field) {
                throw CoinLedgerSyncProviderError.invalidProjection
            }
            return .string(string)
        }
        if let number = value as? NSNumber {
            if Self.int64Fields.contains(field) { return .int64(number.int64Value) }
            if String(cString: number.objCType) == "c" { return .bool(number.boolValue) }
            guard let integer = Int(exactly: number.int64Value) else {
                throw CoinLedgerSyncProviderError.invalidProjection
            }
            return .int(integer)
        }
        throw CoinLedgerSyncProviderError.invalidProjection
    }
}
