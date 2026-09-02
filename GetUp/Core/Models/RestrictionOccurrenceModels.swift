import Foundation

enum LiveActivityCoinModelError: Error, Equatable, Sendable {
    case invalidOccurrenceInterval
    case invalidOccurrenceID
    case duplicateOccurrenceID(String)
    case unsupportedActiveRestrictionSnapshotSchema(Int)
    case invalidActiveRestrictionSnapshotRevision
    case invalidRemainingDistance
    case missingDistanceObservation
    case unexpectedDistanceObservation
    case invalidPurchasedBalance
    case invalidMonthlyAllowanceBalance
    case invalidPurchaseAdjustment
    case invalidCoinLedgerEvent
    case invalidCoinBalanceSnapshot
    case invalidReleaseCommandTransition
    case invalidReleaseExceptionInterval
    case invalidReleaseExceptionCollection
    case unsupportedReleaseExceptionCollectionSchema(Int)
    case invalidPendingAppRoute
}

struct RestrictionOccurrence: Codable, Equatable, Hashable, Sendable {
    let id: String
    let ruleID: UUID
    let ruleRevision: Int
    let startAt: Date
    let endAt: Date
    let activatedAt: Date

    init(
        ruleID: UUID,
        ruleRevision: Int,
        startAt: Date,
        endAt: Date,
        activatedAt: Date
    ) throws {
        guard startAt < endAt else {
            throw LiveActivityCoinModelError.invalidOccurrenceInterval
        }

        self.id = Self.deterministicID(
            ruleID: ruleID,
            ruleRevision: ruleRevision,
            startAt: startAt,
            endAt: endAt
        )
        self.ruleID = ruleID
        self.ruleRevision = ruleRevision
        self.startAt = startAt
        self.endAt = endAt
        self.activatedAt = activatedAt
    }

    static func deterministicID(
        ruleID: UUID,
        ruleRevision: Int,
        startAt: Date,
        endAt: Date
    ) -> String {
        [
            "occurrence",
            ruleID.uuidString.lowercased(),
            String(ruleRevision),
            canonicalDateComponent(startAt),
            canonicalDateComponent(endAt),
        ].joined(separator: ":")
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let persistedID = try container.decode(String.self, forKey: .id)
        let ruleID = try container.decode(UUID.self, forKey: .ruleID)
        let ruleRevision = try container.decode(Int.self, forKey: .ruleRevision)
        let startAt = try container.decode(Date.self, forKey: .startAt)
        let endAt = try container.decode(Date.self, forKey: .endAt)
        let activatedAt = try container.decode(Date.self, forKey: .activatedAt)

        try self.init(
            ruleID: ruleID,
            ruleRevision: ruleRevision,
            startAt: startAt,
            endAt: endAt,
            activatedAt: activatedAt
        )

        guard id == persistedID else {
            throw LiveActivityCoinModelError.invalidOccurrenceID
        }
    }

    private static func canonicalDateComponent(_ date: Date) -> String {
        let value = String(
            date.timeIntervalSinceReferenceDate.bitPattern,
            radix: 16,
            uppercase: false
        )
        return String(repeating: "0", count: max(0, 16 - value.count)) + value
    }
}

struct ActiveRestrictionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let revision: Int
    let occurrences: [RestrictionOccurrence]
    let observedAt: Date

    init(
        schemaVersion: Int = ActiveRestrictionSnapshot.currentSchemaVersion,
        revision: Int,
        occurrences: [RestrictionOccurrence],
        observedAt: Date
    ) throws {
        guard schemaVersion == Self.currentSchemaVersion else {
            throw LiveActivityCoinModelError.unsupportedActiveRestrictionSnapshotSchema(
                schemaVersion
            )
        }
        guard revision >= 0 else {
            throw LiveActivityCoinModelError.invalidActiveRestrictionSnapshotRevision
        }

        var occurrenceIDs = Set<String>()
        for occurrence in occurrences where !occurrenceIDs.insert(occurrence.id).inserted {
            throw LiveActivityCoinModelError.duplicateOccurrenceID(occurrence.id)
        }

        self.schemaVersion = schemaVersion
        self.revision = revision
        self.occurrences = occurrences
        self.observedAt = observedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            revision: container.decode(Int.self, forKey: .revision),
            occurrences: container.decode(
                [RestrictionOccurrence].self,
                forKey: .occurrences
            ),
            observedAt: container.decode(Date.self, forKey: .observedAt)
        )
    }
}
