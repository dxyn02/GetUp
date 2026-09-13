@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings

struct ShieldContentSnapshot: Equatable, @unchecked Sendable {
    let rules: RestrictionRuleCollectionSnapshot
    let savedPlaces: SavedPlaceCollectionSnapshot
    let activeRestrictions: ActiveRestrictionSnapshot
    let coinBalance: CoinBalanceSnapshot
}

protocol ShieldSnapshotReading {
    func readSnapshot() throws -> ShieldContentSnapshot
}

enum ShieldSnapshotReaderError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case appGroupContainerUnavailable
    case snapshotMissing(fileName: String)
    case snapshotReadFailed(fileName: String)
    case snapshotDecodingFailed(fileName: String)
    case unsupportedSchema(fileName: String, found: Int, supported: Int)
}

struct AppGroupShieldSnapshotReader: ShieldSnapshotReading {
    private let bundle: Bundle
    private let fileManager: FileManager

    init(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) {
        self.bundle = bundle
        self.fileManager = fileManager
    }

    func readSnapshot() throws -> ShieldContentSnapshot {
        guard let identifier = SharedIdentifiers.appGroupIdentifier(in: bundle) else {
            throw ShieldSnapshotReaderError.missingAppGroupIdentifier
        }
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            )
        else {
            throw ShieldSnapshotReaderError.appGroupContainerUnavailable
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rules: RestrictionRuleCollectionSnapshot = try decode(
            RestrictionRuleCollectionSnapshot.self,
            from: containerURL.appendingPathComponent(
                SharedIdentifiers.restrictionRulesFileName
            ),
            using: decoder
        )
        let places: SavedPlaceCollectionSnapshot = try decode(
            SavedPlaceCollectionSnapshot.self,
            from: containerURL.appendingPathComponent(
                SharedIdentifiers.savedPlacesFileName
            ),
            using: decoder
        )
        let activeRestrictions: ActiveRestrictionSnapshot = try decode(
            ActiveRestrictionSnapshot.self,
            from: containerURL.appendingPathComponent(
                SharedIdentifiers.activeRestrictionSnapshotFileName
            ),
            using: decoder
        )
        let coinBalance: CoinBalanceSnapshot = try decode(
            CoinBalanceSnapshot.self,
            from: containerURL.appendingPathComponent(
                SharedIdentifiers.coinBalanceSnapshotFileName
            ),
            using: decoder
        )
        try validateSchema(
            rules.schemaVersion,
            supported: RestrictionRuleCollectionSnapshot.currentSchemaVersion,
            fileName: SharedIdentifiers.restrictionRulesFileName
        )
        try validateSchema(
            places.schemaVersion,
            supported: SavedPlaceCollectionSnapshot.currentSchemaVersion,
            fileName: SharedIdentifiers.savedPlacesFileName
        )
        try validateSchema(
            activeRestrictions.schemaVersion,
            supported: ActiveRestrictionSnapshot.currentSchemaVersion,
            fileName: SharedIdentifiers.activeRestrictionSnapshotFileName
        )
        try validateSchema(
            coinBalance.schemaVersion,
            supported: CoinBalanceSnapshot.currentSchemaVersion,
            fileName: SharedIdentifiers.coinBalanceSnapshotFileName
        )

        return ShieldContentSnapshot(
            rules: rules,
            savedPlaces: places,
            activeRestrictions: activeRestrictions,
            coinBalance: coinBalance
        )
    }

    private func decode<Value: Decodable>(
        _ type: Value.Type,
        from fileURL: URL,
        using decoder: JSONDecoder
    ) throws -> Value {
        let fileName = fileURL.lastPathComponent
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw ShieldSnapshotReaderError.snapshotMissing(fileName: fileName)
        }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw ShieldSnapshotReaderError.snapshotReadFailed(fileName: fileName)
        }
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ShieldSnapshotReaderError.snapshotDecodingFailed(fileName: fileName)
        }
    }

    private func validateSchema(
        _ found: Int,
        supported: Int,
        fileName: String
    ) throws {
        guard found == supported else {
            throw ShieldSnapshotReaderError.unsupportedSchema(
                fileName: fileName,
                found: found,
                supported: supported
            )
        }
    }
}

enum ShieldReleaseFundingPolicy: Equatable, Sendable {
    /// The balance snapshot is presentation-only. The action extension asks the
    /// latest ledger to reserve the monthly allowance first, then this quantity.
    case latestLedgerFreeFirst(purchasedFallbackQuantity: Int)
}

