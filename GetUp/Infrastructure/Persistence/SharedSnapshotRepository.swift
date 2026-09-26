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

actor SharedSnapshotRepository: RuleRepository, SavedPlaceRepository, LocationConditionRepository,
    ActiveRestrictionSnapshotRepository, CoinBalanceSnapshotRepository,
    ReleaseExceptionRepository
{
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

    func loadLocationConditions(
        matching rules: [RestrictionRuleSnapshot]
    ) async throws -> [LocationConditionSnapshot] {
        let currentRevisions = rules.reduce(into: [UUID: Int]()) {
            $0[$1.id] = $1.revision
        }
        return try await loadLocationConditionCollection()?.conditions.filter {
            currentRevisions[$0.ruleID] == $0.ruleRevision
        }.sorted {
            $0.ruleID.uuidString < $1.ruleID.uuidString
        } ?? []
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

    func loadActiveRestrictionSnapshot() async throws -> ActiveRestrictionSnapshot? {
        try loadSnapshot(
            ActiveRestrictionSnapshot.self,
            fileName: SharedIdentifiers.activeRestrictionSnapshotFileName,
            supportedSchemaVersion: ActiveRestrictionSnapshot.currentSchemaVersion
        )
    }

    func saveActiveRestrictionSnapshot(
        _ snapshot: ActiveRestrictionSnapshot
    ) async throws {
        try saveSnapshot(
            snapshot,
            fileName: SharedIdentifiers.activeRestrictionSnapshotFileName
        )
    }

    func loadCoinBalanceSnapshot() async throws -> CoinBalanceSnapshot? {
        try loadSnapshot(
            CoinBalanceSnapshot.self,
            fileName: SharedIdentifiers.coinBalanceSnapshotFileName,
            supportedSchemaVersion: CoinBalanceSnapshot.currentSchemaVersion
        )
    }

    func saveCoinBalanceSnapshot(_ snapshot: CoinBalanceSnapshot) async throws {
        try saveSnapshot(
            snapshot,
            fileName: SharedIdentifiers.coinBalanceSnapshotFileName
        )
    }

    func loadReleaseExceptions() async throws -> [ReleaseException] {
        try ReleaseExceptionFileStore(containerURL: containerURL, fileWriter: fileWriter).load()
    }

    func saveReleaseExceptions(_ exceptions: [ReleaseException]) async throws {
        try ReleaseExceptionFileStore(containerURL: containerURL, fileWriter: fileWriter).save(exceptions)
    }

    func insertReleaseException(_ exception: ReleaseException) async throws -> [ReleaseException] {
        try ReleaseExceptionFileStore(containerURL: containerURL, fileWriter: fileWriter).insert(exception)
    }

    func removeReleaseException(commandID: UUID, occurrenceID: String) async throws -> [ReleaseException] {
        try ReleaseExceptionFileStore(containerURL: containerURL, fileWriter: fileWriter)
            .remove(commandID: commandID, occurrenceID: occurrenceID)
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

actor PendingAppRouteRepository: PendingAppRoutePersisting {
    static let validityDuration: TimeInterval = 5 * 60

    private let containerURL: URL
    private let fileWriter: any SnapshotFileWriting

    init(
        containerURL: URL,
        fileWriter: any SnapshotFileWriting = AtomicSnapshotFileWriter()
    ) {
        self.containerURL = containerURL
        self.fileWriter = fileWriter
    }

    func save(_ route: PendingAppRoute) async throws {
        let data: Data
        do {
            data = try makeEncoder().encode(route)
        } catch {
            throw SharedSnapshotRepositoryError.encodingFailed(fileName: fileName)
        }

        do {
            try fileWriter.write(data, to: fileURL)
        } catch {
            throw SharedSnapshotRepositoryError.atomicWriteFailed(fileName: fileName)
        }
    }

    func load() async throws -> PendingAppRoute? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            // Another process or repository instance may consume the route
            // after the existence check. Treat that atomic winner as an
            // already-consumed route instead of surfacing a read failure.
            return nil
        } catch {
            throw SharedSnapshotRepositoryError.readFailed(fileName: fileName)
        }

        do {
            return try makeDecoder().decode(PendingAppRoute.self, from: data)
        } catch {
            throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName)
        }
    }

    func discard() async throws {
        guard let claimedFileURL = try claimRouteFileIfPresent() else {
            return
        }
        do {
            try FileManager.default.removeItem(at: claimedFileURL)
        } catch {
            throw SharedSnapshotRepositoryError.deletionFailed(fileName: fileName)
        }
    }

    func consumeIfEligible(
        now: Date,
        activeOccurrenceIDs: Set<String>
    ) async throws -> PendingAppRoute? {
        guard let claimedFileURL = try claimRouteFileIfPresent() else {
            return nil
        }
        let route = try readClaimedRoute(at: claimedFileURL)

        if route.destination == .releaseProcessing {
            switch route.state {
            case .processing, .terminal:
                try restoreClaimedFile(at: claimedFileURL)
                return route
            case .pending:
                let age = now.timeIntervalSince(route.createdAt)
                let hasActiveOccurrence = route.occurrenceID.map {
                    activeOccurrenceIDs.contains($0)
                } ?? false
                guard route.consumedAt == nil,
                      age >= 0,
                      age < Self.validityDuration,
                      hasActiveOccurrence else {
                    try deleteClaimedFile(at: claimedFileURL)
                    return nil
                }
                let processing = try route.claiming(at: now)
                try persist(processing, replacingClaimedFileAt: claimedFileURL)
                return processing
            }
        }

        let age = now.timeIntervalSince(route.createdAt)
        let isWithinValidityWindow = age >= 0 && age < Self.validityDuration
        let hasActiveOccurrence = route.occurrenceID.map {
            activeOccurrenceIDs.contains($0)
        } ?? true
        let isEligible = route.consumedAt == nil
            && isWithinValidityWindow
            && hasActiveOccurrence

        try deleteClaimedFile(at: claimedFileURL)
        return isEligible ? route : nil
    }

    func claimIfEligible(
        now: Date,
        activeOccurrenceIDs: Set<String>
    ) async throws -> PendingAppRoute? {
        guard let claimedFileURL = try claimRouteFileIfPresent() else {
            return nil
        }
        let route = try readClaimedRoute(at: claimedFileURL)
        guard route.destination == .releaseProcessing else {
            if route.consumedAt == nil {
                try restoreClaimedFile(at: claimedFileURL)
            } else {
                try deleteClaimedFile(at: claimedFileURL)
            }
            return nil
        }

        switch route.state {
        case .processing, .terminal:
            try restoreClaimedFile(at: claimedFileURL)
            return route
        case .pending:
            let age = now.timeIntervalSince(route.createdAt)
            let hasActiveOccurrence = route.occurrenceID.map {
                activeOccurrenceIDs.contains($0)
            } ?? false
            guard route.consumedAt == nil,
                  age >= 0,
                  age < Self.validityDuration,
                  hasActiveOccurrence else {
                try deleteClaimedFile(at: claimedFileURL)
                return nil
            }

            let processing = try route.claiming(at: now)
            try persist(processing, replacingClaimedFileAt: claimedFileURL)
            return processing
        }
    }

    func recordTerminal(
        routeID: UUID,
        outcome: PendingAppRouteTerminalOutcome,
        retryAfter: Date?,
        at date: Date
    ) async throws -> PendingAppRoute {
        let (route, claimedFileURL) = try claimRequiredRoute(routeID: routeID)
        if route.state == .terminal,
           route.terminalOutcome == outcome,
           route.retryAfter == retryAfter {
            try restoreClaimedFile(at: claimedFileURL)
            return route
        }
        do {
            let terminal = try route.recordingTerminal(
                outcome: outcome,
                retryAfter: retryAfter,
                at: date
            )
            try persist(terminal, replacingClaimedFileAt: claimedFileURL)
            return terminal
        } catch {
            if FileManager.default.fileExists(atPath: claimedFileURL.path) {
                try? restoreClaimedFile(at: claimedFileURL)
            }
            throw error
        }
    }

    func markPresented(routeID: UUID, at date: Date) async throws -> PendingAppRoute {
        let (route, claimedFileURL) = try claimRequiredRoute(routeID: routeID)
        if route.presentedAt != nil {
            try restoreClaimedFile(at: claimedFileURL)
            return route
        }
        do {
            let presented = try route.markingPresented(at: date)
            try persist(presented, replacingClaimedFileAt: claimedFileURL)
            return presented
        } catch {
            if FileManager.default.fileExists(atPath: claimedFileURL.path) {
                try? restoreClaimedFile(at: claimedFileURL)
            }
            throw error
        }
    }

    func acknowledgeAndDelete(routeID: UUID, at date: Date) async throws {
        let (route, claimedFileURL) = try claimRequiredRoute(routeID: routeID)
        do {
            _ = try route.acknowledging(at: date)
            try deleteClaimedFile(at: claimedFileURL)
        } catch {
            if FileManager.default.fileExists(atPath: claimedFileURL.path) {
                try? restoreClaimedFile(at: claimedFileURL)
            }
            throw error
        }
    }

    func retry(routeID: UUID, at date: Date) async throws -> PendingAppRoute? {
        let (route, claimedFileURL) = try claimRequiredRoute(routeID: routeID)
        guard route.state == .terminal,
              route.terminalOutcome == .retryable else {
            try restoreClaimedFile(at: claimedFileURL)
            return nil
        }
        if let retryAfter = route.retryAfter, date < retryAfter {
            try restoreClaimedFile(at: claimedFileURL)
            return nil
        }
        do {
            let processing = try route.retrying(at: date)
            try persist(processing, replacingClaimedFileAt: claimedFileURL)
            return processing
        } catch {
            if FileManager.default.fileExists(atPath: claimedFileURL.path) {
                try? restoreClaimedFile(at: claimedFileURL)
            }
            throw error
        }
    }

    private var fileName: String {
        SharedIdentifiers.pendingAppRouteFileName
    }

    private var fileURL: URL {
        containerURL.appendingPathComponent(fileName)
    }

    private func claimRouteFileIfPresent() throws -> URL? {
        let claimedFileURL = containerURL.appendingPathComponent(
            "\(fileName).claim-\(UUID().uuidString)"
        )
        do {
            try FileManager.default.moveItem(at: fileURL, to: claimedFileURL)
            return claimedFileURL
        } catch let error as CocoaError
            where error.code == .fileNoSuchFile
                || error.code == .fileReadNoSuchFile {
            return nil
        } catch {
            throw SharedSnapshotRepositoryError.deletionFailed(fileName: fileName)
        }
    }

    private func claimRequiredRoute(
        routeID: UUID
    ) throws -> (PendingAppRoute, URL) {
        guard let claimedFileURL = try claimRouteFileIfPresent() else {
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        let route = try readClaimedRoute(at: claimedFileURL)
        guard route.routeID == routeID,
              route.destination == .releaseProcessing else {
            try restoreClaimedFile(at: claimedFileURL)
            throw LiveActivityCoinModelError.invalidPendingAppRoute
        }
        return (route, claimedFileURL)
    }

    private func readClaimedRoute(at claimedFileURL: URL) throws -> PendingAppRoute {
        let data: Data
        do {
            data = try Data(contentsOf: claimedFileURL)
        } catch {
            try? FileManager.default.removeItem(at: claimedFileURL)
            throw SharedSnapshotRepositoryError.readFailed(fileName: fileName)
        }
        do {
            return try makeDecoder().decode(PendingAppRoute.self, from: data)
        } catch {
            try? FileManager.default.removeItem(at: claimedFileURL)
            throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName)
        }
    }

    private func persist(
        _ route: PendingAppRoute,
        replacingClaimedFileAt claimedFileURL: URL
    ) throws {
        let data: Data
        do {
            data = try makeEncoder().encode(route)
        } catch {
            try? restoreClaimedFile(at: claimedFileURL)
            throw SharedSnapshotRepositoryError.encodingFailed(fileName: fileName)
        }

        do {
            try fileWriter.write(data, to: fileURL)
        } catch {
            try? restoreClaimedFile(at: claimedFileURL)
            throw SharedSnapshotRepositoryError.atomicWriteFailed(fileName: fileName)
        }
        try deleteClaimedFile(at: claimedFileURL)
    }

    private func restoreClaimedFile(at claimedFileURL: URL) throws {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: claimedFileURL)
            } else {
                try FileManager.default.moveItem(at: claimedFileURL, to: fileURL)
            }
        } catch {
            throw SharedSnapshotRepositoryError.deletionFailed(fileName: fileName)
        }
    }

    private func deleteClaimedFile(at claimedFileURL: URL) throws {
        do {
            try FileManager.default.removeItem(at: claimedFileURL)
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
