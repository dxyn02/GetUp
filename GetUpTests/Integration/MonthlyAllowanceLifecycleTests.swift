import Foundation
import Testing
@testable import GetUp

@Suite("Monthly allowance app lifecycle", .serialized)
struct MonthlyAllowanceLifecycleTests {
    @Test("App UI fixture persists purchased coins and refreshes only free allowance")
    func appFixturePersistsAcrossSeoulMonthBoundary() throws {
        let root = try Self.makeFixtureDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = MonthlyAllowanceUITestFixtureStore(containerURL: root)
        let august = try #require(Self.date("2026-08-31T14:59:59Z"))
        let september = try #require(Self.date("2026-08-31T15:00:00Z"))

        let beforeBoundary = try store.balance(
            mode: .persistedOneRemaining,
            syncState: .current,
            now: august
        )
        let afterBoundary = try store.balance(
            mode: .persistedOneRemaining,
            syncState: .current,
            now: september
        )

        #expect(beforeBoundary.freeAvailable == 1)
        #expect(afterBoundary.freeAvailable == 2)
        #expect(afterBoundary.purchasedAvailable == 3)
        #expect(afterBoundary.currentMonthID == "2026-09")
    }

    @Test("Setup grants two while deletion reset suppresses only its current month")
    func setupAndResetFixturesRemainDistinct() throws {
        let setupRoot = try Self.makeFixtureDirectory()
        let resetRoot = try Self.makeFixtureDirectory()
        defer {
            try? FileManager.default.removeItem(at: setupRoot)
            try? FileManager.default.removeItem(at: resetRoot)
        }
        let august = try #require(Self.date("2026-08-24T07:00:00Z"))
        let september = try #require(Self.date("2026-08-31T15:00:00Z"))

        let setup = try MonthlyAllowanceUITestFixtureStore(containerURL: setupRoot)
            .balance(mode: .firstSetup, syncState: .current, now: august)
        let resetStore = MonthlyAllowanceUITestFixtureStore(containerURL: resetRoot)
        let reset = try resetStore.balance(
            mode: .deletionReset,
            syncState: .deletionConfirmed,
            now: august
        )
        let resumed = try resetStore.balance(
            mode: .deletionReset,
            syncState: .current,
            now: september
        )

        #expect(setup.freeAvailable == 2)
        #expect(setup.purchasedAvailable == 0)
        #expect(reset.freeAvailable == 0)
        #expect(reset.purchasedAvailable == 0)
        #expect(resumed.freeAvailable == 2)
        #expect(resumed.purchasedAvailable == 0)
    }

    @Test("First Shield request creates two and atomically reserves the free allowance first")
    func firstShieldFixtureCreatesAndReservesAllowance() throws {
        let now = try #require(Self.date("2026-08-24T07:00:00Z"))
        let fixture = try ShieldMonthlyAllowanceUITestFixture.firstRequest(now: now)

        #expect(fixture.initialBalance.freeAvailable == 2)
        #expect(fixture.balanceAfterAtomicReservation.freeAvailable == 1)
        #expect(fixture.initialBalance.purchasedAvailable == 3)
        #expect(fixture.balanceAfterAtomicReservation.purchasedAvailable == 3)
        #expect(fixture.initialBalance.currentMonthID == "2026-08")
        #expect(fixture.createsAllowanceOnRequest)
    }

    @Test("Seoul month boundary creates the new allowance only on the next foreground")
    func seoulBoundaryUsesLazyForegroundCreation() async throws {
        let clock = LiveActivityCoinWallClock(
            now: try #require(Self.date("2026-08-31T14:59:59Z"))
        )
        let harness = Self.makeHarness(clock: clock, epoch: Self.initialEpoch)

        _ = try await harness.coordinator.restore()
        #expect(await harness.repository.requestedMonthIDs == ["2026-08"])

        clock.advance(by: 1)
        #expect(MonthlyAllowancePolicy.monthID(containing: clock.now) == "2026-09")
        #expect(await harness.repository.requestedMonthIDs == ["2026-08"])

        _ = try await harness.coordinator.restore()
        #expect(await harness.repository.requestedMonthIDs == ["2026-08", "2026-09"])
        #expect(await harness.repository.allowance(for: "2026-09")?.available == 2)
    }

