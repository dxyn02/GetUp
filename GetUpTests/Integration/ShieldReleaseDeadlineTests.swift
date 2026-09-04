import Foundation
import Testing
@testable import GetUp

@Suite("Shield release deadline")
struct ShieldReleaseDeadlineTests {
    @Test("A CloudKit confirmation at 4.9 seconds can apply the release")
    func confirmationBeforeDeadlineAppliesRelease() async throws {
        let fixture = try DeadlineFixture(timing: .confirmedAtFourPointNineSeconds)

        let outcome = try await fixture.policy.perform(
            commandID: Self.commandID,
            occurrenceID: Self.occurrenceID
        )

        #expect(outcome == .released(commandID: Self.commandID))
        #expect(await fixture.ledger.appliedCommandIDs == [Self.commandID])
        #expect(await fixture.ledger.reconciledCommandIDs.isEmpty)
        #expect(await fixture.routes.savedRoutes.isEmpty)
        #expect(await fixture.ledger.unappliedDeduction == 0)
    }

    @Test("An unconfirmed result at exactly five seconds fails closed")
    func exactDeadlineFailsClosed() async throws {
        let fixture = try DeadlineFixture(timing: .unconfirmedAtFiveSeconds)

        let outcome = try await fixture.policy.perform(
            commandID: Self.commandID,
            occurrenceID: Self.occurrenceID
        )

        #expect(outcome == .reconciliationRequired(commandID: Self.commandID))
        #expect(await fixture.ledger.appliedCommandIDs.isEmpty)
        #expect(await fixture.ledger.reconciledCommandIDs == [Self.commandID])
        #expect(await fixture.routes.destinations == [.reconciliation])
        #expect(await fixture.routes.occurrenceIDs == [Self.occurrenceID])
        #expect(await fixture.ledger.unappliedDeduction == 0)
    }

    @Test("A commit confirmed after five seconds never applies and is compensated")
    func lateCommitIsCompensatedWithoutApplyingRelease() async throws {
        let fixture = try DeadlineFixture(timing: .committedAfterDeadline)

        let outcome = try await fixture.policy.perform(
            commandID: Self.commandID,
            occurrenceID: Self.occurrenceID
        )

        #expect(outcome == .reconciliationRequired(commandID: Self.commandID))
        #expect(await fixture.ledger.appliedCommandIDs.isEmpty)
        #expect(await fixture.ledger.reconciledCommandIDs == [Self.commandID])
        #expect(await fixture.ledger.command?.state == .compensated)
        #expect(await fixture.ledger.unappliedDeduction == 0)
        #expect(await fixture.routes.destinations == [.reconciliation])
    }

    @Test("The next process recovers an interrupted extension with the same command ID")
    func interruptedExtensionReconcilesSameCommand() async throws {
        let fixture = try DeadlineFixture(timing: .committedAfterDeadline)
        try await fixture.ledger.reserveForInterruptedExtension(commandID: Self.commandID)

        let outcome = try await fixture.policy.recoverInterrupted(
            commandID: Self.commandID,
            occurrenceID: Self.occurrenceID
        )

        #expect(outcome == .reconciliationRequired(commandID: Self.commandID))
        #expect(await fixture.ledger.attemptedCommandIDs.isEmpty)
        #expect(await fixture.ledger.appliedCommandIDs.isEmpty)
        #expect(await fixture.ledger.reconciledCommandIDs == [Self.commandID])
        #expect(await fixture.ledger.command?.commandID == Self.commandID)
        #expect(await fixture.ledger.command?.state == .compensated)
        #expect(await fixture.ledger.unappliedDeduction == 0)
        #expect(await fixture.routes.destinations == [.reconciliation])
    }
}

private extension ShieldReleaseDeadlineTests {
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000801")!
    static let routeID = UUID(uuidString: "00000000-0000-4000-8000-000000000802")!
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000803")!
    static let occurrenceID = "occurrence-deadline"
}

private struct DeadlineFixture {
    let ledger: DeadlineLedgerSpy
    let routes: DeadlineRouteSpy
    let policy: ShieldReleaseDeadlinePolicy

