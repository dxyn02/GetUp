import Foundation
import Testing
@testable import GetUp

@Suite("Rule release coordinator")
struct RuleReleaseCoordinatorTests {
    @Test("Unknown applied write retains local evidence for reconciliation")
    func unknownAppliedWrite() async throws {
        let fixture = try CoordinatorFixture()
        await fixture.ledger.failAppliedWrite()
        await expectFailure {
            try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
        }
        #expect(await fixture.exceptionRepository.exceptions == [fixture.exception])
        #expect(await fixture.ledger.compensationCount == 0)
        #expect(await fixture.recorder.operations.last == .markApplied)
    }

    @Test("Compensation failure is explicitly returned as reconciliation required")
    func compensationFailure() async throws {
        let fixture = try CoordinatorFixture(exceptionWriteFailsOnAttempt: 1)
        await fixture.ledger.failCompensation()
        do {
            _ = try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
            Issue.record("Expected reconciliation")
        } catch {
            #expect(error as? RuleReleaseCoordinationError == .reconciliationRequired(commandID: fixture.exception.commandID))
        }
        #expect(await fixture.ledger.command.state == .reserved)
    }

    @Test("An expired occurrence is compensated before writing any local exception")
    func expiredReservation() async throws {
        let fixture = try CoordinatorFixture(now: Self.now.addingTimeInterval(3600))
        await expectFailure {
            try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
        }
        #expect(await fixture.recorder.operations == [.loadExceptions, .compensate])
        #expect(await fixture.ledger.command.state == .compensated)
    }

    @Test("Two coordinators sharing real storage preserve success across a busy retry and first-command rollback", arguments: [false, true])
    func sharedStorageCoordination(firstFails: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstStore = AppGroupReleaseExceptionRepository(containerURL: directory)
        let secondStore = AppGroupReleaseExceptionRepository(containerURL: directory)
        let gate = ReleaseApplicationGate()
        let recorder = ReleaseOperationRecorder()
        let commands = try (0..<2).map { index in
            try ReleaseCommand.requested(commandID: UUID(), occurrenceID: "shared-\(index)", ruleID: UUID(),
                requestedFrom: .app, at: Self.now).transitioning(to: .reserved, fundingSource: .monthlyFree, at: Self.now)
        }
        let exceptions = try commands.map {
            try ReleaseException(commandID: $0.commandID, occurrenceID: $0.occurrenceID, ruleID: $0.ruleID,
                ruleRevision: 1, effectiveAt: Self.now, expiresAt: Self.now.addingTimeInterval(3600))
        }
        let firstLedger = ReleaseLedgerRepositorySpy(command: commands[0], recorder: recorder, commitFails: firstFails)
        let secondLedger = ReleaseLedgerRepositorySpy(command: commands[1], recorder: recorder, commitFails: false)
        let first = RuleReleaseCoordinator(exceptionRepository: firstStore, ledgerRepository: firstLedger,
            applyRestrictions: {
                await gate.pauseFirstApplication()
                let current = try await firstStore.loadReleaseExceptions()
                await gate.record(current)
                return RuleReleaseApplication(desiredLiveActivity: nil)
            }, reconcileLiveActivity: { _ in .noChange }, clock: FixedClock(now: Self.now), coordinationDirectory: directory)
        let second = RuleReleaseCoordinator(exceptionRepository: secondStore, ledgerRepository: secondLedger,
            applyRestrictions: {
                let current = try await secondStore.loadReleaseExceptions()
                await gate.record(current)
                return RuleReleaseApplication(desiredLiveActivity: nil)
            }, reconcileLiveActivity: { _ in .noChange }, clock: FixedClock(now: Self.now), coordinationDirectory: directory)
        let firstTask = Task {
            try await first.coordinate(reservation: CoinReleaseReservation(command: commands[0], allowance: nil, account: nil),
                exception: exceptions[0])
        }
        await gate.waitForApplication()
        await expectFailure {
            try await second.coordinate(reservation: CoinReleaseReservation(command: commands[1], allowance: nil, account: nil),
                exception: exceptions[1])
        }
        #expect(await secondLedger.compensationCount == 0)
        await gate.resume()
        _ = await firstTask.result
        let result = try await second.coordinate(
            reservation: CoinReleaseReservation(command: commands[1], allowance: nil, account: nil), exception: exceptions[1])
        let expected = firstFails ? [exceptions[1]] : exceptions
        #expect(try await Set(secondStore.loadReleaseExceptions()) == Set(expected))
        #expect(await gate.lastApplied == Set(expected.map(\.commandID)))
        #expect(result.committedCommand.state == .committed)
        #expect(await firstLedger.command.state == (firstFails ? .compensated : .committed))
    }

