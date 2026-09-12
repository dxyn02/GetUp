import Foundation
import Testing
@testable import GetUp

@Suite("Coin ledger CKSyncEngine provider")
struct CoinLedgerSyncProviderTests {
    @Test("A fresh process fetches the remote ledger before becoming current")
    func freshProcessRequiresInitialFetch() async throws {
        let account = CoinLedgerCloudAccountFake(.available(sessionID: "account-a"))
        let engine = CoinLedgerSyncEngineFake(results: [
            .success(Self.engineResult(records: try Self.ledgerRecords(freeAvailable: 2)))
        ])
        let checkpointStore = CoinLedgerSyncCheckpointStoreFake()
        let balanceStore = CoinBalanceStoreFake()
        let provider = Self.provider(
            account: account,
            engine: engine,
            checkpointStore: checkpointStore,
            balanceStore: balanceStore
        )

        #expect(await provider.isCurrent() == false)

        let result = try await provider.synchronize()

        #expect(result.outcome.mirror.syncState == .current)
        #expect(result.outcome.mirror.freeAvailable == 2)
        #expect(result.outcome.recoveredFromRemote)
        #expect(await provider.isCurrent())
        #expect(await balanceStore.snapshot == result.outcome.mirror)
        #expect(await checkpointStore.checkpoint?.accountSessionID == "account-a")
        #expect(await checkpointStore.checkpoint?.lastMirror == result.outcome.mirror)
    }

    @Test("Persisted state does not make a restarted process current before another fetch")
    func processRestartRequiresAnotherFetch() async throws {
        let checkpoint = Self.checkpoint(
            accountSessionID: "account-a",
            records: try Self.ledgerRecords(freeAvailable: 1),
            hasPendingChanges: false,
            lastMirror: try Self.balance(freeAvailable: 1)
        )
        let checkpointStore = CoinLedgerSyncCheckpointStoreFake(checkpoint: checkpoint)
        let balanceStore = CoinBalanceStoreFake(snapshot: try Self.balance(freeAvailable: 1))
        let engine = CoinLedgerSyncEngineFake(results: [
            .success(Self.engineResult(records: checkpoint.records))
        ])
        let provider = Self.provider(
            account: CoinLedgerCloudAccountFake(.available(sessionID: "account-a")),
            engine: engine,
            checkpointStore: checkpointStore,
            balanceStore: balanceStore
        )

        #expect(await provider.isCurrent() == false)
        _ = try await provider.synchronize()
        #expect(await provider.isCurrent())
        #expect(await engine.receivedCheckpoints == [checkpoint])
    }

    @Test("Switching iCloud accounts discards the previous account checkpoint and mirror")
    func accountSwitchIsolatesState() async throws {
        let account = CoinLedgerCloudAccountFake(.available(sessionID: "account-a"))
        let engine = CoinLedgerSyncEngineFake(results: [
            .success(Self.engineResult(records: try Self.ledgerRecords(freeAvailable: 2))),
            .success(Self.engineResult(records: try Self.ledgerRecords(freeAvailable: 1))),
        ])
        let checkpointStore = CoinLedgerSyncCheckpointStoreFake()
        let balanceStore = CoinBalanceStoreFake()
        let provider = Self.provider(
            account: account,
            engine: engine,
            checkpointStore: checkpointStore,
            balanceStore: balanceStore
        )

        _ = try await provider.synchronize()
        await account.set(.available(sessionID: "account-b"))
        let switched = try await provider.synchronize()

        #expect(switched.outcome.mirror.freeAvailable == 1)
        #expect(await checkpointStore.checkpoint?.accountSessionID == "account-b")
        #expect(await engine.receivedCheckpoints.count == 2)
        #expect(await engine.receivedCheckpoints[1] == nil)
    }

