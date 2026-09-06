import Foundation

enum ShieldReleaseConfirmation: Sendable {
    case confirmed(CoinReleaseReservation)
    case unconfirmed(commandID: UUID)
}

enum ShieldReleaseDeadlineOutcome: Equatable, Sendable {
    case released(commandID: UUID)
    case reconciliationRequired(commandID: UUID)
}

struct ShieldReleaseDeadlinePolicy: Sendable {
    let deadline: Duration
    let monotonicNow: @Sendable () -> ContinuousClock.Instant
    let attemptRelease: @Sendable (UUID) async throws -> ShieldReleaseConfirmation
    let applyConfirmedRelease: @Sendable (CoinReleaseReservation) async throws -> Void
    let reconcileUnapplied: @Sendable (UUID) async throws -> ReleaseCommand?
    let savePendingRoute: @Sendable (PendingAppRoute) async throws -> Void
    let makeRouteID: @Sendable () -> UUID
    let wallNow: @Sendable () -> Date
    let waitForDeadline: @Sendable (Duration) async -> Void

    init(
        deadline: Duration,
        monotonicNow: @escaping @Sendable () -> ContinuousClock.Instant,
        attemptRelease: @escaping @Sendable (UUID) async throws -> ShieldReleaseConfirmation,
        applyConfirmedRelease: @escaping @Sendable (CoinReleaseReservation) async throws -> Void,
        reconcileUnapplied: @escaping @Sendable (UUID) async throws -> ReleaseCommand?,
        savePendingRoute: @escaping @Sendable (PendingAppRoute) async throws -> Void,
        makeRouteID: @escaping @Sendable () -> UUID,
        wallNow: @escaping @Sendable () -> Date,
        waitForDeadline: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.deadline = deadline
        self.monotonicNow = monotonicNow
        self.attemptRelease = attemptRelease
        self.applyConfirmedRelease = applyConfirmedRelease
        self.reconcileUnapplied = reconcileUnapplied
        self.savePendingRoute = savePendingRoute
        self.makeRouteID = makeRouteID
        self.wallNow = wallNow
        self.waitForDeadline = waitForDeadline
    }

    func perform(commandID: UUID, occurrenceID: String) async throws -> ShieldReleaseDeadlineOutcome {
        let startedAt = monotonicNow()
        let raceResult = await race(commandID: commandID)
        let elapsed = startedAt.duration(to: monotonicNow())

        switch raceResult {
        case .confirmation(.confirmed(let reservation))
            where deadline > .zero && elapsed >= .zero && elapsed < deadline
                && reservation.command.commandID == commandID
                && reservation.command.occurrenceID == occurrenceID:
            do {
                try await applyConfirmedRelease(reservation)
                return .released(commandID: commandID)
            } catch {
                return try await failClosed(commandID: commandID, occurrenceID: occurrenceID)
            }
        case .confirmation(.unconfirmed), .confirmation(.confirmed), .timeout, .failure:
            return try await failClosed(commandID: commandID, occurrenceID: occurrenceID)
        }
    }

    func recoverInterrupted(commandID: UUID, occurrenceID: String) async throws
        -> ShieldReleaseDeadlineOutcome
    {
        try await failClosed(commandID: commandID, occurrenceID: occurrenceID)
    }

    private func failClosed(commandID: UUID, occurrenceID: String) async throws
        -> ShieldReleaseDeadlineOutcome
    {
        let route = try PendingAppRoute(
            routeID: makeRouteID(),
            destination: .reconciliation,
            createdAt: wallNow(),
            occurrenceID: occurrenceID,
            consumedAt: nil
        )

        do {
            _ = try await reconcileUnapplied(commandID)
        } catch {
            try await savePendingRoute(route)
            throw error
        }
        try await savePendingRoute(route)
        return .reconciliationRequired(commandID: commandID)
    }

    private func race(commandID: UUID) async -> DeadlineRaceResult {
        await withCheckedContinuation { continuation in
            let gate = DeadlineRaceGate(continuation: continuation)
            let attemptTask = Task {
                do {
                    await gate.resolve(.confirmation(try await attemptRelease(commandID)))
                } catch {
                    await gate.resolve(.failure)
                }
            }
            let timeoutTask = Task {
                await waitForDeadline(deadline)
                await gate.resolve(.timeout)
            }
            Task { await gate.register([attemptTask, timeoutTask]) }
        }
    }
}

private enum DeadlineRaceResult: Sendable {
    case confirmation(ShieldReleaseConfirmation)
    case timeout
    case failure
}

private actor DeadlineRaceGate {
    private var continuation: CheckedContinuation<DeadlineRaceResult, Never>?
    private var tasks: [Task<Void, Never>] = []
    private var isResolved = false

    init(continuation: CheckedContinuation<DeadlineRaceResult, Never>) {
        self.continuation = continuation
    }

    func register(_ tasks: [Task<Void, Never>]) {
        guard !isResolved else {
            tasks.forEach { $0.cancel() }
            return
        }
        self.tasks = tasks
    }

    func resolve(_ result: DeadlineRaceResult) {
        guard !isResolved else { return }
        isResolved = true
        continuation?.resume(returning: result)
        continuation = nil
        tasks.forEach { $0.cancel() }
        tasks = []
    }
}