    @Test("Unknown commit preserves local release and does not compensate")
    func unknownCommit() async throws {
        let fixture = try CoordinatorFixture(commitError: .database(.resultUnknown))
        await expectFailure {
            try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
        }
        #expect(await fixture.exceptionRepository.exceptions == [fixture.exception])
        #expect(await fixture.ledger.compensationCount == 0)
        #expect(await fixture.ledger.command.state == .applied)
    }

    @Test("Failed local rollback leaves the reservation for reconciliation")
    func rollbackFailure() async throws {
        let fixture = try CoordinatorFixture(exceptionWriteFailsOnAttempt: 2, commitFails: true)
        await expectFailure {
            try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
        }
        #expect(await fixture.exceptionRepository.exceptions == [fixture.exception])
        #expect(await fixture.ledger.compensationCount == 0)
    }

    @Test("A stale retry after commit or compensation cannot recreate or remove an exception", arguments: [true, false])
    func terminalRetry(committed: Bool) async throws {
        let fixture = try CoordinatorFixture(commitFails: !committed)
        _ = try? await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
        let before = await fixture.recorder.operations
        await expectFailure {
            try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
        }
        #expect(await fixture.recorder.operations == before)
        #expect(await fixture.exceptionRepository.exceptions == (committed ? [fixture.exception] : []))
    }

    @Test("Busy local lease causes no side effects and releasing it permits a retry")
    func busyLease() async throws {
        let fixture = try CoordinatorFixture()
        do {
            let lease = try RuleReleaseLocalLease(directory: fixture.directory)
            await expectFailure {
                try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
            }
            withExtendedLifetime(lease) {}
            #expect(await fixture.recorder.operations.isEmpty)
        }
        let result = try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
        #expect(result.committedCommand.state == .committed)
    }

    @Test("A failed release preserves another successful occurrence during owner-scoped rollback")
    func preservesOtherOccurrence() async throws {
        let fixture = try CoordinatorFixture(commitFails: true)
        let other = try ReleaseException(commandID: UUID(), occurrenceID: "other", ruleID: UUID(),
            ruleRevision: 1, effectiveAt: Self.now, expiresAt: Self.now.addingTimeInterval(3600))
        _ = try await fixture.exceptionRepository.insertReleaseException(other)
        await expectFailure {
            try await fixture.coordinator.coordinate(reservation: fixture.reservation, exception: fixture.exception)
        }
        #expect(await fixture.exceptionRepository.exceptions == [other])
        #expect(await fixture.recorder.operations.contains(.applyRestrictions(2)))
        #expect(await fixture.recorder.operations.contains(.applyRestrictions(1)))
        #expect(await fixture.ledger.command.state == .compensated)
    }