    @Test("A failed pending send keeps its checkpoint and retries on the next sync")
    func pendingChangesRetryWithoutBecomingCurrent() async throws {
        let checkpoint = Self.checkpoint(
            accountSessionID: "account-a",
            records: try Self.ledgerRecords(freeAvailable: 1),
            hasPendingChanges: true,
            lastMirror: try Self.balance(freeAvailable: 1)
        )
        let checkpointStore = CoinLedgerSyncCheckpointStoreFake(checkpoint: checkpoint)
        let balanceStore = CoinBalanceStoreFake(snapshot: try Self.balance(freeAvailable: 1))
        let engine = CoinLedgerSyncEngineFake(results: [
            .failure(CoinLedgerSyncProviderError.syncUnavailable),
            .success(Self.engineResult(records: checkpoint.records)),
        ])
        let provider = Self.provider(
            account: CoinLedgerCloudAccountFake(.available(sessionID: "account-a")),
            engine: engine,
            checkpointStore: checkpointStore,
            balanceStore: balanceStore
        )

        let unavailable = try await provider.synchronize()
        #expect(unavailable.outcome.mirror.syncState == .unavailable)
        #expect(unavailable.diagnosticReason == .engineUnavailable)
        #expect(await checkpointStore.checkpoint == checkpoint)
        #expect(await provider.isCurrent() == false)

        let recovered = try await provider.synchronize()
        #expect(recovered.outcome.mirror.syncState == .current)
        #expect(await engine.receivedCheckpoints == [checkpoint, checkpoint])
    }

    @Test("A zone deletion event locks the ledger and clears confirmed balances")
    func zoneDeletionIsConfirmed() async throws {
        let checkpoint = Self.checkpoint(
            accountSessionID: "account-a",
            records: try Self.ledgerRecords(freeAvailable: 2),
            hasPendingChanges: false,
            lastMirror: try Self.balance(freeAvailable: 2)
        )
        let checkpointStore = CoinLedgerSyncCheckpointStoreFake(checkpoint: checkpoint)
        let balanceStore = CoinBalanceStoreFake(snapshot: try Self.balance(freeAvailable: 2))
        let deleted = CoinLedgerSyncEngineResult(
            checkpoint: Self.checkpoint(
                accountSessionID: "account-a",
                records: [],
                hasPendingChanges: false,
                hadObservedZone: true
            ),
            deletionEvidence: .zoneDeletionEvent
        )
        let provider = Self.provider(
            account: CoinLedgerCloudAccountFake(.available(sessionID: "account-a")),
            engine: CoinLedgerSyncEngineFake(results: [.success(deleted)]),
            checkpointStore: checkpointStore,
            balanceStore: balanceStore
        )

        let result = try await provider.synchronize()

        #expect(result.outcome.mirror.syncState == .deletionConfirmed)
        #expect(result.outcome.mirror.purchasedAvailable == 0)
        #expect(result.outcome.mirror.freeAvailable == 0)
        #expect(await provider.isCurrent() == false)
    }

    @Test("A temporary account-status failure preserves only an unavailable display mirror")
    func temporaryAccountFailureIsNotDeletion() async throws {
        let balance = try Self.balance(freeAvailable: 1)
        let checkpoint = Self.checkpoint(
            accountSessionID: "account-a",
            records: try Self.ledgerRecords(freeAvailable: 1),
            hasPendingChanges: false,
            lastMirror: balance
        )
        let balanceStore = CoinBalanceStoreFake(snapshot: balance)
        let engine = CoinLedgerSyncEngineFake(results: [])
        let provider = Self.provider(
            account: CoinLedgerCloudAccountFake(.temporarilyUnavailable),
            engine: engine,
            checkpointStore: CoinLedgerSyncCheckpointStoreFake(checkpoint: checkpoint),
            balanceStore: balanceStore
        )

        let result = try await provider.synchronize()

        #expect(result.outcome.mirror.syncState == .unavailable)
        #expect(result.diagnosticReason == .accountTemporarilyUnavailable)
        #expect(result.outcome.mirror.freeAvailable == 1)
        #expect(result.outcome.mirror.hadConfirmedLedger)
        #expect(await engine.receivedCheckpoints.isEmpty)
        #expect(await provider.isCurrent() == false)
    }

