import Foundation
import Testing
@testable import GetUp

@Suite("Rule release coordinator")
struct RuleReleaseCoordinatorTests {
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

private struct CoordinatorFixture {
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
        desiredActivity: RestrictionLiveActivitySnapshot? =
            RuleReleaseCoordinatorTests.representativeActivity,
        liveActivityResult: LiveActivityCoordinationResult = LiveActivityCoordinationResult(
            actions: [.update(RuleReleaseCoordinatorTests.activityID)],
            failureCodes: []
        )
    ) throws {
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
            commitFails: commitFails
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
            applyRestrictions: { exceptions in
                try await restrictionWriter.apply(exceptions: exceptions)
            },
            reconcileLiveActivity: { desiredActivity in
                await activity.reconcile(desiredActivity: desiredActivity)
            },
            clock: FixedClock(now: RuleReleaseCoordinatorTests.now)
        )
    }
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
        guard writeFailsOnAttempt != writeAttempt else { throw ReleaseExceptionRepositoryError.writeFailed }
        exceptions.append(exception)
        let result = exceptions
        await recorder.record(.saveExceptions(result.count))
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
    private(set) var command: ReleaseCommand
    private(set) var compensationCount = 0

    init(
        command: ReleaseCommand,
        recorder: ReleaseOperationRecorder,
        commitFails: Bool
    ) {
        self.command = command
        self.recorder = recorder
        self.commitFails = commitFails
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
        command = try command.transitioning(to: .applied, at: date)
        return command
    }

    func commitRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        await recorder.record(.commit)
        guard !commitFails else {
            throw CoinLedgerRepositoryError.database(.serverUnavailable)
        }
        command = try command.transitioning(to: .committed, at: date)
        return command
    }

    func compensateRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand {
        await recorder.record(.compensate)
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
