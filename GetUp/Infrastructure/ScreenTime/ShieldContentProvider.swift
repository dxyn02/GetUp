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
    case snapshotUnavailable
    case unsupportedSchema
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
        guard
            rules.schemaVersion == RestrictionRuleCollectionSnapshot.currentSchemaVersion,
            places.schemaVersion == SavedPlaceCollectionSnapshot.currentSchemaVersion,
            activeRestrictions.schemaVersion == ActiveRestrictionSnapshot.currentSchemaVersion,
            coinBalance.schemaVersion == CoinBalanceSnapshot.currentSchemaVersion
        else {
            throw ShieldSnapshotReaderError.unsupportedSchema
        }

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
        guard
            let data = try? Data(contentsOf: fileURL),
            let value = try? decoder.decode(type, from: data)
        else {
            throw ShieldSnapshotReaderError.snapshotUnavailable
        }
        return value
    }
}

struct ShieldContent: Equatable, Sendable {
    let title: String
    let subtitle: String
    let primaryButtonLabel: String
    let secondaryButtonLabel: String?
}

struct ShieldContentProvider {
    private let snapshotReader: any ShieldSnapshotReading
    private let bundle: Bundle
    private let now: () -> Date
    private let calendar: Calendar

    init(
        snapshotReader: any ShieldSnapshotReading,
        bundle: Bundle = .main,
        now: @escaping () -> Date = Date.init,
        calendar: Calendar = .current
    ) {
        self.snapshotReader = snapshotReader
        self.bundle = bundle
        self.now = now
        self.calendar = calendar
    }

    func content(
        for applicationToken: ApplicationToken?,
        categoryToken: ActivityCategoryToken? = nil,
        webDomainToken: WebDomainToken? = nil
    ) -> ShieldContent {
        guard
            applicationToken != nil || categoryToken != nil || webDomainToken != nil,
            let snapshot = try? snapshotReader.readSnapshot(),
            hasValidCollectionIdentity(snapshot),
            snapshot.coinBalance.schemaVersion == CoinBalanceSnapshot.currentSchemaVersion
        else {
            return fallbackContent
        }

        let rulesByID = Dictionary(uniqueKeysWithValues: snapshot.rules.rules.map { ($0.id, $0) })
        let evaluation = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: snapshot.activeRestrictions,
            currentRuleRevisions: Dictionary(
                uniqueKeysWithValues: snapshot.rules.rules.map { ($0.id, $0.revision) }
            ),
            now: now()
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

        guard
            let representativeMatch = matchingOccurrences.first,
            let place = snapshot.savedPlaces.places.first(where: {
                $0.id == representativeMatch.rule.savedPlaceID
            })
        else {
            return fallbackContent
        }

        return releaseContent(
            occurrence: representativeMatch.occurrence,
            rule: representativeMatch.rule,
            place: place,
            additionalRestrictionCount: matchingOccurrences.count - 1
        )
    }

    private func matches(
        _ selection: FamilyActivitySelection,
        applicationToken: ApplicationToken?,
        categoryToken: ActivityCategoryToken?,
        webDomainToken: WebDomainToken?
    ) -> Bool {
        if let applicationToken,
           selection.applicationTokens.contains(applicationToken) {
            return true
        }
        if let categoryToken,
           selection.categoryTokens.contains(categoryToken) {
            return true
        }
        if let webDomainToken,
           selection.webDomainTokens.contains(webDomainToken) {
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
            secondaryButtonLabel: closeButtonLabel
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
            secondaryButtonLabel: nil
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