    @Test("A temporary user identity failure stays distinct from account status failure")
    func temporaryUserIdentityFailureIsDiagnosed() async throws {
        let balance = try Self.balance(freeAvailable: 1)
        let result = try await Self.provider(
            account: CoinLedgerCloudAccountFake(
                .userIdentityTemporarilyUnavailable(errorCode: 9)
            ),
            engine: CoinLedgerSyncEngineFake(results: []),
            checkpointStore: CoinLedgerSyncCheckpointStoreFake(checkpoint: Self.checkpoint(
                accountSessionID: "account-a",
                records: try Self.ledgerRecords(freeAvailable: 1),
                hasPendingChanges: false,
                lastMirror: balance
            )),
            balanceStore: CoinBalanceStoreFake(snapshot: balance)
        ).synchronize()

        #expect(result.outcome.mirror.syncState == .unavailable)
        #expect(result.outcome.mirror.freeAvailable == 1)
        #expect(result.diagnosticReason == .userIdentityTemporarilyUnavailable)
        #expect(result.diagnosticDetail == "ckErrorCode: 9")
    }

    @Test("Signing out removes the account checkpoint and never exposes its balance")
    func signOutIsolatesPriorAccount() async throws {
        let checkpointStore = CoinLedgerSyncCheckpointStoreFake(checkpoint: Self.checkpoint(
            accountSessionID: "account-a",
            records: try Self.ledgerRecords(freeAvailable: 2),
            hasPendingChanges: false
        ))
        let balanceStore = CoinBalanceStoreFake(snapshot: try Self.balance(freeAvailable: 2))
        let provider = Self.provider(
            account: CoinLedgerCloudAccountFake(.signedOut),
            engine: CoinLedgerSyncEngineFake(results: []),
            checkpointStore: checkpointStore,
            balanceStore: balanceStore
        )

        let result = try await provider.synchronize()

        #expect(result.outcome.mirror.syncState == .unavailable)
        #expect(result.diagnosticReason == .signedOut)
        #expect(result.outcome.mirror.purchasedAvailable == 0)
        #expect(result.outcome.mirror.freeAvailable == 0)
        #expect(result.outcome.mirror.hadConfirmedLedger == false)
        #expect(await checkpointStore.checkpoint == nil)
    }