    @Test("A successful release persists, applies, commits, then updates the representative activity")
    func successfulReleaseUpdatesRepresentativeActivity() async throws {
        let fixture = try CoordinatorFixture(desiredActivity: .activity(occurrenceID: "occurrence-2"))

        let result = try await fixture.coordinator.coordinate(
            reservation: fixture.reservation,
            exception: fixture.exception
        )

        #expect(result.committedCommand.state == .committed)
        #expect(result.liveActivityResult.actions == [.update(Self.activityID)])
        #expect(await fixture.recorder.operations == [
            .loadExceptions,
            .saveExceptions(1),
            .applyRestrictions(1),
            .markApplied,
            .commit,
            .reconcileLiveActivity("occurrence-2"),
        ])
    }

    @Test("A successful release ends the activity when no restriction remains")
    func successfulReleaseEndsFinalActivity() async throws {
        let fixture = try CoordinatorFixture(desiredActivity: nil)

        let result = try await fixture.coordinator.coordinate(
            reservation: fixture.reservation,
            exception: fixture.exception
        )

        #expect(result.committedCommand.state == .committed)
        #expect(result.liveActivityResult.actions == [.end(Self.activityID)])
        #expect(await fixture.recorder.operations.last == .reconcileLiveActivity(nil))
    }

    @Test("An App Group exception write failure compensates without changing restrictions")
    func exceptionWriteFailureCompensatesReservation() async throws {
        let fixture = try CoordinatorFixture(exceptionWriteFailsOnAttempt: 1)

        await expectFailure {
            try await fixture.coordinator.coordinate(
                reservation: fixture.reservation,
                exception: fixture.exception
            )
        }

        #expect(await fixture.ledger.command.state == .compensated)
        #expect(await fixture.exceptionRepository.exceptions.isEmpty)
        #expect(await fixture.recorder.operations == [
            .loadExceptions,
            .saveExceptions(1),
            .compensate,
        ])
    }

    @Test("A Managed Settings failure removes the exception, restores restrictions, and compensates")
    func restrictionWriteFailureRollsBackAndCompensates() async throws {
        let fixture = try CoordinatorFixture(restrictionWriteFailsOnAttempt: 1)

        await expectFailure {
            try await fixture.coordinator.coordinate(
                reservation: fixture.reservation,
                exception: fixture.exception
            )
        }

        #expect(await fixture.ledger.command.state == .compensated)
        #expect(await fixture.exceptionRepository.exceptions.isEmpty)
        #expect(await fixture.recorder.operations == [
            .loadExceptions,
            .saveExceptions(1),
            .applyRestrictions(1),
            .saveExceptions(0),
            .applyRestrictions(0),
            .compensate,
        ])
    }

    @Test("A definite CloudKit commit failure rolls back local state and compensates")
    func commitFailureRollsBackAndCompensates() async throws {
        let fixture = try CoordinatorFixture(commitFails: true)

        await expectFailure {
            try await fixture.coordinator.coordinate(
                reservation: fixture.reservation,
                exception: fixture.exception
            )
        }

        #expect(await fixture.ledger.command.state == .compensated)
        #expect(await fixture.exceptionRepository.exceptions.isEmpty)
        #expect(await fixture.recorder.operations == [
            .loadExceptions,
            .saveExceptions(1),
            .applyRestrictions(1),
            .markApplied,
            .commit,
            .saveExceptions(0),
            .applyRestrictions(0),
            .compensate,
        ])
    }

    @Test("ActivityKit failure is reported without reverting a committed release")
    func activityFailureIsNonFatal() async throws {
        let fixture = try CoordinatorFixture(
            liveActivityResult: LiveActivityCoordinationResult(
                actions: [],
                failureCodes: [.activityUpdateFailed]
            )
        )

        let result = try await fixture.coordinator.coordinate(
            reservation: fixture.reservation,
            exception: fixture.exception
        )

        #expect(result.committedCommand.state == .committed)
        #expect(result.liveActivityResult.failureCodes == [.activityUpdateFailed])
        #expect(await fixture.exceptionRepository.exceptions == [fixture.exception])
        #expect(await fixture.ledger.compensationCount == 0)
    }
}

