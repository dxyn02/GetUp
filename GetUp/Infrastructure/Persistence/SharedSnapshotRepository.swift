@preconcurrency import FamilyControls
import Foundation

enum SharedSnapshotRepositoryError: Error, Equatable, Sendable {
    case encodingFailed(fileName: String)
    case decodingFailed(fileName: String)
    case unsupportedSchema(fileName: String, found: Int, supported: Int)
    case revisionMismatch(expected: Int, actual: Int)
    case readFailed(fileName: String)
    case atomicWriteFailed(fileName: String)
    case deletionFailed(fileName: String)
}

protocol SnapshotFileWriting: Sendable {
    func write(_ data: Data, to destinationURL: URL) throws
}

struct AtomicSnapshotFileWriter: SnapshotFileWriting {
    static let writingOptions: Data.WritingOptions = [
        .atomic,
        .completeFileProtectionUntilFirstUserAuthentication,
    ]

    func write(_ data: Data, to destinationURL: URL) throws {
        try data.write(
            to: destinationURL,
            options: Self.writingOptions
        )
    }
}

actor SharedSnapshotRepository: RuleRepository, SavedPlaceRepository, LocationConditionRepository {
    private let containerURL: URL
    private let fileWriter: any SnapshotFileWriting

    init(
        containerURL: URL,
        fileWriter: any SnapshotFileWriting = AtomicSnapshotFileWriter()
    ) {
        self.containerURL = containerURL
        self.fileWriter = fileWriter
    }

    func loadRuleCollection() async throws -> RestrictionRuleCollectionSnapshot? {
        if let collection: RestrictionRuleCollectionSnapshot = try loadSnapshot(
            RestrictionRuleCollectionSnapshot.self,
            fileName: SharedIdentifiers.restrictionRulesFileName,
            supportedSchemaVersion: RestrictionRuleCollectionSnapshot.currentSchemaVersion
        ) {
            return collection
        }

        return try loadLegacyConfiguration()?.rules
    }

    func saveRuleCollection(_ collection: RestrictionRuleCollectionSnapshot) async throws {
        try saveSnapshot(
            collection,
            fileName: SharedIdentifiers.restrictionRulesFileName
        )
    }

    func deleteRuleCollection() async throws {
        try deleteSnapshot(fileName: SharedIdentifiers.restrictionRulesFileName)
    }

    func loadRule() async throws -> RestrictionRuleSnapshot? {
        try await loadRuleCollection()?.rules.first
    }

    func saveRule(_ rule: RestrictionRuleSnapshot) async throws {
        try await saveRuleCollection(
            RestrictionRuleCollectionSnapshot(
                revision: rule.revision,
                rules: [rule]
            )
        )
    }

    func deleteRule() async throws {
        try await deleteRuleCollection()
    }

    func loadSavedPlaceCollection() async throws -> SavedPlaceCollectionSnapshot? {
        if let collection: SavedPlaceCollectionSnapshot = try loadSnapshot(
            SavedPlaceCollectionSnapshot.self,
            fileName: SharedIdentifiers.savedPlacesFileName,
            supportedSchemaVersion: SavedPlaceCollectionSnapshot.currentSchemaVersion
        ) {
            return collection
        }

        return try loadLegacyConfiguration()?.places
    }

    func saveSavedPlaceCollection(_ collection: SavedPlaceCollectionSnapshot) async throws {
        try saveSnapshot(collection, fileName: SharedIdentifiers.savedPlacesFileName)
    }

    func deleteSavedPlaceCollection() async throws {
        try deleteSnapshot(fileName: SharedIdentifiers.savedPlacesFileName)
    }

    func loadLocationConditionCollection() async throws -> LocationConditionCollectionSnapshot? {
        let fileName = SharedIdentifiers.locationConditionFileName
        let fileURL = containerURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SharedSnapshotRepositoryError.readFailed(fileName: fileName)
        }

        let decoder = makeDecoder()
        let header: SchemaHeader
        do {
            header = try decoder.decode(SchemaHeader.self, from: data)
        } catch {
            throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName)
        }

        switch header.schemaVersion {
        case LocationConditionCollectionSnapshot.currentSchemaVersion:
            do {
                return try decoder.decode(LocationConditionCollectionSnapshot.self, from: data)
            } catch {
                throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName)
            }
        case LegacyLocationConditionSnapshot.currentSchemaVersion:
            do {
                _ = try decoder.decode(LegacyLocationConditionSnapshot.self, from: data)
                return LocationConditionCollectionSnapshot(conditions: [])
            } catch {
                throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName)
            }
        default:
            throw SharedSnapshotRepositoryError.unsupportedSchema(
                fileName: fileName,
                found: header.schemaVersion,
                supported: LocationConditionCollectionSnapshot.currentSchemaVersion
            )
        }
    }

    func saveLocationCondition(_ condition: LocationConditionSnapshot) async throws {
        var conditions = try await loadLocationConditionCollection()?.conditions ?? []
        conditions.removeAll { $0.ruleID == condition.ruleID }
        conditions.append(condition)
        conditions.sort { $0.ruleID.uuidString < $1.ruleID.uuidString }
        try saveSnapshot(
            LocationConditionCollectionSnapshot(conditions: conditions),
            fileName: SharedIdentifiers.locationConditionFileName
        )
    }

    func deleteLocationCondition(for ruleID: UUID) async throws {
        guard var collection = try await loadLocationConditionCollection() else {
            return
        }
        collection = LocationConditionCollectionSnapshot(
            conditions: collection.conditions.filter { $0.ruleID != ruleID }
        )
        try saveSnapshot(
            collection,
            fileName: SharedIdentifiers.locationConditionFileName
        )
    }

    func deleteLocationConditions() async throws {
        try deleteSnapshot(fileName: SharedIdentifiers.locationConditionFileName)
    }

    private func loadSnapshot<Snapshot: Decodable>(
        _ type: Snapshot.Type,
        fileName: String,
        supportedSchemaVersion: Int
    ) throws -> Snapshot? {
        let fileURL = containerURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            throw SharedSnapshotRepositoryError.readFailed(fileName: fileName)
        }

        let decoder = makeDecoder()
        let header: SchemaHeader
        do {
            header = try decoder.decode(SchemaHeader.self, from: data)
        } catch {
            throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName)
        }

        guard header.schemaVersion == supportedSchemaVersion else {
            throw SharedSnapshotRepositoryError.unsupportedSchema(
                fileName: fileName,
                found: header.schemaVersion,
                supported: supportedSchemaVersion
            )
        }

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName)
        }
    }

    private func saveSnapshot<Snapshot: Encodable>(
        _ snapshot: Snapshot,
        fileName: String
    ) throws {
        let data: Data
        do {
            data = try makeEncoder().encode(snapshot)
        } catch {
            throw SharedSnapshotRepositoryError.encodingFailed(fileName: fileName)
        }

        do {
            try fileWriter.write(
                data,
                to: containerURL.appendingPathComponent(fileName)
            )
        } catch {
            throw SharedSnapshotRepositoryError.atomicWriteFailed(fileName: fileName)
        }
    }

    private func deleteSnapshot(fileName: String) throws {
        let fileURL = containerURL.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch {
            throw SharedSnapshotRepositoryError.deletionFailed(fileName: fileName)
        }
    }

    private func loadLegacyConfiguration() throws -> LegacyConfiguration? {
        guard let legacy: LegacyRestrictionRuleSnapshot = try loadSnapshot(
            LegacyRestrictionRuleSnapshot.self,
            fileName: SharedIdentifiers.legacyRestrictionRuleFileName,
            supportedSchemaVersion: LegacyRestrictionRuleSnapshot.currentSchemaVersion
        ) else {
            return nil
        }

        let rule = RestrictionRuleSnapshot(
            id: LegacyConfiguration.ruleID,
            revision: legacy.revision,
            name: nil,
            isEnabled: legacy.isEnabled,
            weekdays: legacy.weekdays,
            startTime: legacy.startTime,
            endTime: legacy.endTime,
            savedPlaceID: LegacyConfiguration.placeID,
            radius: legacy.radius,
            activitySelection: legacy.activitySelection,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )
        let place = SavedPlaceSnapshot(
            id: LegacyConfiguration.placeID,
            name: "기존 장소",
            coordinate: legacy.referenceLocation,
            createdAt: legacy.createdAt,
            updatedAt: legacy.updatedAt
        )

        return LegacyConfiguration(
            rules: RestrictionRuleCollectionSnapshot(
                revision: legacy.revision,
                rules: [rule]
            ),
            places: SavedPlaceCollectionSnapshot(
                revision: legacy.revision,
                places: [place]
            )
        )
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct SchemaHeader: Decodable {
    let schemaVersion: Int
}

private struct LegacyLocationConditionSnapshot: Codable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let ruleRevision: Int
    let state: LocationConditionState
    let observedAt: Date
    let distanceMeters: Double?
    let horizontalAccuracyMeters: Double?
    let source: LocationConditionSource
}

private struct LegacyRestrictionRuleSnapshot: Codable, @unchecked Sendable {
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

private struct LegacyConfiguration {
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!
    static let placeID = UUID(uuidString: "00000000-0000-4000-8000-000000000002")!

    let rules: RestrictionRuleCollectionSnapshot
    let places: SavedPlaceCollectionSnapshot
}