    @Test("A successful fetch with pending engine changes remains stale")
    func pendingCheckpointCannotPublishCurrentMirror() async throws {
        let pending = CoinLedgerSyncEngineResult(
            checkpoint: Self.checkpoint(
                accountSessionID: "account-a",
                records: try Self.ledgerRecords(freeAvailable: 2),
                hasPendingChanges: true
            ),
            deletionEvidence: .none
        )
        let provider = Self.provider(
            account: CoinLedgerCloudAccountFake(.available(sessionID: "account-a")),
            engine: CoinLedgerSyncEngineFake(results: [.success(pending)]),
            checkpointStore: CoinLedgerSyncCheckpointStoreFake(),
            balanceStore: CoinBalanceStoreFake()
        )

        let result = try await provider.synchronize()

        #expect(result.outcome.mirror.syncState == .stale)
        #expect(result.diagnosticReason == .staleProjection)
        #expect(
            result.diagnosticDetail
                == "projectionCompleted: true, pendingReconciliation: false, pendingChanges: true"
        )
        #expect(await provider.isCurrent() == false)
    }

    @Test("A fetched ledger without this month's allowance is current with zero confirmed free uses")
    func missingCurrentAllowanceSupportsLazyCreation() async throws {
        let records = try Self.ledgerRecords(freeAvailable: 2).filter {
            $0.recordType != CoinLedgerRecordType.monthlyAllowance
        }
        let provider = Self.provider(
            account: CoinLedgerCloudAccountFake(.available(sessionID: "account-a")),
            engine: CoinLedgerSyncEngineFake(results: [
                .success(Self.engineResult(records: records))
            ]),
            checkpointStore: CoinLedgerSyncCheckpointStoreFake(),
            balanceStore: CoinBalanceStoreFake()
        )

        let result = try await provider.synchronize()

        #expect(result.outcome.mirror.syncState == .current)
        #expect(result.outcome.mirror.freeAvailable == 0)
        #expect(await provider.isCurrent())
    }

    @Test("The App Group checkpoint round-trips account, engine state, and remote records")
    func fileCheckpointRoundTrips() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "coin-ledger-sync-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = FileCoinLedgerSyncCheckpointRepository(containerURL: directory)
        let shieldRepository = FileCoinLedgerSyncCheckpointRepository(
            containerURL: directory,
            process: .shieldAction
        )
        let checkpoint = Self.checkpoint(
            accountSessionID: "account-a",
            records: try Self.ledgerRecords(freeAvailable: 1),
            hasPendingChanges: true
        )

        try await repository.saveCheckpoint(checkpoint)
        try await shieldRepository.saveCheckpoint(checkpoint.replacingAccountSessionID("shield"))

        #expect(try await repository.loadCheckpoint() == checkpoint)
        #expect(try await shieldRepository.loadCheckpoint()?.accountSessionID == "shield")
        try await repository.clearCheckpoint()
        #expect(try await repository.loadCheckpoint() == nil)
        #expect(try await shieldRepository.loadCheckpoint()?.accountSessionID == "shield")
    }

    @Test("An incomplete remote projection cannot replace the mirror as current")
    func invalidProjectionFailsClosed() async throws {
        let records = try Self.ledgerRecords(freeAvailable: 2).filter {
            $0.recordType == CoinLedgerRecordType.ledgerEpoch
        }
        let checkpointStore = CoinLedgerSyncCheckpointStoreFake()
        let provider = Self.provider(
            account: CoinLedgerCloudAccountFake(.available(sessionID: "account-a")),
            engine: CoinLedgerSyncEngineFake(results: [
                .success(Self.engineResult(records: records))
            ]),
            checkpointStore: checkpointStore,
            balanceStore: CoinBalanceStoreFake()
        )

        let result = try await provider.synchronize()

        #expect(result.outcome.mirror.syncState == .unavailable)
        #expect(result.diagnosticReason == .invalidProjection)
        #expect(result.outcome.mirror.hadConfirmedLedger == false)
        #expect(await checkpointStore.checkpoint?.lastMirror == result.outcome.mirror)
        #expect(await provider.isCurrent() == false)
    }

    @Test("App launch, foreground, and Shield each fetch before exposing the shared mirror")
    func liveRuntimeRefreshesEveryProcessEntryPoint() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "coin-ledger-live-runtime-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let shared = SharedSnapshotRepository(containerURL: directory)
        let records = try Self.ledgerRecords(freeAvailable: 2)
        let appEngine = CoinLedgerSyncEngineFake(results: [
            .success(Self.engineResult(records: records)),
            .success(Self.engineResult(records: records)),
        ])
        let shieldEngine = CoinLedgerSyncEngineFake(results: [
            .success(Self.engineResult(records: records)),
        ])
        let appProvider = CoinLedgerSyncProvider(
            accountProvider: CoinLedgerCloudAccountFake(.available(sessionID: "account-a")),
            engine: appEngine,
            checkpointRepository: CoinLedgerSyncCheckpointStoreFake(),
            balanceRepository: shared,
            wallClockNow: { Self.now }
        )
        let shieldProvider = CoinLedgerSyncProvider(
            accountProvider: CoinLedgerCloudAccountFake(.available(sessionID: "account-a")),
            engine: shieldEngine,
            checkpointRepository: CoinLedgerSyncCheckpointStoreFake(),
            balanceRepository: shared,
            wallClockNow: { Self.now }
        )
        let unusedDatabase = CoinLedgerDatabaseUnusedFake()
        let app = CoinLedgerLiveRuntime(
            repository: CloudKitCoinLedgerRepository(database: unusedDatabase),
            synchronize: { try await appProvider.synchronize() }
        )
        let shield = CoinLedgerLiveRuntime(
            repository: CloudKitCoinLedgerRepository(database: unusedDatabase),
            synchronize: { try await shieldProvider.synchronize() }
        )

        let launch = try await app.refreshForApp()
        let foreground = try await app.refreshForApp()
        let shieldRequest = try await shield.refreshBeforeShieldRequest()

        #expect(launch.balance.syncState == .current)
        #expect(foreground.balance.syncState == .current)
        #expect(shieldRequest.snapshot.balance.syncState == .current)
        #expect(await appEngine.receivedCheckpoints.count == 2)
        #expect(await shieldEngine.receivedCheckpoints.count == 1)
        #expect(try await shared.loadCoinBalanceSnapshot() == shieldRequest.snapshot.balance)
    }

    @Test("App refresh reconciles every remote nonterminal command before returning current")
    func liveRuntimeReconcilesBeforeReturning() async throws {
        let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000001102")!
        let requested = try ReleaseCommand.requested(
            commandID: commandID,
            occurrenceID: "occurrence-live",
            ruleID: UUID(),
            requestedFrom: .shield,
            at: Self.now
        )
        let reserved = try requested.transitioning(
            to: .reserved,
            fundingSource: .monthlyFree,
            at: Self.now
        )
        let mapper = CoinLedgerRecordMapper()
        let pendingRecords = try Self.ledgerRecords(freeAvailable: 1)
            + [mapper.record(for: .releaseCommand(reserved))]
        let queue = RuntimeSyncQueue(results: [
            CoinLedgerSyncProviderResult(
                outcome: CoinLedgerSyncOutcome(
                    mirror: try CoinBalanceSnapshot(
                        purchasedAvailable: 0,
                        currentMonthID: "2026-09",
                        freeAvailable: 1,
                        syncState: .stale,
                        syncedAt: Self.now,
                        ledgerEpochID: Self.epochID,
                        hadConfirmedLedger: true
                    ),
                    recoveredFromRemote: false
                ),
                remoteRecords: pendingRecords
            ),
            CoinLedgerSyncProviderResult(
                outcome: CoinLedgerSyncOutcome(
                    mirror: try Self.balance(freeAvailable: 2),
                    recoveredFromRemote: true
                ),
                remoteRecords: try Self.ledgerRecords(freeAvailable: 2)
            ),
        ])
        let reconciled = ReconciledCommandRecorder()
        let runtime = CoinLedgerLiveRuntime(
            repository: CloudKitCoinLedgerRepository(database: CoinLedgerDatabaseUnusedFake()),
            synchronize: { try await queue.next() }
        )

        let result = try await runtime.refreshForApp { ids in
            await reconciled.record(ids)
        }

        #expect(result.balance.syncState == .current)
        #expect(await reconciled.commandIDs == [commandID])
        #expect(await queue.callCount == 2)
    }
}