struct ShieldContent: Equatable, Sendable {
    let title: String
    let subtitle: String
    let primaryButtonLabel: String
    let secondaryButtonLabel: String?
    let releaseFundingPolicy: ShieldReleaseFundingPolicy?
}

enum ShieldContentDiagnosticOutcome: String, Codable, Equatable, Sendable {
    case releaseContent
    case fallback
}

enum ShieldContentFallbackReason: String, Codable, Equatable, Sendable {
    case none
    case missingShieldToken
    case missingAppGroupIdentifier
    case appGroupContainerUnavailable
    case snapshotMissing
    case snapshotReadFailed
    case snapshotDecodingFailed
    case unsupportedSchema
    case unknownSnapshotError
    case invalidCollectionIdentity
    case unsupportedCoinBalanceSchema
    case noMatchingOccurrence
    case missingSavedPlace
}

/// DEBUG builds persist only this sanitized decision summary. Family Controls
/// tokens, rule/place identifiers, names, coordinates, and CloudKit details are
/// deliberately excluded.
struct ShieldContentDiagnostic: Codable, Equatable, Sendable {
    let recordedAt: Date
    let outcome: ShieldContentDiagnosticOutcome
    let fallbackReason: ShieldContentFallbackReason
    let failingFileName: String?
    let foundSchemaVersion: Int?
    let supportedSchemaVersion: Int?
    let rulesSchemaVersion: Int?
    let savedPlacesSchemaVersion: Int?
    let activeRestrictionsSchemaVersion: Int?
    let coinBalanceSchemaVersion: Int?
    let ruleCount: Int?
    let savedPlaceCount: Int?
    let activeOccurrenceCount: Int?
    let matchingOccurrenceCount: Int?
    let hasApplicationToken: Bool
    let hasCategoryToken: Bool
    let hasWebDomainToken: Bool
}

struct ShieldContentResult: Equatable, Sendable {
    let content: ShieldContent
    let diagnostic: ShieldContentDiagnostic
}

struct ShieldContentProvider {
    private let snapshotReader: any ShieldSnapshotReading
    private let tokenRefresher: any ShieldTokenRefreshing
    private let bundle: Bundle
    private let now: () -> Date
    private let calendar: Calendar

    init(
        snapshotReader: any ShieldSnapshotReading,
        tokenRefresher: any ShieldTokenRefreshing = SystemShieldTokenRefresher(),
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.snapshotReader = snapshotReader
        self.tokenRefresher = tokenRefresher
        self.bundle = bundle
        self.now = now
        self.calendar = calendar
    }

    func content(
        for applicationToken: ApplicationToken?,
        categoryToken: ActivityCategoryToken? = nil,
        webDomainToken: WebDomainToken? = nil
    ) -> ShieldContent {
        contentResult(
            for: applicationToken,
            categoryToken: categoryToken,
            webDomainToken: webDomainToken
        ).content
    }

    func contentResult(
        for applicationToken: ApplicationToken?,
        categoryToken: ActivityCategoryToken? = nil,
        webDomainToken: WebDomainToken? = nil
    ) -> ShieldContentResult {
        let evaluatedAt = now()
        let tokenState = TokenState(
            hasApplicationToken: applicationToken != nil,
            hasCategoryToken: categoryToken != nil,
            hasWebDomainToken: webDomainToken != nil
        )
        guard tokenState.hasAnyToken else {
            return fallbackResult(
                reason: .missingShieldToken,
                recordedAt: evaluatedAt,
                tokenState: tokenState
            )
        }

        let snapshot: ShieldContentSnapshot
        do {
            snapshot = try snapshotReader.readSnapshot()
        } catch {
            return fallbackResult(
                snapshotError: error,
                recordedAt: evaluatedAt,
                tokenState: tokenState
            )
        }

        guard hasValidCollectionIdentity(snapshot) else {
            return fallbackResult(
                reason: .invalidCollectionIdentity,
                recordedAt: evaluatedAt,
                tokenState: tokenState,
                snapshot: snapshot
            )
        }
        guard snapshot.coinBalance.schemaVersion == CoinBalanceSnapshot.currentSchemaVersion else {
            return fallbackResult(
                reason: .unsupportedCoinBalanceSchema,
                recordedAt: evaluatedAt,
                tokenState: tokenState,
                snapshot: snapshot
            )
        }

        let rulesByID = Dictionary(uniqueKeysWithValues: snapshot.rules.rules.map { ($0.id, $0) })
        let evaluation = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: snapshot.activeRestrictions,
            currentRuleRevisions: Dictionary(
                uniqueKeysWithValues: snapshot.rules.rules.map { ($0.id, $0.revision) }
            ),
            now: evaluatedAt
        )
        let matchingOccurrences: [(
            occurrence: RestrictionOccurrence,
            rule: RestrictionRuleSnapshot
        )] = evaluation.orderedOccurrences.compactMap { occurrence in
            guard
                let rule = rulesByID[occurrence.ruleID],
                matches(
                rule.activitySelection,
                applicationToken: applicationToken,
                categoryToken: categoryToken,
                webDomainToken: webDomainToken
                )
            else {
                return nil
            }
            return (occurrence: occurrence, rule: rule)
        }

