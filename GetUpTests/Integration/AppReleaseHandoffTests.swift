import Foundation
import Testing
@testable import GetUp

@Suite("App release handoff")
@MainActor
struct AppReleaseHandoffTests {
    @Test("App claim persists processing, then completion until explicit acknowledgement")
    func coordinatorPersistsCompletionUntilAcknowledged() async throws {
        let directory = try makeHandoffDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routes = PendingAppRouteRepository(containerURL: directory)
        let route = try makeReleaseRoute()
        try await routes.save(route)
        let coordinator = AppReleaseHandoffCoordinator(
            routes: routes,
            activeOccurrenceIDs: { _ in ["occurrence-701"] },
            execute: { _, _ in .completed(
                fundingSource: .monthlyFree,
                remainingRestrictionCount: 0
            ) }
        )

        let claimed = try #require(await coordinator.claim(at: Self.now))
        #expect(claimed.state == .processing)
        #expect(try await routes.load()?.state == .processing)
        let terminal = try #require(await coordinator.process(
            claimed,
            context: .initialClaim,
            at: Self.now.addingTimeInterval(1)
        ))
        #expect(terminal.terminalOutcome == .completed)
        #expect(try await routes.load()?.terminalOutcome == .completed)
        _ = try await coordinator.markPresented(
            routeID: route.routeID,
            at: Self.now.addingTimeInterval(2)
        )
        try await coordinator.acknowledge(
            routeID: route.routeID,
            at: Self.now.addingTimeInterval(3)
        )
        #expect(try await routes.load() == nil)
    }

    @Test("A retryable handoff restarts only the same persisted command")
    func coordinatorRetriesSameCommand() async throws {
        let directory = try makeHandoffDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routes = PendingAppRouteRepository(containerURL: directory)
        let route = try makeReleaseRoute()
        try await routes.save(route)
        let executor = SequencedHandoffExecutor(results: [
            .failed(.transientRetryable(retryAfter: Self.now.addingTimeInterval(30))),
            .completed(fundingSource: .purchased, remainingRestrictionCount: 0),
        ])
        let coordinator = AppReleaseHandoffCoordinator(
            routes: routes,
            activeOccurrenceIDs: { _ in ["occurrence-701"] },
            execute: { route, _ in await executor.execute(route.commandID!) }
        )
        let claimed = try #require(await coordinator.claim(at: Self.now))
        _ = try await coordinator.process(
            claimed, context: .initialClaim, at: Self.now.addingTimeInterval(1)
        )
        #expect(try await coordinator.retry(
            routeID: route.routeID, at: Self.now.addingTimeInterval(29)
        ) == nil)
        let restarted = try #require(await coordinator.retry(
            routeID: route.routeID, at: Self.now.addingTimeInterval(30)
        ))
        #expect(restarted.commandID == route.commandID)
        _ = try await coordinator.process(
            restarted, context: .initialClaim, at: Self.now.addingTimeInterval(31)
        )
        #expect(try await routes.load()?.terminalOutcome == .completed)
        #expect(await executor.commandIDs == [Self.commandID, Self.commandID])
    }

    @Test("Only a resumed processing handoff may expose an interrupted retry")
    func coordinatorClassifiesForegroundInterruption() async throws {
        let directory = try makeHandoffDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let routes = PendingAppRouteRepository(containerURL: directory)
        try await routes.save(makeReleaseRoute())
        let coordinator = AppReleaseHandoffCoordinator(
            routes: routes,
            activeOccurrenceIDs: { _ in ["occurrence-701"] },
            execute: { _, _ in .interruptedUnresolved }
        )
        let claimed = try #require(await coordinator.claim(at: Self.now))
        _ = try await coordinator.process(
            claimed, context: .initialClaim, at: Self.now.addingTimeInterval(1)
        )
        #expect(try await routes.load()?.state == .processing)
        let resumed = try #require(await coordinator.claim(
            at: Self.now.addingTimeInterval(2)
        ))
        _ = try await coordinator.process(
            resumed,
            context: .foregroundReconciliation,
            at: Self.now.addingTimeInterval(3)
        )
        #expect(try await routes.load()?.terminalOutcome == .retryable)
    }

    @Test("A claimed handoff starts processing and suppresses duplicate execution")
    func processingSuppressesDuplicateExecution() async {
        let executor = HeldHandoffExecutor()
        let model = ActiveRestrictionReleaseHandoffModel(
            commandID: Self.commandID,
            execute: { commandID in await executor.execute(commandID) }
        )

        #expect(model.phase == .processing)
        #expect(!model.canRetry(at: Self.now))

        let first = Task { await model.process(context: .initialClaim) }
        await executor.waitUntilRequested()
        await model.process(context: .initialClaim)

        #expect(await executor.commandIDs == [Self.commandID])
        #expect(model.phase == .processing)
        #expect(!model.canRetry(at: Self.now))

        await executor.finish(with: .failed(.outcomeUnknown))
        await first.value
    }

    @Test("Verified read-back and ledger commit are required for completion")
    func verifiedCompletionTransitionsToCompleted() async {
        let model = makeModel(result: .completed(
            fundingSource: .monthlyFree,
            remainingRestrictionCount: 1
        ))

        await model.process(context: .initialClaim)

        #expect(model.phase == .completed(
            fundingSource: .monthlyFree,
            remainingRestrictionCount: 1
        ))
        #expect(!model.canRetry(at: Self.now))
    }

    @Test("A transient failure exposes retry only after retryAfter")
    func transientFailureHonorsRetryAfter() async {
        let retryAfter = Self.now.addingTimeInterval(30)
        let model = makeModel(result: .failed(.transientRetryable(
            retryAfter: retryAfter
        )))

        await model.process(context: .initialClaim)

        #expect(model.phase == .retryable(retryAfter: retryAfter))
        #expect(!model.canRetry(at: retryAfter.addingTimeInterval(-1)))
        #expect(model.canRetry(at: retryAfter))
    }

    @Test("An unknown outcome remains processing while reconciliation is unresolved")
    func unknownOutcomeDoesNotExposeRetry() async {
        let model = makeModel(result: .failed(.outcomeUnknown))

        await model.process(context: .initialClaim)

        #expect(model.phase == .processing)
        #expect(!model.canRetry(at: Self.now.addingTimeInterval(3_600)))
    }

    @Test("Account and ledger failures reuse the recovery destination")
    func accountFailureRequiresRecovery() async {
        let model = makeModel(result: .failed(.accountOrLedgerRecovery))

        await model.process(context: .initialClaim)

        #expect(model.phase == .recoveryRequired)
        #expect(!model.canRetry(at: Self.now))
    }

    @Test("Confirmed zero balance transitions directly to insufficient")
    func zeroBalanceTransitionsToInsufficient() async {
        let model = makeModel(result: .failed(.insufficientBalance))

        await model.process(context: .initialClaim)

        #expect(model.phase == .insufficient)
        #expect(!model.canRetry(at: Self.now))
    }

    @Test("Only foreground reconciliation turns an interrupted command retryable")
    func interruptedCommandRequiresForegroundEvidence() async {
        let initial = makeModel(result: .interruptedUnresolved)
        await initial.process(context: .initialClaim)
        #expect(initial.phase == .processing)
        #expect(!initial.canRetry(at: Self.now))

        let foreground = makeModel(result: .interruptedUnresolved)
        await foreground.process(context: .foregroundReconciliation)
        #expect(foreground.phase == .retryable(retryAfter: nil))
        #expect(foreground.canRetry(at: Self.now))
    }

    @Test("Retry reuses the same command and never runs before retryAfter")
    func retryReusesCommandID() async {
        let retryAfter = Self.now.addingTimeInterval(30)
        let executor = SequencedHandoffExecutor(results: [
            .failed(.transientRetryable(retryAfter: retryAfter)),
            .completed(fundingSource: .purchased, remainingRestrictionCount: 0),
        ])
        let model = ActiveRestrictionReleaseHandoffModel(
            commandID: Self.commandID,
            execute: { commandID in await executor.execute(commandID) }
        )
        await model.process(context: .initialClaim)

        await model.retry(at: retryAfter.addingTimeInterval(-1))
        #expect(await executor.commandIDs == [Self.commandID])

        await model.retry(at: retryAfter)
        #expect(await executor.commandIDs == [Self.commandID, Self.commandID])
        #expect(model.phase == .completed(
            fundingSource: .purchased,
            remainingRestrictionCount: 0
        ))
    }
}

