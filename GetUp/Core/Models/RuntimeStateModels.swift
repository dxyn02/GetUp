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
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let ruleID: UUID
    let ruleRevision: Int
    let state: LocationConditionState
    let observedAt: Date
    let distanceMeters: Double?
    let horizontalAccuracyMeters: Double?
    let source: LocationConditionSource

    init(
        schemaVersion: Int = LocationConditionSnapshot.currentSchemaVersion,
        ruleID: UUID,
        ruleRevision: Int,
        state: LocationConditionState,
        observedAt: Date,
        distanceMeters: Double?,
        horizontalAccuracyMeters: Double?,
        source: LocationConditionSource
    ) {
        self.schemaVersion = schemaVersion
        self.ruleID = ruleID
        self.ruleRevision = ruleRevision
        self.state = state
        self.observedAt = observedAt
        self.distanceMeters = distanceMeters
        self.horizontalAccuracyMeters = horizontalAccuracyMeters
        self.source = source
    }
}

struct LocationConditionCollectionSnapshot: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 2

    let schemaVersion: Int
    let conditions: [LocationConditionSnapshot]

    init(
        schemaVersion: Int = LocationConditionCollectionSnapshot.currentSchemaVersion,
        conditions: [LocationConditionSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.conditions = conditions
    }

    func condition(for rule: RestrictionRuleSnapshot) -> LocationConditionSnapshot? {
        conditions.first {
            $0.ruleID == rule.id && $0.ruleRevision == rule.revision
        }
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

struct AuthorizationSnapshotRecord: Codable, Equatable, Sendable {
    let snapshot: AuthorizationSnapshot
    let observedAt: Date
}

enum IntervalStartDiagnosticStage: String, Codable, Sendable {
    case callbackReceived
    case invalidActivityName
    case snapshotReadFailed
    case startedRuleMissing
    case storeVerificationFailed
    case completed
}

struct IntervalStartDiagnosticRecord: Codable, Equatable, Sendable {
    let stage: IntervalStartDiagnosticStage
    let observedAt: Date
    let activityName: String
    let ruleCount: Int?
    let locationConditionCount: Int?
    let desiredRuleCount: Int?
    let currentAppliedRuleCount: Int?
    let startedRuleDecision: String?
    let startedLocationState: LocationConditionState?
    let startedLocationAgeSeconds: TimeInterval?
    let authorization: AuthorizationSnapshot?
    let errorCode: String?
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