    init(timing: ShieldReleaseTimingFixture) throws {
        let monotonicClock = LiveActivityCoinMonotonicClock()
        let ledger = try DeadlineLedgerSpy(timing: timing, clock: monotonicClock)
        let routes = DeadlineRouteSpy()

        self.ledger = ledger
        self.routes = routes
        self.policy = ShieldReleaseDeadlinePolicy(
            deadline: ShieldReleaseTimingFixture.deadline,
            monotonicNow: { monotonicClock.now },
            attemptRelease: { commandID in
                try await ledger.attemptRelease(commandID: commandID)
            },
            applyConfirmedRelease: { reservation in
                try await ledger.applyConfirmed(reservation)
            },
            reconcileUnapplied: { commandID in
                try await ledger.reconcileUnapplied(commandID: commandID)
            },
            savePendingRoute: { route in
                try await routes.save(route)
            },
            makeRouteID: { ShieldReleaseDeadlineTests.routeID },
            wallNow: { ShieldReleaseDeadlineTests.now }
        )
    }
}

private actor DeadlineLedgerSpy {
    private let timing: ShieldReleaseTimingFixture
    private let clock: LiveActivityCoinMonotonicClock
    private(set) var command: ReleaseCommand?
    private(set) var attemptedCommandIDs: [UUID] = []
    private(set) var appliedCommandIDs: [UUID] = []
    private(set) var reconciledCommandIDs: [UUID] = []
    private var reservedQuantity = 0

    var unappliedDeduction: Int {
        reservedQuantity
    }

    init(
        timing: ShieldReleaseTimingFixture,
        clock: LiveActivityCoinMonotonicClock
    ) throws {
        self.timing = timing
        self.clock = clock
    }

    func attemptRelease(commandID: UUID) throws -> ShieldReleaseConfirmation {
        attemptedCommandIDs.append(commandID)
        clock.advance(by: timing.confirmationDelay)

        switch timing {
        case .confirmedAtFourPointNineSeconds, .committedAfterDeadline:
            let reservation = try reserve(commandID: commandID)
            return .confirmed(reservation)
        case .unconfirmedAtFiveSeconds:
            return .unconfirmed(commandID: commandID)
        }
    }

    func applyConfirmed(_ reservation: CoinReleaseReservation) throws {
        appliedCommandIDs.append(reservation.command.commandID)
        reservedQuantity -= 1
        command = try reservation.command
            .transitioning(
                to: .applied,
                at: ShieldReleaseDeadlineTests.now.addingTimeInterval(1)
            )
            .transitioning(
                to: .committed,
                at: ShieldReleaseDeadlineTests.now.addingTimeInterval(2)
            )
    }

    func reconcileUnapplied(commandID: UUID) throws -> ReleaseCommand? {
        reconciledCommandIDs.append(commandID)
        guard let current = command else {
            return nil
        }
        guard current.commandID == commandID else {
            throw DeadlineFixtureError.unexpectedCommand
        }

        reservedQuantity -= 1
        let reconciled = try current
            .transitioning(
                to: .compensating,
                failureCode: "shield_deadline_exceeded",
                at: ShieldReleaseDeadlineTests.now.addingTimeInterval(5)
            )
            .transitioning(
                to: .compensated,
                at: ShieldReleaseDeadlineTests.now.addingTimeInterval(6)
            )
        command = reconciled
        return reconciled
    }

    func reserveForInterruptedExtension(commandID: UUID) throws {
        _ = try reserve(commandID: commandID)
    }

    private func reserve(commandID: UUID) throws -> CoinReleaseReservation {
        let reserved = try ReleaseCommand.requested(
            commandID: commandID,
            occurrenceID: ShieldReleaseDeadlineTests.occurrenceID,
            ruleID: ShieldReleaseDeadlineTests.ruleID,
            requestedFrom: .shield,
            at: ShieldReleaseDeadlineTests.now
        ).transitioning(
            to: .reserved,
            fundingSource: .monthlyFree,
            at: ShieldReleaseDeadlineTests.now
        )
        command = reserved
        reservedQuantity += 1
        return CoinReleaseReservation(command: reserved, allowance: nil, account: nil)
    }
}

private actor DeadlineRouteSpy {
    private(set) var savedRoutes: [PendingAppRoute] = []

    var destinations: [PendingAppRouteDestination] {
        savedRoutes.map(\.destination)
    }

    var occurrenceIDs: [String?] {
        savedRoutes.map(\.occurrenceID)
    }

    func save(_ route: PendingAppRoute) throws {
        savedRoutes.append(route)
    }
}

private enum DeadlineFixtureError: Error {
    case unexpectedCommand
}
