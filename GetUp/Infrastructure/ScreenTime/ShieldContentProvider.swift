@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings

struct ShieldContentSnapshot: Equatable, @unchecked Sendable {
    let rules: RestrictionRuleCollectionSnapshot
    let savedPlaces: SavedPlaceCollectionSnapshot
    let activeRuleRevisions: Set<ActiveRuleRevision>
}

protocol ShieldSnapshotReading {
    func readSnapshot() throws -> ShieldContentSnapshot
}

enum ShieldSnapshotReaderError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case appGroupContainerUnavailable
    case sharedDefaultsUnavailable
    case snapshotUnavailable
    case unsupportedSchema
    case appliedStateUnavailable
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
        guard let defaults = UserDefaults(suiteName: identifier) else {
            throw ShieldSnapshotReaderError.sharedDefaultsUnavailable
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
        guard
            rules.schemaVersion == RestrictionRuleCollectionSnapshot.currentSchemaVersion,
            places.schemaVersion == SavedPlaceCollectionSnapshot.currentSchemaVersion
        else {
            throw ShieldSnapshotReaderError.unsupportedSchema
        }
        guard
            let appliedData = defaults.data(
                forKey: SharedIdentifiers.activeRuleRevisionsDefaultsKey
            ),
            let activeRuleRevisions = try? decoder.decode(
                Set<ActiveRuleRevision>.self,
                from: appliedData
            )
        else {
            throw ShieldSnapshotReaderError.appliedStateUnavailable
        }

        return ShieldContentSnapshot(
            rules: rules,
            savedPlaces: places,
            activeRuleRevisions: activeRuleRevisions
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
}

struct ShieldContentProvider {
    private let snapshotReader: any ShieldSnapshotReading
    private let bundle: Bundle

    init(
        snapshotReader: any ShieldSnapshotReading,
        bundle: Bundle = .main
    ) {
        self.snapshotReader = snapshotReader
        self.bundle = bundle
    }

    func content(for applicationToken: ApplicationToken?) -> ShieldContent {
        guard
            let applicationToken,
            let snapshot = try? snapshotReader.readSnapshot()
        else {
            return fallbackContent
        }

        let matchingRules = snapshot.rules.rules.filter { rule in
            snapshot.activeRuleRevisions.contains(
                ActiveRuleRevision(ruleID: rule.id, revision: rule.revision)
            ) && rule.activitySelection.applicationTokens.contains(applicationToken)
        }

        switch matchingRules.count {
        case 1:
            guard
                let rule = matchingRules.first,
                let place = snapshot.savedPlaces.places.first(where: {
                    $0.id == rule.savedPlaceID
                })
            else {
                return fallbackContent
            }
            return detailedContent(rule: rule, place: place)
        case 2...:
            return multipleRulesContent(count: matchingRules.count)
        default:
            return fallbackContent
        }
    }

    private func detailedContent(
        rule: RestrictionRuleSnapshot,
        place: SavedPlaceSnapshot
    ) -> ShieldContent {
        let radius = radiusLabel(rule.radius)
        let endTime = timeLabel(rule.endTime)
        let titleFormat = localized(
            "shield.title.outside_radius",
            value: "%@ %@ 밖으로 이동하세요"
        )
        let subtitleFormat = localized(
            "shield.subtitle.release_condition",
            value: "현재 ‘%@’의 %@ 범위 안에 있어요. %@의 중심에서 %@ 밖으로 이동하거나 %@이 되면 자동으로 다시 사용할 수 있어요."
        )

        return ShieldContent(
            title: String(format: titleFormat, place.name, radius),
            subtitle: String(
                format: subtitleFormat,
                place.name,
                radius,
                place.name,
                radius,
                endTime
            ),
            primaryButtonLabel: primaryButtonLabel
        )
    }

    private func multipleRulesContent(count: Int) -> ShieldContent {
        let titleFormat = localized(
            "shield.title.multiple_rules",
            value: "%d개 제한 규칙이 활성화 중이에요"
        )
        return ShieldContent(
            title: String(format: titleFormat, count),
            subtitle: localized(
                "shield.subtitle.multiple_rules",
                value: "각 규칙의 위치 또는 시간이 모두 끝나면 다시 사용할 수 있어요."
            ),
            primaryButtonLabel: primaryButtonLabel
        )
    }

    private var fallbackContent: ShieldContent {
        ShieldContent(
            title: localized(
                "shield.title.fallback",
                value: "앱 사용 제한이 활성화되었어요"
            ),
            subtitle: localized(
                "shield.subtitle.fallback",
                value: "설정한 위치 또는 시간이 끝나면 자동으로 다시 사용할 수 있어요."
            ),
            primaryButtonLabel: primaryButtonLabel
        )
    }

    private var primaryButtonLabel: String {
        localized("shield.primary.close", value: "앱 닫기")
    }

    private func localized(_ key: String, value: String) -> String {
        NSLocalizedString(key, bundle: bundle, value: value, comment: "")
    }

    private func radiusLabel(_ radius: RadiusOption) -> String {
        if radius.rawValue < 1_000 {
            return "\(radius.rawValue)m"
        }
        return "\(radius.rawValue / 1_000)km"
    }

    private func timeLabel(_ time: TimeOfDay) -> String {
        let period = time.hour < 12 ? "AM" : "PM"
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        return String(format: "%02d:%02d %@", hour, time.minute, period)
    }
}
