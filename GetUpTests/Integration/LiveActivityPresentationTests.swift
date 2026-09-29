import Foundation
import Testing
@testable import GetUp

@Suite("Live Activity presentation fixtures")
struct LiveActivityPresentationTests {
    @Test("Every approved state has a fixture for every surface, language, appearance and text size")
    func fixtureMatrix() {
        let scenarios = RestrictionLiveActivityPreviewFixtures.scenarios
        #expect(scenarios.count == 128)
        let keys = Set(scenarios.map {
            "\($0.surface.rawValue)|\($0.variant.rawValue)|\($0.language.rawValue)|\($0.appearance.rawValue)|\($0.textSize.rawValue)"
        })
        #expect(keys.count == 128)
    }

    @Test("State snapshots preserve approved information and remove stale numbers")
    func stateSnapshots() throws {
        let fixtures = RestrictionLiveActivityPreviewFixtures.self
        #expect(fixtures.known.ruleDisplayName == "집중 시간")
        #expect(fixtures.known.remainingDistance == .known(meters: 320))
        #expect(fixtures.known.hasAdditionalRestrictions == false)
        #expect(fixtures.unavailable.remainingDistance == .unavailable)
        #expect(fixtures.unavailable.distanceObservedAt == nil)
        #expect(fixtures.unavailable.endsAt == fixtures.now.addingTimeInterval(2 * 60 * 60))
        #expect(fixtures.stale.remainingDistance == .unavailable)
        #expect(fixtures.stale.distanceObservedAt == nil)
        #expect(fixtures.multipleRestrictions.remainingDistance == .known(meters: 80))
        #expect(fixtures.multipleRestrictions.hasAdditionalRestrictions)
        #expect(fixtures.known.endsAt == fixtures.now.addingTimeInterval(45 * 60))
        #expect(fixtures.attributes.restrictionStartedAt == fixtures.now.addingTimeInterval(-15 * 60))
        for variant in RestrictionLiveActivityPreviewFixtures.Variant.allCases {
            let state = fixtures.contentState(for: variant)
            let encoder = JSONEncoder()
            let attributesBytes = try encoder.encode(fixtures.attributes).count
            let contentBytes = try encoder.encode(state).count
            #expect(attributesBytes + contentBytes < RestrictionLiveActivityAttributes.maximumPayloadSizeInBytes)
        }
    }
}
