import Foundation

enum SharedIdentifiers {
    static let appGroupIdentifierInfoDictionaryKey = "GetUpAppGroupIdentifier"

    static let restrictionRulesFileName = "restriction-rules.json"
    static let savedPlacesFileName = "saved-places.json"
    static let legacyRestrictionRuleFileName = "restriction-rule.json"
    static let restrictionRuleFileName = restrictionRulesFileName
    static let locationConditionFileName = "location-condition.json"

    static let managedSettingsStoreName = "getup.restriction"
    static let deviceActivityNamePrefix = "getup.schedule"
    static let locationRegionIdentifierPrefix = "getup.location"
    static let activeRuleRevisionsDefaultsKey = "getup.restriction.active-rule-revisions"
    static let authorizationSnapshotDefaultsKey = "getup.authorization.last-known-snapshot"
    static let legacyRestrictionIsAppliedDefaultsKey = "getup.restriction.is-applied"
    static let legacyRestrictionRuleRevisionDefaultsKey = "getup.restriction.rule-revision"

    static func ruleID(fromDeviceActivityName activityName: String) -> UUID? {
        let prefix = "\(deviceActivityNamePrefix)."
        guard activityName.hasPrefix(prefix) else {
            return nil
        }

        let remainder = activityName.dropFirst(prefix.count)
        guard let identifier = remainder.split(separator: ".").first else {
            return nil
        }
        return UUID(uuidString: String(identifier))
    }

    static func locationRegionIdentifier(for ruleID: UUID) -> String {
        "\(locationRegionIdentifierPrefix).\(ruleID.uuidString.lowercased())"
    }

    static func ruleID(fromLocationRegionIdentifier identifier: String) -> UUID? {
        let prefix = "\(locationRegionIdentifierPrefix)."
        guard identifier.hasPrefix(prefix) else {
            return nil
        }

        return UUID(uuidString: String(identifier.dropFirst(prefix.count)))
    }

    static func appGroupIdentifier(in bundle: Bundle = .main) -> String? {
        guard
            let identifier = bundle.object(
                forInfoDictionaryKey: appGroupIdentifierInfoDictionaryKey
            ) as? String,
            !identifier.isEmpty,
            !identifier.contains("$(")
        else {
            return nil
        }

        return identifier
    }

    static func deviceActivityName(forWeekdayIdentifier weekdayIdentifier: String) -> String {
        "\(deviceActivityNamePrefix).\(weekdayIdentifier)"
    }
}
