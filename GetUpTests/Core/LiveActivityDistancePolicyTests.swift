import Foundation
import Testing
@testable import GetUp

@Suite("Live Activity distance policy")
struct LiveActivityDistancePolicyTests {
    @Test("A fresh inside location shows the rounded remaining meters")
    func freshInsideLocationIsKnown() throws {
        let condition = locationCondition(
            distanceMeters: 742,
            horizontalAccuracyMeters: 10
        )

        let content = try makeContent(condition: condition)

        #expect(content.remainingDistance == .known(meters: 260))
        #expect(content.distanceObservedAt == Self.observedAt)
    }

    @Test(arguments: [
        (centerDistance: 996.0, expectedMeters: 0),
        (centerDistance: 995.0, expectedMeters: 10),
        (centerDistance: 985.0, expectedMeters: 20),
    ])
    func roundsToTenMetersHalfUp(
        centerDistance: Double,
        expectedMeters: Int
    ) throws {
        let content = try makeContent(
            condition: locationCondition(
                distanceMeters: centerDistance,
                horizontalAccuracyMeters: 0
            )
        )

        #expect(content.remainingDistance == .known(meters: expectedMeters))
    }

    @Test("The radius boundary clamps the remaining distance to zero")
    func radiusBoundaryClampsToZero() throws {
        let content = try makeContent(
            condition: locationCondition(
                distanceMeters: Self.radiusMeters,
                horizontalAccuracyMeters: 0
            )
        )

        #expect(content.remainingDistance == .known(meters: 0))
    }

    @Test("A location observed exactly five minutes ago remains current")
    func exactFiveMinuteBoundaryIsCurrent() throws {
        let condition = locationCondition(
            observedAt: Self.now.addingTimeInterval(-300),
            distanceMeters: 800,
            horizontalAccuracyMeters: 10
        )

        let content = try makeContent(condition: condition)

        #expect(content.remainingDistance == .known(meters: 200))
        #expect(content.distanceObservedAt == condition.observedAt)
    }

    @Test("A location older than five minutes is unavailable")
    func olderThanFiveMinutesIsUnavailable() throws {
        let condition = locationCondition(
            observedAt: Self.now.addingTimeInterval(-300.001),
            distanceMeters: 800,
            horizontalAccuracyMeters: 10
        )

        let content = try makeContent(condition: condition)

        #expect(content.remainingDistance == .unavailable)
        #expect(content.distanceObservedAt == nil)
    }

    @Test(arguments: [
        LocationConditionState.outside,
        LocationConditionState.unavailable,
    ])
    func nonInsideLocationIsUnavailable(
        state: LocationConditionState
    ) throws {
        let condition = LocationConditionSnapshot(
            ruleID: Self.ruleID,
            ruleRevision: Self.ruleRevision,
            state: state,
            observedAt: Self.observedAt,
            distanceMeters: 800,
            horizontalAccuracyMeters: 10,
            source: .freshFix
        )

        let content = try makeContent(condition: condition)

        #expect(content.remainingDistance == .unavailable)
        #expect(content.distanceObservedAt == nil)
    }

    @Test("Missing or mismatched location evidence is unavailable")
    func missingOrMismatchedLocationIsUnavailable() throws {
        let mismatch = LocationConditionSnapshot(
            ruleID: Self.ruleID,
            ruleRevision: Self.ruleRevision + 1,
            state: .inside,
            observedAt: Self.observedAt,
            distanceMeters: 800,
            horizontalAccuracyMeters: 10,
            source: .freshFix
        )

        let missingContent = try makeContent(condition: nil)
        let mismatchContent = try makeContent(condition: mismatch)

        #expect(missingContent.remainingDistance == .unavailable)
        #expect(mismatchContent.remainingDistance == .unavailable)
        #expect(missingContent.distanceObservedAt == nil)
        #expect(mismatchContent.distanceObservedAt == nil)
    }

    @Test("Future and malformed inside evidence is unavailable")
    func invalidInsideEvidenceIsUnavailable() throws {
        let future = locationCondition(
            observedAt: Self.now.addingTimeInterval(0.001),
            distanceMeters: 800,
            horizontalAccuracyMeters: 10
        )
        let missingDistance = LocationConditionSnapshot(
            ruleID: Self.ruleID,
            ruleRevision: Self.ruleRevision,
            state: .inside,
            observedAt: Self.observedAt,
            distanceMeters: nil,
            horizontalAccuracyMeters: 10,
            source: .freshFix
        )

        #expect(try makeContent(condition: future).remainingDistance == .unavailable)
        #expect(
            try makeContent(condition: missingDistance).remainingDistance
                == .unavailable
        )
    }

    private func makeContent(
        condition: LocationConditionSnapshot?
    ) throws -> RestrictionLiveActivityAttributes.ContentState {
        try LiveActivityContentPolicy.makeContentState(
            occurrence: Self.occurrence,
            ruleDisplayName: "집중 시간",
            radiusMeters: Self.radiusMeters,
            locationCondition: condition,
            hasAdditionalRestrictions: true,
            now: Self.now
        )
    }

    private func locationCondition(
        observedAt: Date = Self.observedAt,
        distanceMeters: Double,
        horizontalAccuracyMeters: Double
    ) -> LocationConditionSnapshot {
        LocationConditionSnapshot(
            ruleID: Self.ruleID,
            ruleRevision: Self.ruleRevision,
            state: LocationEvidenceEvaluator.evaluate(
                distanceMeters: distanceMeters,
                horizontalAccuracyMeters: horizontalAccuracyMeters,
                radiusMeters: Self.radiusMeters
            ),
            observedAt: observedAt,
            distanceMeters: distanceMeters,
            horizontalAccuracyMeters: horizontalAccuracyMeters,
            source: .freshFix
        )
    }

    private static let ruleID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000101"
    )!
    private static let ruleRevision = 3
    private static let radiusMeters = 1_000.0
    private static let now = Date(timeIntervalSince1970: 1_788_192_300)
    private static let observedAt = now.addingTimeInterval(-60)
    private static let occurrence = try! RestrictionOccurrence(
        ruleID: ruleID,
        ruleRevision: ruleRevision,
        startAt: now.addingTimeInterval(-600),
        endAt: now.addingTimeInterval(3_600),
        activatedAt: now.addingTimeInterval(-590)
    )
}
