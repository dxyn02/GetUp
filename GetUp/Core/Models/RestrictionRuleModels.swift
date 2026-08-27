import FamilyControls
import Foundation

extension FamilyActivitySelection {
    var restrictionTargetCount: Int {
        applicationTokens.count + categoryTokens.count + webDomainTokens.count
    }

    var hasRestrictionTargets: Bool {
        restrictionTargetCount > 0
    }

    func restrictionSelectionSummary(
        countedTargets: Int? = nil
    ) -> RestrictionSelectionSummary {
        if !categoryTokens.isEmpty {
            return .multiple
        }

        let count = countedTargets ?? restrictionTargetCount
        return count == 0 ? .none : .exact(count)
    }
}

enum RestrictionSelectionSummary: Equatable, Sendable {
    case none
    case exact(Int)
    case multiple
}

enum Weekday: String, Codable, CaseIterable, Hashable, Sendable {
    case monday
    case tuesday
    case wednesday
    case thursday
    case friday
    case saturday
    case sunday
}

struct TimeOfDay: Codable, Equatable, Hashable, Sendable {
    let hour: Int
    let minute: Int
}

enum RadiusOption: Int, Codable, CaseIterable, Sendable {
    case meters100 = 100
    case meters250 = 250
    case meters500 = 500
    case meters1000 = 1_000

    var meters: Double {
        Double(rawValue)
    }
}

struct ReferenceLocation: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double
}

struct SavedPlaceSnapshot: Codable, Equatable, Sendable {
    let id: UUID
    let name: String
    let coordinate: ReferenceLocation
    let createdAt: Date
    let updatedAt: Date

    init(
        id: UUID,
        name: String,
        coordinate: ReferenceLocation,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.name = name
        self.coordinate = coordinate
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        coordinate = ReferenceLocation(
            latitude: try container.decode(Double.self, forKey: .latitude),
            longitude: try container.decode(Double.self, forKey: .longitude)
        )
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case latitude
        case longitude
        case createdAt
        case updatedAt
    }
}

enum SavedPlaceNamePolicy {
    static let maximumLength = 10

    static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func uniquenessKey(_ name: String) -> String {
        normalized(name).lowercased()
    }

    static func isValid(_ name: String) -> Bool {
        let value = normalized(name)
        return !value.isEmpty && value.count <= maximumLength
    }

    static func hasUniqueValidNames(_ places: [SavedPlaceSnapshot]) -> Bool {
        let keys = places.map { uniquenessKey($0.name) }
        return places.allSatisfy { isValid($0.name) } && Set(keys).count == keys.count
    }
}

struct RestrictionRuleSnapshot: Codable, Equatable, @unchecked Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let id: UUID
    let revision: Int
    let name: String?
    let isEnabled: Bool
    let weekdays: Set<Weekday>
    let startTime: TimeOfDay
    let endTime: TimeOfDay
    let savedPlaceID: UUID
    let radius: RadiusOption
    let activitySelection: FamilyActivitySelection
    let createdAt: Date
    let updatedAt: Date

    init(
        schemaVersion: Int = RestrictionRuleSnapshot.currentSchemaVersion,
        id: UUID,
        revision: Int,
        name: String?,
        isEnabled: Bool,
        weekdays: Set<Weekday>,
        startTime: TimeOfDay,
        endTime: TimeOfDay,
        savedPlaceID: UUID,
        radius: RadiusOption,
        activitySelection: FamilyActivitySelection,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.name = name
        self.isEnabled = isEnabled
        self.weekdays = weekdays
        self.startTime = startTime
        self.endTime = endTime
        self.savedPlaceID = savedPlaceID
        self.radius = radius
        self.activitySelection = activitySelection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case id
        case revision
        case name
        case isEnabled
        case weekdays
        case startTime
        case endTime
        case savedPlaceID
        case radius = "radiusMeters"
        case activitySelection
        case createdAt
        case updatedAt
    }
}

struct RestrictionRuleCollectionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let revision: Int
    let rules: [RestrictionRuleSnapshot]

    init(
        schemaVersion: Int = RestrictionRuleCollectionSnapshot.currentSchemaVersion,
        revision: Int,
        rules: [RestrictionRuleSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.rules = rules
    }
}

struct SavedPlaceCollectionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let revision: Int
    let places: [SavedPlaceSnapshot]

    init(
        schemaVersion: Int = SavedPlaceCollectionSnapshot.currentSchemaVersion,
        revision: Int,
        places: [SavedPlaceSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.places = places
    }
}
