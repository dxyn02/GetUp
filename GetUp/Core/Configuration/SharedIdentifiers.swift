import Foundation

enum SharedIdentifiers {
    static let appGroupIdentifierInfoDictionaryKey = "GetUpAppGroupIdentifier"

    static let restrictionRuleFileName = "restriction-rule.json"
    static let locationConditionFileName = "location-condition.json"

    static let managedSettingsStoreName = "getup.restriction"
    static let deviceActivityNamePrefix = "getup.schedule"

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
