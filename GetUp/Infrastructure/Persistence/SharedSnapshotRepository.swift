import Foundation

enum SharedSnapshotRepositoryError: Error, Equatable {
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
    func write(_ data: Data, to destinationURL: URL) throws {
        try data.write(
            to: destinationURL,
            options: [
                .atomic,
                .completeFileProtectionUntilFirstUserAuthentication,
            ]
        )
    }
}

actor SharedSnapshotRepository: RuleRepository, LocationConditionRepository {
    private let containerURL: URL
    private let fileWriter: any SnapshotFileWriting
    private let fileManager: FileManager

    init(
        containerURL: URL,
        fileWriter: any SnapshotFileWriting = AtomicSnapshotFileWriter(),
        fileManager: FileManager = .default
    ) {
        self.containerURL = containerURL
        self.fileWriter = fileWriter
        self.fileManager = fileManager
    }

    func loadRule() async throws -> RestrictionRuleSnapshot? {
        try loadSnapshot(
            RestrictionRuleSnapshot.self,
            fileName: SharedIdentifiers.restrictionRuleFileName,
            supportedSchemaVersion: RestrictionRuleSnapshot.currentSchemaVersion
        )
    }

    func saveRule(_ rule: RestrictionRuleSnapshot) async throws {
        try saveSnapshot(
            rule,
            fileName: SharedIdentifiers.restrictionRuleFileName
        )
    }

    func deleteRule() async throws {
        try deleteSnapshot(fileName: SharedIdentifiers.restrictionRuleFileName)
    }

    func loadLocationCondition() async throws -> LocationConditionSnapshot? {
        guard
            let condition: LocationConditionSnapshot = try loadSnapshot(
                LocationConditionSnapshot.self,
                fileName: SharedIdentifiers.locationConditionFileName,
                supportedSchemaVersion: LocationConditionSnapshot.currentSchemaVersion
            )
        else {
            return nil
        }

        guard let rule = try await loadRule() else {
            return nil
        }
        guard condition.ruleRevision == rule.revision else {
            throw SharedSnapshotRepositoryError.revisionMismatch(
                expected: rule.revision,
                actual: condition.ruleRevision
            )
        }

        return condition
    }

    func saveLocationCondition(_ condition: LocationConditionSnapshot) async throws {
        try saveSnapshot(
            condition,
            fileName: SharedIdentifiers.locationConditionFileName
        )
    }

    func deleteLocationCondition() async throws {
        try deleteSnapshot(fileName: SharedIdentifiers.locationConditionFileName)
    }

    private func loadSnapshot<Snapshot: Decodable>(
        _ type: Snapshot.Type,
        fileName: String,
        supportedSchemaVersion: Int
    ) throws -> Snapshot? {
        let fileURL = containerURL.appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
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
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return
        }

        do {
            try fileManager.removeItem(at: fileURL)
        } catch {
            throw SharedSnapshotRepositoryError.deletionFailed(fileName: fileName)
        }
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
