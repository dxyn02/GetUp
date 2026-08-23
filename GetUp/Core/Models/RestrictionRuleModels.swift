import FamilyControls
import Foundation

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

struct RestrictionRuleSnapshot: Codable, Equatable, @unchecked Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let revision: Int
    let isEnabled: Bool
    let weekdays: Set<Weekday>
    let startTime: TimeOfDay
    let endTime: TimeOfDay
    let referenceLocation: ReferenceLocation
    let radius: RadiusOption
    let activitySelection: FamilyActivitySelection
    let createdAt: Date
    let updatedAt: Date

    init(
        schemaVersion: Int = RestrictionRuleSnapshot.currentSchemaVersion,
        revision: Int,
        isEnabled: Bool,
        weekdays: Set<Weekday>,
        startTime: TimeOfDay,
        endTime: TimeOfDay,
        referenceLocation: ReferenceLocation,
        radius: RadiusOption,
        activitySelection: FamilyActivitySelection,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.revision = revision
        self.isEnabled = isEnabled
        self.weekdays = weekdays
        self.startTime = startTime
        self.endTime = endTime
        self.referenceLocation = referenceLocation
        self.radius = radius
        self.activitySelection = activitySelection
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case revision
        case isEnabled
        case weekdays
        case startTime
        case endTime
        case referenceLocation
        case radius = "radiusMeters"
        case activitySelection
        case createdAt
        case updatedAt
    }
}
