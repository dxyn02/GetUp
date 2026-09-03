import Foundation
import Testing
@testable import GetUp

@Suite("Live Activity time policy")
struct LiveActivityTimePolicyTests {
    @Test("A future end date preserves the remaining interval")
    func futureEndDate() {
        let endAt = Self.now.addingTimeInterval(125)
        let result = LiveActivityTimePolicy.evaluate(endsAt: endAt, now: Self.now)

        #expect(result.endsAt == endAt)
        #expect(result.remainingSeconds == 125)
        #expect(abs(result.remainingSeconds - 125) <= 60)
    }

    @Test("The exact end boundary clamps to zero")
    func exactEndBoundary() {
        let result = LiveActivityTimePolicy.evaluate(endsAt: Self.now, now: Self.now)

        #expect(result.endsAt == Self.now)
        #expect(result.remainingSeconds == 0)
    }

    @Test("A past end date uses now and never produces a negative countdown")
    func pastEndDate() {
        let result = LiveActivityTimePolicy.evaluate(
            endsAt: Self.now.addingTimeInterval(-30),
            now: Self.now
        )

        #expect(result.endsAt == Self.now)
        #expect(result.remainingSeconds == 0)
    }

    @Test("Clamping content preserves every non-time field")
    func clampsContentState() throws {
        let content = try contentState(endsAt: Self.now.addingTimeInterval(-1))
        let clamped = try LiveActivityTimePolicy.clamping(
            contentState: content,
            now: Self.now
        )

        #expect(clamped.endsAt == Self.now)
        #expect(clamped.occurrenceID == content.occurrenceID)
        #expect(clamped.ruleDisplayName == content.ruleDisplayName)
        #expect(clamped.remainingDistance == content.remainingDistance)
        #expect(clamped.distanceObservedAt == content.distanceObservedAt)
        #expect(clamped.hasAdditionalRestrictions == content.hasAdditionalRestrictions)
    }

    @Test("An ending state sets the end date to now")
    func endingState() throws {
        let content = try contentState(endsAt: Self.now.addingTimeInterval(300))
        let ending = try LiveActivityTimePolicy.ending(
            contentState: content,
            now: Self.now
        )

        #expect(ending.endsAt == Self.now)
        #expect(ending.occurrenceID == content.occurrenceID)
        #expect(ending.remainingDistance == content.remainingDistance)
    }

    private func contentState(
        endsAt: Date
    ) throws -> RestrictionLiveActivityAttributes.ContentState {
        try RestrictionLiveActivityAttributes.ContentState(
            occurrenceID: "occurrence-1",
            ruleDisplayName: "집중 시간",
            endsAt: endsAt,
            remainingDistance: .known(meters: 100),
            distanceObservedAt: Self.now.addingTimeInterval(-10),
            hasAdditionalRestrictions: true
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_788_192_300)
}
