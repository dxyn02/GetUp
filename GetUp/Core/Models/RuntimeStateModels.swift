import Foundation

enum LocationConditionState: String, Codable, Sendable {
    case inside
    case outside
    case unavailable
}

enum LocationConditionSource: String, Codable, Sendable {
    case freshFix
    case regionEvent
    case restoration
}

struct LocationConditionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let ruleRevision: Int
    let state: LocationConditionState
    let observedAt: Date
    let distanceMeters: Double?
    let horizontalAccuracyMeters: Double?
    let source: LocationConditionSource

    init(
        schemaVersion: Int = LocationConditionSnapshot.currentSchemaVersion,
        ruleRevision: Int,
        state: LocationConditionState,
        observedAt: Date,
        distanceMeters: Double?,
        horizontalAccuracyMeters: Double?,
        source: LocationConditionSource
    ) {
        self.schemaVersion = schemaVersion
        self.ruleRevision = ruleRevision
        self.state = state
        self.observedAt = observedAt
        self.distanceMeters = distanceMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.source = source
    }
}

enum FamilyControlsAuthorizationStatus: String, Codable, Sendable {
    case approved
    case denied
    case notDetermined
}

enum LocationAuthorizationStatus: String, Codable, Sendable {
    case always
    case whenInUse
    case denied
    case restricted
    case notDetermined
}

enum LocationAccuracyStatus: String, Codable, Sendable {
    case full
    case reduced
}

enum BackgroundRefreshStatus: String, Codable, Sendable {
    case available
    case denied
    case restricted
}

struct AuthorizationSnapshot: Codable, Equatable, Sendable {
    let familyControls: FamilyControlsAuthorizationStatus
    let locationAuthorization: LocationAuthorizationStatus
    let locationAccuracy: LocationAccuracyStatus
    let backgroundRefresh: BackgroundRefreshStatus
}

enum RequiredPermission: String, Codable, Hashable, Sendable {
    case familyControls
    case alwaysLocation
    case fullAccuracy
    case backgroundRefresh
}

enum RestrictionPresentationState: Codable, Equatable, Sendable {
    case configurationRequired
    case inactive
    case active
    case permissionRequired(missingPermissions: Set<RequiredPermission>)
    case locationUnavailable(isRestrictionApplied: Bool)
}