private extension CoinLedgerSyncProviderTests {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let epochID = UUID(uuidString: "00000000-0000-4000-8000-000000001101")!

    static func provider(
        account: CoinLedgerCloudAccountFake,
        engine: CoinLedgerSyncEngineFake,
        checkpointStore: CoinLedgerSyncCheckpointStoreFake,
        balanceStore: CoinBalanceStoreFake
    ) -> CoinLedgerSyncProvider {
        CoinLedgerSyncProvider(
            accountProvider: account,
            engine: engine,
            checkpointRepository: checkpointStore,
            balanceRepository: balanceStore,
            wallClockNow: { now },
            monotonicNow: { ContinuousClock().now }
        )
    }

    static func engineResult(
        records: [CloudKitRecordSnapshot]
    ) -> CoinLedgerSyncEngineResult {
        CoinLedgerSyncEngineResult(
            checkpoint: checkpoint(
                accountSessionID: "ignored-by-provider",
                records: records,
                hasPendingChanges: false
            ),
            deletionEvidence: .none
        )
    }

    static func checkpoint(
        accountSessionID: String,
        records: [CloudKitRecordSnapshot],
        hasPendingChanges: Bool,
        hadObservedZone: Bool = true,
        lastMirror: CoinBalanceSnapshot? = nil
    ) -> CoinLedgerSyncCheckpoint {
        CoinLedgerSyncCheckpoint(
            accountSessionID: accountSessionID,
            stateSerialization: Data([0x01, 0x02]),
            records: records,
            recordArchives: [:],
            lastMirror: lastMirror,
            hadObservedZone: hadObservedZone,
            hasPendingChanges: hasPendingChanges
        )
    }

    static func ledgerRecords(freeAvailable: Int) throws -> [CloudKitRecordSnapshot] {
        let mapper = CoinLedgerRecordMapper()
        let allowance = try MonthlyAllowance(
            monthID: "2026-09",
            quota: 2,
            used: 2 - freeAvailable,
            reserved: 0,
            creationDate: now,
            updatedAt: now
        )
        return try [
            mapper.record(for: .ledgerEpoch(LedgerEpoch(
                epochID: epochID,
                createdAt: now,
                reason: .initialSetup,
                suppressedFreeMonthID: nil,
                disclosureVersion: 1
            ))),
            mapper.record(for: .coinAccount(CoinAccount(
                purchasedAvailable: 0,
                purchasedReserved: 0,
                revision: 0,
                updatedAt: now
            ))),
            mapper.record(for: .monthlyAllowance(allowance)),
        ]
    }

