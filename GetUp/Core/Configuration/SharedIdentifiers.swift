import Foundation

enum SharedIdentifiers {
    static let appGroupIdentifierInfoDictionaryKey = "GetUpAppGroupIdentifier"
    static let coinProductCatalogInfoDictionaryKey = "GetUpCoinProductCatalog"
    static let coinProductIdentifierCatalogKey = "ProductIdentifier"
    static let coinProductQuantityCatalogKey = "Quantity"

    static let restrictionRulesFileName = "restriction-rules.json"
    static let savedPlacesFileName = "saved-places.json"
    static let legacyRestrictionRuleFileName = "restriction-rule.json"
    static let restrictionRuleFileName = restrictionRulesFileName
    static let locationConditionFileName = "location-condition.json"
    static let activeRestrictionSnapshotFileName = "active-restrictions.json"
    static let coinBalanceSnapshotFileName = "coin-balance.json"
    static let releaseExceptionsFileName = "release-exceptions.json"
    static let pendingAppRouteFileName = "pending-app-route.json"

    static let coinLedgerZoneName = "CoinLedgerZone"

    static let managedSettingsStoreName = "getup.restriction"
    static let deviceActivityNamePrefix = "getup.schedule"
    static let locationRegionIdentifierPrefix = "getup.location"
    static let activeRuleRevisionsDefaultsKey = "getup.restriction.active-rule-revisions"
    static let authorizationSnapshotDefaultsKey = "getup.authorization.last-known-snapshot"
    static let intervalStartDiagnosticDefaultsKey = "getup.diagnostics.interval-start.latest"
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

enum CoinLedgerRecordType {
    static let ledgerEpoch = "LedgerEpoch"
    static let coinAccount = "CoinAccount"
    static let monthlyAllowance = "MonthlyAllowance"
    static let purchaseGrant = "PurchaseGrant"
    static let event = "CoinLedgerEvent"
    static let releaseCommand = "ReleaseCommand"
}

enum CoinLedgerRecordID {
    static let ledgerEpoch = "ledger-epoch"
    static let coinAccount = "coin-account"

    static func allowance(monthID: String) -> String {
        "allowance:\(monthID)"
    }

    static func purchaseGrant(
        environment: PurchaseEnvironment,
        transactionID: UInt64
    ) -> String {
        "purchase-grant:\(environment.rawValue):\(transactionID)"
    }

    static func event(eventID: String) -> String {
        eventID
    }

    static func releaseCommand(commandID: UUID) -> String {
        "release-command:\(normalized(commandID))"
    }

    private static func normalized(_ identifier: UUID) -> String {
        identifier.uuidString.lowercased()
    }
}

enum CoinLedgerDeterministicID {
    static func purchase(
        environment: PurchaseEnvironment,
        transactionID: UInt64
    ) -> String {
        "purchase:\(environment.rawValue):\(transactionID)"
    }

    static func freeGrant(monthID: String) -> String {
        "free:\(monthID)"
    }

    static func reservation(commandID: UUID) -> String {
        "reserve:\(normalized(commandID))"
    }

    static func spend(commandID: UUID) -> String {
        "spend:\(normalized(commandID))"
    }

    static func release(commandID: UUID, attempt: Int) -> String {
        "release:\(normalized(commandID)):\(attempt)"
    }

    static func refund(transactionID: UInt64, revocationDate: Date) -> String {
        "refund:\(transactionID):\(String(revocationDate.timeIntervalSince1970.bitPattern, radix: 16))"
    }

    private static func normalized(_ identifier: UUID) -> String {
        identifier.uuidString.lowercased()
    }
}
