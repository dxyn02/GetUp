import Foundation
import Testing
@testable import GetUp

@Suite("Live Activity location bridge", .serialized)
struct LiveActivityLocationBridgeTests {
    private static let latencyLimit: TimeInterval = 30

    @Test("Main-app trusted location updates distance within 30 seconds")
    func mainAppLocationUsesReceiptAsMeasurementStart() async throws {
        let current = try snapshot(distance: .unavailable, observedAt: nil)
        let manager = LiveActivityManagerFake(activities: [current])
        let coordinator = LiveActivityCoordinator(
            manager: manager,
            clock: FixedClock(now: Self.now)
        )
        let measurementClock = ContinuousClock()

        let trustedLocationReceivedAt = measurementClock.now
        let desired = try snapshot(
            contentState: LiveActivityContentPolicy.makeContentState(
                occurrence: Self.occurrence,
                ruleDisplayName: "집중 시간",
                radiusMeters: Self.radiusMeters,
                locationCondition: Self.trustedLocation,
                hasAdditionalRestrictions: false,
                now: Self.now
            )
        )
        let result = await coordinator.reconcile(
            context: .foreground,
            desiredActivity: desired
        )
        let distanceReflectedAt = measurementClock.now

        #expect(result.actions == [.update(Self.activityID)])
        #expect(await manager.activities.first?.contentState.remainingDistance == .known(meters: 300))
        #expect(
            trustedLocationReceivedAt.duration(to: distanceReflectedAt).seconds
                <= Self.latencyLimit
        )
    }

    @Test("Extension-only location waits for the next foreground measurement start")
    func extensionLocationUsesNextForegroundAsMeasurementStart() async throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        let current = try snapshot(distance: .unavailable, observedAt: nil)
        let manager = LiveActivityManagerFake(activities: [current])
        let coordinator = LiveActivityCoordinator(
            manager: manager,
            clock: FixedClock(now: Self.now)
        )

        try await repository.saveLocationCondition(Self.trustedLocation)

        #expect(await manager.operations.isEmpty)
        #expect(
            try await repository.loadLocationConditionCollection()?.conditions
                == [Self.trustedLocation]
        )

        let measurementClock = ContinuousClock()
        let foregroundBecameAdjustableAt = measurementClock.now
        let persistedLocation = try await repository
            .loadLocationConditionCollection()?.conditions.first
        let desired = try snapshot(
            contentState: LiveActivityContentPolicy.makeContentState(
                occurrence: Self.occurrence,
                ruleDisplayName: "집중 시간",
                radiusMeters: Self.radiusMeters,
                locationCondition: persistedLocation,
                hasAdditionalRestrictions: false,
                now: Self.now
            )
        )
        let result = await coordinator.reconcile(
            context: .foreground,
            desiredActivity: desired
        )
        let distanceReflectedAt = measurementClock.now

        #expect(result.actions == [.update(Self.activityID)])
        #expect(await manager.activities.first?.contentState.remainingDistance == .known(meters: 300))
        #expect(
            foregroundBecameAdjustableAt.duration(to: distanceReflectedAt).seconds
                <= Self.latencyLimit
        )
    }

    private func snapshot(
        distance: RestrictionLiveActivityDistance,
        observedAt: Date?
    ) throws -> RestrictionLiveActivitySnapshot {
        try snapshot(
            contentState: RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: Self.occurrence.id,
                ruleDisplayName: "집중 시간",
                endsAt: Self.occurrence.endAt,
                remainingDistance: distance,
                distanceObservedAt: observedAt,
                hasAdditionalRestrictions: false
            )
        )
    }

    private func snapshot(
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) throws -> RestrictionLiveActivitySnapshot {
        RestrictionLiveActivitySnapshot(
            attributes: RestrictionLiveActivityAttributes(
                activityID: Self.activityID,
                restrictionStartedAt: Self.occurrence.activatedAt
            ),
            contentState: contentState
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("getup-live-activity-location-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private static let now = Date(timeIntervalSince1970: 1_788_192_300)
    private static let radiusMeters = 1_000.0
    private static let ruleID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000401"
    )!
    private static let activityID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000402"
    )!
    private static let occurrence = try! RestrictionOccurrence(
        ruleID: ruleID,
        ruleRevision: 2,
        startAt: now.addingTimeInterval(-600),
        endAt: now.addingTimeInterval(3_600),
        activatedAt: now.addingTimeInterval(-590)
    )
    private static let trustedLocation = LocationConditionSnapshot(
        ruleID: ruleID,
        ruleRevision: 2,
        state: .inside,
        observedAt: now,
        distanceMeters: 700,
        horizontalAccuracyMeters: 10,
        source: .regionEvent
    )
}

private extension Duration {
    var seconds: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds)
            + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