private extension AppReleaseHandoffTests {
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000701")!
    static let now = Date(timeIntervalSince1970: 1_788_192_000)

    func makeHandoffDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func makeReleaseRoute() throws -> PendingAppRoute {
        try PendingAppRoute.releaseProcessing(
            routeID: UUID(uuidString: "00000000-0000-4000-8000-000000000702")!,
            commandID: Self.commandID,
            createdAt: Self.now,
            occurrenceID: "occurrence-701"
        )
    }

    func makeModel(
        result: ReleaseHandoffExecutionResult
    ) -> ActiveRestrictionReleaseHandoffModel {
        ActiveRestrictionReleaseHandoffModel(
            commandID: Self.commandID,
            execute: { _ in result }
        )
    }
}

private actor HeldHandoffExecutor {
    private var continuation: CheckedContinuation<ReleaseHandoffExecutionResult, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private(set) var commandIDs: [UUID] = []

    func execute(_ commandID: UUID) async -> ReleaseHandoffExecutionResult {
        commandIDs.append(commandID)
        waiters.forEach { $0.resume() }
        waiters = []
        return await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilRequested() async {
        if !commandIDs.isEmpty { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func finish(with result: ReleaseHandoffExecutionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor SequencedHandoffExecutor {
    private var results: [ReleaseHandoffExecutionResult]
    private(set) var commandIDs: [UUID] = []

    init(results: [ReleaseHandoffExecutionResult]) {
        self.results = results
    }

    func execute(_ commandID: UUID) -> ReleaseHandoffExecutionResult {
        commandIDs.append(commandID)
        return results.removeFirst()
    }
}