private extension RuleReleaseCoordinatorTests {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000601")!
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000602")!
    static let activityID = UUID(uuidString: "00000000-0000-4000-8000-000000000603")!
    static let representativeActivity = try! RestrictionLiveActivitySnapshot.activity(
        occurrenceID: "occurrence-2"
    )

    func expectFailure(
        _ operation: () async throws -> some Sendable
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected release coordination to fail")
        } catch {
            // The failure boundary is asserted through rollback side effects.
        }
    }
}

private final class CoordinatorFixture {
    let directory: URL
    let recorder: ReleaseOperationRecorder
    let exceptionRepository: ReleaseExceptionRepositorySpy
    let ledger: ReleaseLedgerRepositorySpy
    let coordinator: RuleReleaseCoordinator
    let reservation: CoinReleaseReservation
    let exception: ReleaseException

    init(
        exceptionWriteFailsOnAttempt: Int? = nil,
        restrictionWriteFailsOnAttempt: Int? = nil,
        commitFails: Bool = false,
        commitError: CoinLedgerRepositoryError? = nil,
        now: Date = RuleReleaseCoordinatorTests.now,
        desiredActivity: RestrictionLiveActivitySnapshot? =
            RuleReleaseCoordinatorTests.representativeActivity,
        liveActivityResult: LiveActivityCoordinationResult = LiveActivityCoordinationResult(
            actions: [.update(RuleReleaseCoordinatorTests.activityID)],
            failureCodes: []
        )
    ) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let recorder = ReleaseOperationRecorder()
        let reservedCommand = try ReleaseCommand.requested(
            commandID: RuleReleaseCoordinatorTests.commandID,
            occurrenceID: "occurrence-1",
            ruleID: RuleReleaseCoordinatorTests.ruleID,
            requestedFrom: .app,
            at: RuleReleaseCoordinatorTests.now
        ).transitioning(
            to: .reserved,
            fundingSource: .monthlyFree,
            at: RuleReleaseCoordinatorTests.now
        )
        let exception = try ReleaseException(
            commandID: reservedCommand.commandID,
            occurrenceID: reservedCommand.occurrenceID,
            ruleID: reservedCommand.ruleID,
            ruleRevision: 3,
            effectiveAt: RuleReleaseCoordinatorTests.now,
            expiresAt: RuleReleaseCoordinatorTests.now.addingTimeInterval(3_600)
        )
        let exceptionRepository = ReleaseExceptionRepositorySpy(
            recorder: recorder,
            writeFailsOnAttempt: exceptionWriteFailsOnAttempt
        )
        let ledger = ReleaseLedgerRepositorySpy(
            command: reservedCommand,
            recorder: recorder,
            commitFails: commitFails,
            commitError: commitError
        )
        let restrictionWriter = ReleaseRestrictionWriterSpy(
            recorder: recorder,
            failureOnAttempt: restrictionWriteFailsOnAttempt,
            desiredActivity: desiredActivity
        )
        let activity = ReleaseLiveActivitySpy(
            recorder: recorder,
            result: desiredActivity == nil
                ? LiveActivityCoordinationResult(
                    actions: [.end(RuleReleaseCoordinatorTests.activityID)],
                    failureCodes: liveActivityResult.failureCodes
                )
                : liveActivityResult
        )

        self.recorder = recorder
        self.exceptionRepository = exceptionRepository
        self.ledger = ledger
        self.reservation = CoinReleaseReservation(
            command: reservedCommand,
            allowance: nil,
            account: nil
        )
        self.exception = exception
        self.coordinator = RuleReleaseCoordinator(
            exceptionRepository: exceptionRepository,
            ledgerRepository: ledger,
            applyRestrictions: {
                try await restrictionWriter.apply(exceptions: exceptionRepository.exceptions)
            },
            reconcileLiveActivity: { desiredActivity in
                await activity.reconcile(desiredActivity: desiredActivity)
            },
            clock: FixedClock(now: now),
            coordinationDirectory: directory
        )
    }

    deinit { try? FileManager.default.removeItem(at: directory) }
}