    @Test("Crossing midnight while the app is inactive performs no background grant")
    func midnightDoesNotScheduleBackgroundCreation() async throws {
        let clock = LiveActivityCoinWallClock(
            now: try #require(Self.date("2026-09-30T14:59:59Z"))
        )
        let harness = Self.makeHarness(clock: clock, epoch: Self.initialEpoch)

        clock.advance(by: 1)

        #expect(MonthlyAllowancePolicy.monthID(containing: clock.now) == "2026-10")
        #expect(await harness.repository.requestedMonthIDs.isEmpty)
        #expect(await harness.repository.allowance(for: "2026-10") == nil)

        _ = try await harness.coordinator.restore()
        #expect(await harness.repository.requestedMonthIDs == ["2026-10"])
    }

    @Test("Changing the device time zone cannot change the Seoul allowance month")
    func deviceTimeZoneChangeDoesNotChangeMonthID() async throws {
        let instant = try #require(Self.date("2026-09-30T15:30:00Z"))
        let clock = LiveActivityCoinWallClock(now: instant)
        let context = MonthlyAllowanceLifecycleContextSource(
            clock: clock,
            epoch: Self.initialEpoch,
            deviceTimeZone: try #require(TimeZone(identifier: "Pacific/Honolulu"))
        )
        let harness = Self.makeHarness(clock: clock, context: context)

        #expect(await context.deviceLocalMonthID() == "2026-09")
        _ = try await harness.coordinator.restore()

        await context.changeDeviceTimeZone(
            to: try #require(TimeZone(identifier: "Pacific/Kiritimati"))
        )
        #expect(await context.deviceLocalMonthID() == "2026-10")
        _ = try await harness.coordinator.restore()

        #expect(await harness.repository.requestedMonthIDs == ["2026-10"])
        #expect(await harness.repository.allowance(for: "2026-10")?.available == 2)
    }

