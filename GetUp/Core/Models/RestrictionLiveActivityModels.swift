import Foundation

#if os(iOS) && !targetEnvironment(macCatalyst)
import ActivityKit
#endif

enum RestrictionLiveActivityDistance: Codable, Equatable, Hashable, Sendable {
    case known(meters: Int)
    case unavailable
}

struct RestrictionLiveActivityAttributes: Codable, Equatable, Hashable, Sendable {
    static let maximumPayloadSizeInBytes = 4 * 1_024

    let activityID: UUID
    let restrictionStartedAt: Date

    struct ContentState: Codable, Equatable, Hashable, Sendable {
        let occurrenceID: String
        let ruleDisplayName: String
        let endsAt: Date
        let remainingDistance: RestrictionLiveActivityDistance
        let distanceObservedAt: Date?
        let hasAdditionalRestrictions: Bool

        init(
            occurrenceID: String,
            ruleDisplayName: String,
            endsAt: Date,
            remainingDistance: RestrictionLiveActivityDistance,
            distanceObservedAt: Date?,
            hasAdditionalRestrictions: Bool
        ) throws {
            switch remainingDistance {
            case .known(let meters):
                guard meters >= 0 else {
                    throw LiveActivityCoinModelError.invalidRemainingDistance
                }
                guard distanceObservedAt != nil else {
                    throw LiveActivityCoinModelError.missingDistanceObservation
                }
            case .unavailable:
                guard distanceObservedAt == nil else {
                    throw LiveActivityCoinModelError.unexpectedDistanceObservation
                }
            }

            self.occurrenceID = occurrenceID
            self.ruleDisplayName = ruleDisplayName
            self.endsAt = endsAt
            self.remainingDistance = remainingDistance
            self.distanceObservedAt = distanceObservedAt
            self.hasAdditionalRestrictions = hasAdditionalRestrictions
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(
                occurrenceID: container.decode(String.self, forKey: .occurrenceID),
                ruleDisplayName: container.decode(String.self, forKey: .ruleDisplayName),
                endsAt: container.decode(Date.self, forKey: .endsAt),
                remainingDistance: container.decode(
                    RestrictionLiveActivityDistance.self,
                    forKey: .remainingDistance
                ),
                distanceObservedAt: container.decodeIfPresent(
                    Date.self,
                    forKey: .distanceObservedAt
                ),
                hasAdditionalRestrictions: container.decode(
                    Bool.self,
                    forKey: .hasAdditionalRestrictions
                )
            )
        }
    }
}

#if os(iOS) && !targetEnvironment(macCatalyst)
extension RestrictionLiveActivityAttributes: ActivityAttributes {}
#endif
