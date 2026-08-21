import Foundation

struct EvaluationInput: Equatable, Sendable {
    let rule: RestrictionRuleSnapshot?
    let now: Date
    let calendar: Calendar
    let timeZone: TimeZone
    let locationCondition: LocationConditionSnapshot
    let authorization: AuthorizationSnapshot
    let appliedRestriction: AppliedRestrictionState
}

enum DesiredRestrictionState: String, Codable, Sendable {
    case active
    case inactive
    case preserve
}

enum RestrictionEffect: String, Codable, Sendable {
    case applyShield
    case removeShield
    case none
}

enum EvaluationReason: Equatable, Sendable {
    case configurationMissing
    case ruleDisabled
    case scheduleInactive
    case missingPermissions(Set<RequiredPermission>)
    case locationRevisionMismatch
    case locationOutside
    case locationUnavailable
    case conditionsSatisfied
}

struct EvaluationDecision: Equatable, Sendable {
    let presentationState: RestrictionPresentationState
    let desiredRestriction: DesiredRestrictionState
    let effect: RestrictionEffect
    let reason: EvaluationReason
}