        guard let representativeMatch = matchingOccurrences.first else {
            return fallbackResult(
                reason: .noMatchingOccurrence,
                recordedAt: evaluatedAt,
                tokenState: tokenState,
                snapshot: snapshot,
                activeOccurrenceCount: evaluation.orderedOccurrences.count,
                matchingOccurrenceCount: 0
            )
        }
        guard let place = snapshot.savedPlaces.places.first(where: {
            $0.id == representativeMatch.rule.savedPlaceID
        }) else {
            return fallbackResult(
                reason: .missingSavedPlace,
                recordedAt: evaluatedAt,
                tokenState: tokenState,
                snapshot: snapshot,
                activeOccurrenceCount: evaluation.orderedOccurrences.count,
                matchingOccurrenceCount: matchingOccurrences.count
            )
        }

        return ShieldContentResult(
            content: releaseContent(
                occurrence: representativeMatch.occurrence,
                rule: representativeMatch.rule,
                place: place,
                additionalRestrictionCount: matchingOccurrences.count - 1
            ),
            diagnostic: diagnostic(
                outcome: .releaseContent,
                reason: .none,
                recordedAt: evaluatedAt,
                tokenState: tokenState,
                snapshot: snapshot,
                activeOccurrenceCount: evaluation.orderedOccurrences.count,
                matchingOccurrenceCount: matchingOccurrences.count
            )
        )
    }

    private struct TokenState {
        let hasApplicationToken: Bool
        let hasCategoryToken: Bool
        let hasWebDomainToken: Bool

        var hasAnyToken: Bool {
            hasApplicationToken || hasCategoryToken || hasWebDomainToken
        }
    }

    private func fallbackResult(
        snapshotError error: any Error,
        recordedAt: Date,
        tokenState: TokenState
    ) -> ShieldContentResult {
        let details: (
            reason: ShieldContentFallbackReason,
            fileName: String?,
            found: Int?,
            supported: Int?
        )
        switch error as? ShieldSnapshotReaderError {
        case .missingAppGroupIdentifier:
            details = (.missingAppGroupIdentifier, nil, nil, nil)
        case .appGroupContainerUnavailable:
            details = (.appGroupContainerUnavailable, nil, nil, nil)
        case let .snapshotMissing(fileName):
            details = (.snapshotMissing, fileName, nil, nil)
        case let .snapshotReadFailed(fileName):
            details = (.snapshotReadFailed, fileName, nil, nil)
        case let .snapshotDecodingFailed(fileName):
            details = (.snapshotDecodingFailed, fileName, nil, nil)
        case let .unsupportedSchema(fileName, found, supported):
            details = (.unsupportedSchema, fileName, found, supported)
        case nil:
            details = (.unknownSnapshotError, nil, nil, nil)
        }
        return ShieldContentResult(
            content: fallbackContent,
            diagnostic: diagnostic(
                outcome: .fallback,
                reason: details.reason,
                recordedAt: recordedAt,
                tokenState: tokenState,
                failingFileName: details.fileName,
                foundSchemaVersion: details.found,
                supportedSchemaVersion: details.supported
            )
        )
    }

    private func fallbackResult(
        reason: ShieldContentFallbackReason,
        recordedAt: Date,
        tokenState: TokenState,
        snapshot: ShieldContentSnapshot? = nil,
        activeOccurrenceCount: Int? = nil,
        matchingOccurrenceCount: Int? = nil
    ) -> ShieldContentResult {
        ShieldContentResult(
            content: fallbackContent,
            diagnostic: diagnostic(
                outcome: .fallback,
                reason: reason,
                recordedAt: recordedAt,
                tokenState: tokenState,
                snapshot: snapshot,
                activeOccurrenceCount: activeOccurrenceCount,
                matchingOccurrenceCount: matchingOccurrenceCount
            )
        )
    }

    private func diagnostic(
        outcome: ShieldContentDiagnosticOutcome,
        reason: ShieldContentFallbackReason,
        recordedAt: Date,
        tokenState: TokenState,
        snapshot: ShieldContentSnapshot? = nil,
        activeOccurrenceCount: Int? = nil,
        matchingOccurrenceCount: Int? = nil,
        failingFileName: String? = nil,
        foundSchemaVersion: Int? = nil,
        supportedSchemaVersion: Int? = nil
    ) -> ShieldContentDiagnostic {
        ShieldContentDiagnostic(
            recordedAt: recordedAt,
            outcome: outcome,
            fallbackReason: reason,
            failingFileName: failingFileName,
            foundSchemaVersion: foundSchemaVersion,
            supportedSchemaVersion: supportedSchemaVersion,
            rulesSchemaVersion: snapshot?.rules.schemaVersion,
            savedPlacesSchemaVersion: snapshot?.savedPlaces.schemaVersion,
            activeRestrictionsSchemaVersion: snapshot?.activeRestrictions.schemaVersion,
            coinBalanceSchemaVersion: snapshot?.coinBalance.schemaVersion,
            ruleCount: snapshot?.rules.rules.count,
            savedPlaceCount: snapshot?.savedPlaces.places.count,
            activeOccurrenceCount: activeOccurrenceCount,
            matchingOccurrenceCount: matchingOccurrenceCount,
            hasApplicationToken: tokenState.hasApplicationToken,
            hasCategoryToken: tokenState.hasCategoryToken,
            hasWebDomainToken: tokenState.hasWebDomainToken
        )
    }

    private func matches(
        _ selection: FamilyActivitySelection,
        applicationToken: ApplicationToken?,
        categoryToken: ActivityCategoryToken?,
        webDomainToken: WebDomainToken?
    ) -> Bool {
        if let applicationToken,
           shieldTokenMatches(
               applicationToken,
               storedTokens: selection.applicationTokens,
               refresh: tokenRefresher.applicationTokens
           ) {
            return true
        }
        if let categoryToken,
           shieldTokenMatches(
               categoryToken,
               storedTokens: selection.categoryTokens,
               refresh: tokenRefresher.categoryTokens
           ) {
            return true
        }
        if let webDomainToken,
           shieldTokenMatches(
               webDomainToken,
               storedTokens: selection.webDomainTokens,
               refresh: tokenRefresher.webDomainTokens
           ) {
            return true
        }
        return false
    }

    private func releaseContent(
        occurrence: RestrictionOccurrence,
        rule: RestrictionRuleSnapshot,
        place: SavedPlaceSnapshot,
        additionalRestrictionCount: Int
    ) -> ShieldContent {
        let radius = radiusLabel(rule.radius)
        let endTime = timeLabel(occurrence.endAt)
        let placeName = localizedPresetPlaceName(place.name)
        let representativeName = rule.name.flatMap { name in
            let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalized.isEmpty ? nil : normalized
        } ?? placeName
        let titleFormat = localized(
            "shield.title.outside_radius",
            value: "%@에서 %@ 밖으로 나서세요"
        )
        let subtitle: String
        if additionalRestrictionCount == 0 {
            subtitle = String(
                format: localized(
                    "shield.subtitle.release_confirmation.single",
                    value: "대표 규칙 ‘%@’ · %@까지 적용돼요. 무료 해제권을 먼저 사용하고, 없으면 구매 코인 1개를 사용해 이번 구간만 해제해요. 다른 규칙의 제한은 남지 않아요."
                ),
                representativeName,
                endTime
            )
        } else {
            subtitle = String(
                format: localized(
                    "shield.subtitle.release_confirmation.multiple",
                    value: "대표 규칙 ‘%@’ · %@까지 적용돼요. 무료 해제권을 먼저 사용하고, 없으면 구매 코인 1개를 사용해 이번 구간만 해제해요. 다른 규칙 %d개의 제한은 남아요."
                ),
                representativeName,
                endTime,
                additionalRestrictionCount
            )
        }

        return ShieldContent(
            title: String(format: titleFormat, placeName, radius),
            subtitle: subtitle,
            primaryButtonLabel: releaseButtonLabel,
            secondaryButtonLabel: closeButtonLabel,
            releaseFundingPolicy: .latestLedgerFreeFirst(
                purchasedFallbackQuantity: 1
            )
        )
    }

    private var fallbackContent: ShieldContent {
        ShieldContent(
            title: localized(
                "shield.title.fallback",
                value: "밖으로 나설 시간이에요"
            ),
            subtitle: localized(
                "shield.subtitle.fallback",
                value: "설정한 위치에서 벗어나거나 시간이 끝나면 자동으로 다시 사용할 수 있어요."
            ),
            primaryButtonLabel: closeButtonLabel,
            secondaryButtonLabel: nil,
            releaseFundingPolicy: nil
        )
    }

    private func hasValidCollectionIdentity(_ snapshot: ShieldContentSnapshot) -> Bool {
        let ruleIDs = snapshot.rules.rules.map(\.id)
        let placeIDs = snapshot.savedPlaces.places.map(\.id)
        return Set(ruleIDs).count == ruleIDs.count
            && Set(placeIDs).count == placeIDs.count
            && snapshot.rules.rules.allSatisfy {
                $0.schemaVersion == RestrictionRuleSnapshot.currentSchemaVersion
            }
    }

    private var releaseButtonLabel: String {
        localized("shield.primary.release", value: "해제권 1회 사용")
    }

    private var closeButtonLabel: String {
        localized("shield.primary.close", value: "앱 닫기")
    }

    private func localized(_ key: String, value: String) -> String {
        NSLocalizedString(key, bundle: bundle, value: value, comment: "")
    }

    private func localizedPresetPlaceName(_ storedName: String) -> String {
        switch storedName {
        case "집", "회사":
            localized(storedName, value: storedName)
        default:
            storedName
        }
    }

    private func radiusLabel(_ radius: RadiusOption) -> String {
        if radius.rawValue < 1_000 {
            return "\(radius.rawValue)m"
        }
        return "\(radius.rawValue / 1_000)km"
    }

    private func timeLabel(_ date: Date) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let hour = components.hour ?? 0
        let minute = components.minute ?? 0
        let period = hour < 12 ? "AM" : "PM"
        let twelveHour = hour % 12 == 0 ? 12 : hour % 12
        return String(format: "%02d:%02d %@", twelveHour, minute, period)
    }
}

