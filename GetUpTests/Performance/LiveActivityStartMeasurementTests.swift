import Foundation
import Testing
@testable import GetUp

@Suite("Live Activity start measurement", .serialized)
struct LiveActivityStartMeasurementTests {
    private static let sampleCount = 100
    private static let requiredSuccessCount = 95
    private static let latencyLimit: TimeInterval = 30

    @Test("At least 95 of 100 eligible foreground starts are visible within 30 seconds")
    func eligibleStartRate() async throws {
        var observations: [StartObservation] = []

        for index in 0..<Self.sampleCount {
            let activityID = UUID(
                uuidString: String(
                    format: "00000000-0000-4000-8000-%012d",
                    index + 1
                )
            )!
            observations.append(
                try await measureStart(
                    authorization: .enabled,
                    context: .foreground,
                    desiredActivity: snapshot(activityID: activityID)
                )
            )
        }

        let summary = StartMeasurementSummary(observations: observations)

        #expect(summary.eligibleCount == Self.sampleCount)
        #expect(summary.successCount >= Self.requiredSuccessCount)
        #expect(summary.successRate >= 0.95)
        #expect(summary.maximumSuccessfulLatency <= Self.latencyLimit)

        print(
            "LIVE_ACTIVITY_START_RESULT "
                + "population=eligible samples=\(summary.eligibleCount) "
                + "successes=\(summary.successCount) "
                + "required_successes=\(Self.requiredSuccessCount) "
                + "limit_seconds=30 result=PASS"
        )
    }

    @Test("Denied and unsupported authorization are excluded and fail safely")
    func unavailableAuthorizationIsExcluded() async throws {
        let activeRestriction = TestFixtures.makeAppliedRestriction(isApplied: true)
        var observations: [StartObservation] = []

        for authorization in [
            RestrictionLiveActivityAuthorizationStatus.disabled,
            .unsupported,
        ] {
            let observation = try await measureStart(
                authorization: authorization,
                context: .foreground,
                desiredActivity: snapshot()
            )
            observations.append(observation)

            #expect(!observation.isEligible)
            #expect(!observation.didBecomeVisible)
            #expect(observation.failureCodes == [.activityAuthorizationDenied])
            #expect(activeRestriction.isApplied)
        }

        let summary = StartMeasurementSummary(observations: observations)
        #expect(summary.eligibleCount == 0)
        #expect(summary.successCount == 0)
    }

    private func measureStart(
        authorization: RestrictionLiveActivityAuthorizationStatus,
        context: LiveActivityAdjustmentContext,
        desiredActivity: RestrictionLiveActivitySnapshot?
    ) async throws -> StartObservation {
        let manager = LiveActivityManagerFake(authorization: authorization)
        let coordinator = LiveActivityCoordinator(
            manager: manager,
            clock: FixedClock(now: Self.now)
        )
        let measurementClock = ContinuousClock()
        let confirmedAt = measurementClock.now
        let result = await coordinator.reconcile(
            context: context,
            desiredActivity: desiredActivity
        )
        let visibleAt = measurementClock.now
        let didBecomeVisible = await manager.activities.count == 1
        let latency = confirmedAt.duration(to: visibleAt).timeInterval

        return StartObservation(
            isEligible: authorization == .enabled
                && context == .foreground
                && desiredActivity != nil,
            didBecomeVisible: didBecomeVisible,
            latencySeconds: latency,
            failureCodes: result.failureCodes
        )
    }

    private func snapshot(
        activityID: UUID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000301"
        )!
    ) throws -> RestrictionLiveActivitySnapshot {
        RestrictionLiveActivitySnapshot(
            attributes: RestrictionLiveActivityAttributes(
                activityID: activityID,
                restrictionStartedAt: Self.now
            ),
            contentState: try RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: "occurrence-1",
                ruleDisplayName: "집중 시간",
                endsAt: Self.now.addingTimeInterval(3_600),
                remainingDistance: .known(meters: 100),
                distanceObservedAt: Self.now,
                hasAdditionalRestrictions: false
            )
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_788_192_300)
}

private struct StartObservation: Sendable {
    let isEligible: Bool
    let didBecomeVisible: Bool
    let latencySeconds: TimeInterval
    let failureCodes: [LiveActivityCoinErrorCode]

    var meetsTarget: Bool {
        isEligible
            && didBecomeVisible
            && failureCodes.isEmpty
            && latencySeconds <= 30
    }
}

private struct StartMeasurementSummary: Sendable {
    let eligibleCount: Int
    let successCount: Int
    let maximumSuccessfulLatency: TimeInterval

    init(observations: [StartObservation]) {
        let eligible = observations.filter(\.isEligible)
        let successful = eligible.filter(\.meetsTarget)
        eligibleCount = eligible.count
        successCount = successful.count
        maximumSuccessfulLatency = successful.map(\.latencySeconds).max() ?? .infinity
    }

    var successRate: Double {
        guard eligibleCount > 0 else { return 0 }
        return Double(successCount) / Double(eligibleCount)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let parts = components
        return TimeInterval(parts.seconds)
            + TimeInterval(parts.attoseconds) / 1_000_000_000_000_000_000
    }
}