    static func balance(freeAvailable: Int) throws -> CoinBalanceSnapshot {
        try CoinBalanceSnapshot(
            purchasedAvailable: 0,
            currentMonthID: "2026-09",
            freeAvailable: freeAvailable,
            syncState: .current,
            syncedAt: now,
            ledgerEpochID: epochID,
            hadConfirmedLedger: true
        )
    }
}

private actor CoinLedgerCloudAccountFake: CoinLedgerCloudAccountProviding {
    private var availability: CoinLedgerCloudAccountAvailability

    init(_ availability: CoinLedgerCloudAccountAvailability) {
        self.availability = availability
    }

    func currentAvailability() async -> CoinLedgerCloudAccountAvailability {
        availability
    }

    func set(_ availability: CoinLedgerCloudAccountAvailability) {
        self.availability = availability
    }
}

private actor CoinLedgerSyncEngineFake: CoinLedgerSyncEngineDriving {
    private var results: [Result<CoinLedgerSyncEngineResult, Error>]
    private(set) var receivedCheckpoints: [CoinLedgerSyncCheckpoint?] = []

    init(results: [Result<CoinLedgerSyncEngineResult, Error>]) {
        self.results = results
    }

    func synchronize(
        accountSessionID: String,
        checkpoint: CoinLedgerSyncCheckpoint?
    ) async throws -> CoinLedgerSyncEngineResult {
        receivedCheckpoints.append(checkpoint)
        guard !results.isEmpty else {
            throw CoinLedgerSyncProviderError.syncUnavailable
        }
        let result = results.removeFirst()
        switch result {
        case .success(let value):
            return CoinLedgerSyncEngineResult(
                checkpoint: value.checkpoint.replacingAccountSessionID(accountSessionID),
                deletionEvidence: value.deletionEvidence
            )
        case .failure(let error):
            throw error
        }
    }
}

private actor CoinLedgerSyncCheckpointStoreFake: CoinLedgerSyncCheckpointRepository {
    private(set) var checkpoint: CoinLedgerSyncCheckpoint?

    init(checkpoint: CoinLedgerSyncCheckpoint? = nil) {
        self.checkpoint = checkpoint
    }

    func loadCheckpoint() async throws -> CoinLedgerSyncCheckpoint? { checkpoint }
    func saveCheckpoint(_ checkpoint: CoinLedgerSyncCheckpoint) async throws {
        self.checkpoint = checkpoint
    }
    func clearCheckpoint() async throws { checkpoint = nil }
}

private actor CoinBalanceStoreFake: CoinBalanceSnapshotRepository {
    private(set) var snapshot: CoinBalanceSnapshot?

    init(snapshot: CoinBalanceSnapshot? = nil) {
        self.snapshot = snapshot
    }

    func loadCoinBalanceSnapshot() async throws -> CoinBalanceSnapshot? { snapshot }
    func saveCoinBalanceSnapshot(_ snapshot: CoinBalanceSnapshot) async throws {
        self.snapshot = snapshot
    }
}

private actor CoinLedgerDatabaseUnusedFake: CoinLedgerCloudDatabase {
    func fetch(_: CoinLedgerFetchRequest) async throws -> [CloudKitRecordSnapshot] { [] }
    func modify(_: CoinLedgerModifyRequest) async throws -> [CloudKitRecordSnapshot] {
        throw CoinLedgerDatabaseError.unexpectedRequest
    }
}

private actor RuntimeSyncQueue {
    private var results: [CoinLedgerSyncProviderResult]
    private(set) var callCount = 0

    init(results: [CoinLedgerSyncProviderResult]) { self.results = results }

    func next() throws -> CoinLedgerSyncProviderResult {
        callCount += 1
        guard !results.isEmpty else { throw CoinLedgerSyncProviderError.syncUnavailable }
        return results.removeFirst()
    }
}

private actor ReconciledCommandRecorder {
    private(set) var commandIDs: [UUID] = []
    func record(_ commandIDs: [UUID]) { self.commandIDs.append(contentsOf: commandIDs) }
}