    @Test("A reset epoch suppresses its month and resumes two grants next Seoul month")
    func resetMonthSuppressionResumesAtNextBoundary() async throws {
        let clock = LiveActivityCoinWallClock(
            now: try #require(Self.date("2026-09-15T00:00:00Z"))
        )
        let resetEpoch = LedgerEpoch(
            epochID: UUID(uuidString: "00000000-0000-4000-8000-000000000781")!,
            createdAt: clock.now,
            reason: .userConfirmedResetAfterDeletion,
            suppressedFreeMonthID: "2026-09",
            disclosureVersion: 1
        )
        let harness = Self.makeHarness(clock: clock, epoch: resetEpoch)

        _ = try await harness.coordinator.restore()
        #expect(await harness.repository.allowance(for: "2026-09")?.available == 0)

        clock.setNow(try #require(Self.date("2026-09-30T15:00:00Z")))
        #expect(await harness.repository.allowance(for: "2026-10") == nil)

        _ = try await harness.coordinator.restore()
        #expect(await harness.repository.allowance(for: "2026-10")?.available == 2)
        #expect(await harness.repository.requestedMonthIDs == ["2026-09", "2026-10"])
    }

    private static let initialEpoch = LedgerEpoch(
        epochID: UUID(uuidString: "00000000-0000-4000-8000-000000000780")!,
        createdAt: Date(timeIntervalSince1970: 1_778_000_000),
        reason: .initialSetup,
        suppressedFreeMonthID: nil,
        disclosureVersion: 1
    )

    private static func makeHarness(
        clock: LiveActivityCoinWallClock,
        epoch: LedgerEpoch
    ) -> MonthlyAllowanceLifecycleHarness {
        let context = MonthlyAllowanceLifecycleContextSource(
            clock: clock,
            epoch: epoch,
            deviceTimeZone: TimeZone(secondsFromGMT: 0)!
        )
        return makeHarness(clock: clock, context: context)
    }

    private static func makeHarness(
        clock: LiveActivityCoinWallClock,
        context: MonthlyAllowanceLifecycleContextSource
    ) -> MonthlyAllowanceLifecycleHarness {
        let repository = context.repository
        let service = MonthlyAllowanceService(repository: repository)
        let coordinator = AppLifecycleCoordinator(
            ruleRepository: EmptyMonthlyLifecycleRuleRepository(),
            scheduleManager: NoOpMonthlyLifecycleScheduleManager(),
            locationMonitor: NoOpMonthlyLifecycleLocationMonitor(),
            authorizationProvider: MonthlyLifecycleAuthorizationProvider(),
            ensureMonthlyAllowance: {
                let foreground = await context.foregroundContext()
                _ = try await service.ensureAllowanceForAppForeground(
                    monthID: foreground.monthID,
                    ledgerState: foreground.ledgerState,
                    existingAllowance: foreground.existingAllowance
                )
            },
            restoreRestriction: {
                RestrictionCoordinationResult(
                    event: .restoration,
                    decisions: [:],
                    appliedState: AppliedRestrictionState(activeRuleRevisions: []),
                    transitionMeasurement: nil
                )
            },
            clock: clock
        )
        return MonthlyAllowanceLifecycleHarness(
            repository: repository,
            coordinator: coordinator
        )
    }

    private static func date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    private static func makeFixtureDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("GetUpMonthlyAllowanceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}

private struct MonthlyAllowanceLifecycleHarness {
    let repository: MonthlyAllowanceLifecycleRepository
    let coordinator: AppLifecycleCoordinator
}

private actor MonthlyAllowanceLifecycleContextSource {
    let repository: MonthlyAllowanceLifecycleRepository

    private let clock: LiveActivityCoinWallClock
    private let epoch: LedgerEpoch
    private var deviceTimeZone: TimeZone

    init(
        clock: LiveActivityCoinWallClock,
        epoch: LedgerEpoch,
        deviceTimeZone: TimeZone
    ) {
        self.clock = clock
        self.epoch = epoch
        self.deviceTimeZone = deviceTimeZone
        repository = MonthlyAllowanceLifecycleRepository(clock: clock, epoch: epoch)
    }

    func foregroundContext() async -> MonthlyAllowanceForegroundContext {
        let monthID = MonthlyAllowancePolicy.monthID(containing: clock.now)
        return MonthlyAllowanceForegroundContext(
            monthID: monthID,
            ledgerState: .current(epoch: epoch),
            existingAllowance: await repository.allowance(for: monthID)
        )
    }

    func changeDeviceTimeZone(to timeZone: TimeZone) {
        deviceTimeZone = timeZone
    }

    func deviceLocalMonthID() -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = deviceTimeZone
        let components = calendar.dateComponents([.year, .month], from: clock.now)
        return String(
            format: "%04d-%02d",
            locale: Locale(identifier: "en_US_POSIX"),
            components.year ?? 0,
            components.month ?? 0
        )
    }
}

private actor MonthlyAllowanceLifecycleRepository: MonthlyAllowanceRepository {
    private let clock: LiveActivityCoinWallClock
    private let epoch: LedgerEpoch
    private var allowances: [String: MonthlyAllowance] = [:]
    private(set) var requestedMonthIDs: [String] = []

    init(clock: LiveActivityCoinWallClock, epoch: LedgerEpoch) {
        self.clock = clock
        self.epoch = epoch
    }

    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) throws -> MonthlyAllowance {
        if let existing = allowances[request.monthID] {
            return existing
        }
        guard request.epochID == epoch.epochID else {
            throw MonthlyAllowanceLifecycleTestError.epochMismatch
        }

        requestedMonthIDs.append(request.monthID)
        let allowance = try MonthlyAllowancePolicy.makeAllowance(
            monthID: request.monthID,
            ledgerEpoch: epoch,
            serverCreationDate: clock.now
        )
        allowances[request.monthID] = allowance
        return allowance
    }

    func allowance(for monthID: String) -> MonthlyAllowance? {
        allowances[monthID]
    }
}

private actor EmptyMonthlyLifecycleRuleRepository: RuleRepository {
    func loadRuleCollection() -> RestrictionRuleCollectionSnapshot? { nil }
    func saveRuleCollection(_: RestrictionRuleCollectionSnapshot) {}
    func deleteRuleCollection() {}
}

private actor NoOpMonthlyLifecycleScheduleManager: ScheduleManaging {
    func replaceSchedules(for _: RestrictionRuleSnapshot) {}
    func removeSchedules() {}
}

private actor NoOpMonthlyLifecycleLocationMonitor: LocationMonitoring {
    func replaceMonitoring(for _: RestrictionRuleSnapshot) {}
    func stopMonitoring() {}

    func refreshLocationCondition(
        for rule: RestrictionRuleSnapshot,
        source: LocationConditionSource
    ) -> LocationConditionSnapshot {
        TestFixtures.makeLocationCondition(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            observedAt: Date(),
            source: source
        )
    }
}

private struct MonthlyLifecycleAuthorizationProvider: AuthorizationProviding {
    func authorizationSnapshot() -> AuthorizationSnapshot {
        TestFixtures.makeAuthorization()
    }
}

private enum MonthlyAllowanceLifecycleTestError: Error {
    case epochMismatch
}