#if DEBUG
struct ShieldContentDiagnosticRecorder {
    private let bundle: Bundle

    init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    func record(_ diagnostic: ShieldContentDiagnostic) {
        guard
            let identifier = SharedIdentifiers.appGroupIdentifier(in: bundle),
            let defaults = UserDefaults(suiteName: identifier)
        else {
            return
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(diagnostic) else {
            return
        }
        defaults.set(data, forKey: SharedIdentifiers.shieldContentDiagnosticDefaultsKey)
        defaults.set(
            diagnostic.fallbackReason.rawValue,
            forKey: "\(SharedIdentifiers.shieldContentDiagnosticDefaultsKey).reason"
        )
        // Shield configuration extensions may be suspended immediately after
        // returning their value, so flush this DEBUG-only evidence eagerly.
        defaults.synchronize()
    }
}
#endif

struct ShieldMonthlyAllowanceUITestFixture: Equatable, Sendable {
    let initialBalance: CoinBalanceSnapshot
    let balanceAfterAtomicReservation: CoinBalanceSnapshot
    let createsAllowanceOnRequest: Bool

    static func firstRequest(now: Date, purchasedAvailable: Int = 3) throws -> Self {
        let monthID = MonthlyAllowancePolicy.monthID(containing: now)
        let epochID = UUID(uuidString: "00000000-0000-4000-8000-000000000592")!
        return try ShieldMonthlyAllowanceUITestFixture(
            initialBalance: CoinBalanceSnapshot(
                purchasedAvailable: purchasedAvailable,
                currentMonthID: monthID,
                freeAvailable: MonthlyAllowancePolicy.monthlyQuota,
                syncState: .current,
                syncedAt: now,
                ledgerEpochID: epochID,
                hadConfirmedLedger: true
            ),
            balanceAfterAtomicReservation: CoinBalanceSnapshot(
                purchasedAvailable: purchasedAvailable,
                currentMonthID: monthID,
                freeAvailable: MonthlyAllowancePolicy.monthlyQuota - 1,
                syncState: .current,
                syncedAt: now,
                ledgerEpochID: epochID,
                hadConfirmedLedger: true
            ),
            createsAllowanceOnRequest: true
        )
    }

    static func existingAllowance(now: Date, purchasedAvailable: Int = 3) throws -> Self {
        let fixture = try firstRequest(now: now, purchasedAvailable: purchasedAvailable)
        return ShieldMonthlyAllowanceUITestFixture(
            initialBalance: fixture.initialBalance,
            balanceAfterAtomicReservation: fixture.balanceAfterAtomicReservation,
            createsAllowanceOnRequest: false
        )
    }
}