private enum ReleaseOperation: Equatable, Sendable {
    case loadExceptions
    case saveExceptions(Int)
    case applyRestrictions(Int)
    case markApplied
    case commit
    case compensate
    case reconcileLiveActivity(String?)
}

private actor ReleaseOperationRecorder {
    private(set) var operations: [ReleaseOperation] = []

    func record(_ operation: ReleaseOperation) {
        operations.append(operation)
    }
}

private actor ReleaseExceptionRepositorySpy: ReleaseExceptionRepository {
    private let recorder: ReleaseOperationRecorder
    private let writeFailsOnAttempt: Int?
    private var writeAttempt = 0
    private(set) var exceptions: [ReleaseException] = []

    init(recorder: ReleaseOperationRecorder, writeFailsOnAttempt: Int?) {
        self.recorder = recorder
        self.writeFailsOnAttempt = writeFailsOnAttempt
    }

    func loadReleaseExceptions() async throws -> [ReleaseException] {
        await recorder.record(.loadExceptions)
        return exceptions
    }

    func insertReleaseException(_ exception: ReleaseException) async throws -> [ReleaseException] {
        if let existing = exceptions.first(where: {
            $0.commandID == exception.commandID || $0.occurrenceID == exception.occurrenceID
        }) {
            guard existing == exception else { throw ReleaseExceptionRepositoryError.conflict }
            return exceptions
        }
        writeAttempt += 1
        await recorder.record(.saveExceptions(exceptions.count + 1))
        guard writeFailsOnAttempt != writeAttempt else { throw ReleaseExceptionRepositoryError.writeFailed }
        exceptions.append(exception)
        let result = exceptions
        return result
    }

    func removeReleaseException(commandID: UUID, occurrenceID: String) async throws -> [ReleaseException] {
        let next = exceptions.filter { !($0.commandID == commandID && $0.occurrenceID == occurrenceID) }
        guard next != exceptions else { return exceptions }
        writeAttempt += 1
        guard writeFailsOnAttempt != writeAttempt else { throw ReleaseExceptionRepositoryError.writeFailed }
        exceptions = next
        await recorder.record(.saveExceptions(next.count))
        return next
    }

    func saveReleaseExceptions(_ exceptions: [ReleaseException]) async throws {
        writeAttempt += 1
        await recorder.record(.saveExceptions(exceptions.count))
        guard writeFailsOnAttempt != writeAttempt else {
            throw ReleaseExceptionRepositoryError.writeFailed
        }
        self.exceptions = exceptions
    }
}

private actor ReleaseRestrictionWriterSpy {
    private let recorder: ReleaseOperationRecorder
    private let failureOnAttempt: Int?
    private let desiredActivity: RestrictionLiveActivitySnapshot?
    private var attempt = 0

    init(
        recorder: ReleaseOperationRecorder,
        failureOnAttempt: Int?,
        desiredActivity: RestrictionLiveActivitySnapshot?
    ) {
        self.recorder = recorder
        self.failureOnAttempt = failureOnAttempt
        self.desiredActivity = desiredActivity
    }

    func apply(exceptions: [ReleaseException]) async throws -> RuleReleaseApplication {
        attempt += 1
        await recorder.record(.applyRestrictions(exceptions.count))
        guard failureOnAttempt != attempt else {
            throw ReleaseCoordinatorFixtureError.restrictionWriteFailed
        }
        return RuleReleaseApplication(desiredLiveActivity: desiredActivity)
    }
}

private actor ReleaseLiveActivitySpy {
    private let recorder: ReleaseOperationRecorder
    private let result: LiveActivityCoordinationResult

    init(recorder: ReleaseOperationRecorder, result: LiveActivityCoordinationResult) {
        self.recorder = recorder
        self.result = result
    }

    func reconcile(
        desiredActivity: RestrictionLiveActivitySnapshot?
    ) async -> LiveActivityCoordinationResult {
        await recorder.record(
            .reconcileLiveActivity(desiredActivity?.contentState.occurrenceID)
        )
        return result
    }
}

private actor ReleaseLedgerRepositorySpy: CoinLedgerRepository {
    private let recorder: ReleaseOperationRecorder
    private let commitFails: Bool
    private let commitError: CoinLedgerRepositoryError?
    private(set) var command: ReleaseCommand
    private(set) var compensationCount = 0
    private var appliedWriteFails = false
    private var compensationFails = false

    func failAppliedWrite() { appliedWriteFails = true }
    func failCompensation() { compensationFails = true }

    init(
        command: ReleaseCommand,
        recorder: ReleaseOperationRecorder,
        commitFails: Bool,
        commitError: CoinLedgerRepositoryError? = nil
    ) {
        self.command = command
        self.recorder = recorder
        self.commitFails = commitFails
        self.commitError = commitError
    }

    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) async throws -> MonthlyAllowance {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func reserveMonthlyFree(
        _ request: MonthlyFreeReservationRequest
    ) async throws -> CoinReleaseReservation {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func reservePurchasedCoin(
        _ request: PurchasedCoinReservationRequest
    ) async throws -> CoinReleaseReservation {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }

    func fetchReleaseCommand(commandID: UUID) async throws -> ReleaseCommand? { command }

    func markReleaseApplied(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        await recorder.record(.markApplied)
        if appliedWriteFails { throw CoinLedgerRepositoryError.database(.resultUnknown) }
        command = try command.transitioning(to: .applied, at: date)
        return command
    }

    func commitRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        await recorder.record(.commit)
        if let commitError { throw commitError }
        guard !commitFails else {
            throw CoinLedgerRepositoryError.database(.serverUnavailable)
        }
        command = try command.transitioning(to: .committed, at: date)
        return command
    }

    func compensateRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        await recorder.record(.compensate)
        if compensationFails { throw CoinLedgerRepositoryError.database(.resultUnknown) }
        compensationCount += 1
        command = try command.transitioning(
            to: .compensating,
            failureCode: "release_coordination_failed",
            at: date
        ).transitioning(to: .compensated, at: date)
        return command
    }

    func grantPurchase(_ request: PurchaseGrantRequest) async throws -> PurchaseGrant {
        throw CoinLedgerRepositoryError.database(.unexpectedRequest)
    }
}

private enum ReleaseCoordinatorFixtureError: Error {
    case restrictionWriteFailed
}

private actor ReleaseApplicationGate {
    private var entered = false
    private var pause: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    private(set) var lastApplied: Set<UUID> = []

    func pauseFirstApplication() async {
        guard !entered else { return }
        entered = true
        await withCheckedContinuation { continuation in
            pause = continuation
            observer?.resume()
            observer = nil
        }
    }

    func waitForApplication() async {
        if entered { return }
        await withCheckedContinuation { observer = $0 }
    }

    func resume() { pause?.resume(); pause = nil }
    func record(_ exceptions: [ReleaseException]) { lastApplied = Set(exceptions.map(\.commandID)) }
}

private extension RestrictionLiveActivitySnapshot {
    static func activity(occurrenceID: String) throws -> RestrictionLiveActivitySnapshot {
        RestrictionLiveActivitySnapshot(
            attributes: RestrictionLiveActivityAttributes(
                activityID: RuleReleaseCoordinatorTests.activityID,
                restrictionStartedAt: RuleReleaseCoordinatorTests.now.addingTimeInterval(-600)
            ),
            contentState: try RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: occurrenceID,
                ruleDisplayName: "다음 규칙",
                endsAt: RuleReleaseCoordinatorTests.now.addingTimeInterval(7_200),
                remainingDistance: .known(meters: 100),
                distanceObservedAt: RuleReleaseCoordinatorTests.now,
                hasAdditionalRestrictions: false
            )
        )
    }
}
