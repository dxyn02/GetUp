@preconcurrency import FamilyControls
import Foundation
import Testing
@testable import GetUp

@Suite("Shared snapshot repository", .serialized)
struct SharedSnapshotRepositoryTests {
    @Test("Rule and saved-place collections round-trip through their contract files")
    func collectionsRoundTrip() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        let rule = TestFixtures.makeRule(revision: 3)
        let place = SavedPlaceSnapshot(
            id: rule.savedPlaceID,
            name: "집",
            coordinate: ReferenceLocation(latitude: 37.0, longitude: 127.0),
            createdAt: TestFixtures.now,
            updatedAt: TestFixtures.now
        )
        let rules = RestrictionRuleCollectionSnapshot(revision: 5, rules: [rule])
        let places = SavedPlaceCollectionSnapshot(revision: 2, places: [place])

        try await repository.saveSavedPlaceCollection(places)
        try await repository.saveRuleCollection(rules)

        #expect(try await repository.loadRuleCollection() == rules)
        #expect(try await repository.loadSavedPlaceCollection() == places)
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(
                SharedIdentifiers.restrictionRulesFileName
            ).path
        ))
        #expect(FileManager.default.fileExists(
            atPath: directory.appendingPathComponent(
                SharedIdentifiers.savedPlacesFileName
            ).path
        ))
    }

    @Test("A legacy single-rule snapshot is read as linked rule and place collections")
    func legacyRuleMigratesWithoutLosingCoordinates() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let legacy = LegacyRuleTestSnapshot(
            schemaVersion: 1,
            revision: 4,
            isEnabled: true,
            weekdays: [.monday],
            startTime: TimeOfDay(hour: 6, minute: 0),
            endTime: TimeOfDay(hour: 9, minute: 0),
            referenceLocation: ReferenceLocation(latitude: 37.0, longitude: 127.0),
            radius: .meters1000,
            activitySelection: FamilyActivitySelection(),
            createdAt: TestFixtures.now,
            updatedAt: TestFixtures.now
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(
            to: directory.appendingPathComponent(
                SharedIdentifiers.legacyRestrictionRuleFileName
            )
        )
        let repository = SharedSnapshotRepository(containerURL: directory)

        let rules = try #require(try await repository.loadRuleCollection())
        let places = try #require(try await repository.loadSavedPlaceCollection())
        let rule = try #require(rules.rules.first)
        let place = try #require(places.places.first)

        #expect(rules.revision == 4)
        #expect(rule.revision == 4)
        #expect(rule.savedPlaceID == place.id)
        #expect(place.name == "기존 장소")
        #expect(place.coordinate == legacy.referenceLocation)
    }

    @Test("Rule and location snapshots round-trip through separate files")
    func snapshotsRoundTrip() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        let rule = TestFixtures.makeRule()
        let condition = TestFixtures.makeLocationCondition()

        try await repository.saveRule(rule)
        try await repository.saveLocationCondition(condition)

        #expect(try await repository.loadRule() == rule)
        #expect(
            try await repository.loadLocationConditionCollection()?.conditions
                == [condition]
        )
    }

    @Test("Location conditions are stored independently by rule ID")
    func locationConditionCollectionPreservesEveryRule() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        let first = TestFixtures.makeLocationCondition()
        let second = TestFixtures.makeLocationCondition(
            ruleID: UUID(uuidString: "00000000-0000-4000-8000-000000000201")!,
            ruleRevision: 4,
            state: .outside
        )

        try await repository.saveLocationCondition(first)
        try await repository.saveLocationCondition(second)

        let collection = try #require(
            try await repository.loadLocationConditionCollection()
        )
        #expect(Set(collection.conditions.map(\.ruleID)) == [first.ruleID, second.ruleID])
        #expect(collection.conditions.count == 2)
    }

    @Test("A legacy location snapshot migrates to an empty safe collection")
    func legacyLocationSnapshotDoesNotGuessRuleIdentity() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let legacy = LegacyLocationConditionTestSnapshot(
            schemaVersion: 1,
            ruleRevision: 1,
            state: .inside,
            observedAt: TestFixtures.now,
            distanceMeters: 100,
            horizontalAccuracyMeters: 10,
            source: .freshFix
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(legacy).write(
            to: directory.appendingPathComponent(
                SharedIdentifiers.locationConditionFileName
            )
        )
        let repository = SharedSnapshotRepository(containerURL: directory)

        let collection = try #require(
            try await repository.loadLocationConditionCollection()
        )

        #expect(collection.schemaVersion == 2)
        #expect(collection.conditions.isEmpty)
    }

    @Test("Snapshot files use complete-until-first-unlock protection")
    func snapshotFilesAreProtected() async throws {
        #expect(
            AtomicSnapshotFileWriter.writingOptions.contains(
                .completeFileProtectionUntilFirstUserAuthentication
            )
        )

        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)

        try await repository.saveRule(TestFixtures.makeRule())
        try await repository.saveSavedPlaceCollection(
            SavedPlaceCollectionSnapshot(revision: 1, places: [])
        )
        try await repository.saveLocationCondition(TestFixtures.makeLocationCondition())

        #if !targetEnvironment(simulator)
        for fileName in [
            SharedIdentifiers.restrictionRulesFileName,
            SharedIdentifiers.savedPlacesFileName,
            SharedIdentifiers.locationConditionFileName,
        ] {
            let attributes = try FileManager.default.attributesOfItem(
                atPath: directory.appendingPathComponent(fileName).path
            )
            #expect(
                attributes[.protectionKey] as? FileProtectionType
                    == .completeUntilFirstUserAuthentication
            )
        }
        #endif
    }

    @Test("Missing snapshot files load as nil")
    func missingFilesReturnNil() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)

        #expect(try await repository.loadRule() == nil)
        #expect(try await repository.loadLocationConditionCollection() == nil)
    }

    @Test("Corrupted rule JSON reports a decoding failure")
    func corruptedRuleReportsDecodingFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await repository.saveRule(TestFixtures.makeRule())
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent(
                SharedIdentifiers.restrictionRuleFileName
            )
        )
        await expectRepositoryError(
            .decodingFailed(fileName: SharedIdentifiers.restrictionRuleFileName)
        ) {
            _ = try await repository.loadRule()
        }
    }

    @Test("Corrupted location JSON reports a decoding failure")
    func corruptedLocationReportsDecodingFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await repository.saveRule(TestFixtures.makeRule())
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent(
                SharedIdentifiers.locationConditionFileName
            )
        )
        await expectRepositoryError(
            .decodingFailed(fileName: SharedIdentifiers.locationConditionFileName)
        ) {
            _ = try await repository.loadLocationConditionCollection()
        }
    }

    @Test("A rule from a newer schema is rejected")
    func unsupportedRuleSchemaIsRejected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await repository.saveRule(TestFixtures.makeRule())
        try replaceJSONInteger(
            key: "schemaVersion",
            value: RestrictionRuleSnapshot.currentSchemaVersion + 1,
            in: directory.appendingPathComponent(
                SharedIdentifiers.restrictionRuleFileName
            )
        )

        await expectRepositoryError(
            .unsupportedSchema(
                fileName: SharedIdentifiers.restrictionRuleFileName,
                found: RestrictionRuleSnapshot.currentSchemaVersion + 1,
                supported: RestrictionRuleSnapshot.currentSchemaVersion
            )
        ) {
            _ = try await repository.loadRule()
        }
    }

    @Test("A location snapshot from a newer schema is rejected")
    func unsupportedLocationSchemaIsRejected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await repository.saveRule(TestFixtures.makeRule())
        try await repository.saveLocationCondition(TestFixtures.makeLocationCondition())
        try replaceJSONInteger(
            key: "schemaVersion",
            value: LocationConditionSnapshot.currentSchemaVersion + 1,
            in: directory.appendingPathComponent(
                SharedIdentifiers.locationConditionFileName
            )
        )

        await expectRepositoryError(
            .unsupportedSchema(
                fileName: SharedIdentifiers.locationConditionFileName,
                found: LocationConditionSnapshot.currentSchemaVersion + 1,
                supported: LocationConditionSnapshot.currentSchemaVersion
            )
        ) {
            _ = try await repository.loadLocationConditionCollection()
        }
    }

    @Test("A location snapshot revision remains available for per-rule evaluation")
    func mismatchedRuleRevisionIsLoadedForSafeEvaluation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await repository.saveRule(TestFixtures.makeRule(revision: 1))
        try await repository.saveLocationCondition(
            TestFixtures.makeLocationCondition(ruleRevision: 2)
        )

        let collection = try #require(
            try await repository.loadLocationConditionCollection()
        )
        #expect(collection.conditions.first?.ruleRevision == 2)
    }

    @Test("Atomic rule write failure preserves the previous snapshot")
    func failedAtomicRuleWritePreservesPreviousSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let workingRepository = SharedSnapshotRepository(containerURL: directory)
        let originalRule = TestFixtures.makeRule(revision: 1)
        try await workingRepository.saveRule(originalRule)
        let failingRepository = SharedSnapshotRepository(
            containerURL: directory,
            fileWriter: FailingSnapshotFileWriter()
        )

        await expectRepositoryError(
            .atomicWriteFailed(fileName: SharedIdentifiers.restrictionRuleFileName)
        ) {
            try await failingRepository.saveRule(
                TestFixtures.makeRule(revision: 2)
            )
        }

        #expect(try await workingRepository.loadRule() == originalRule)
    }

    @Test("Atomic location write failure preserves the previous snapshot")
    func failedAtomicLocationWritePreservesPreviousSnapshot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let workingRepository = SharedSnapshotRepository(containerURL: directory)
        let originalCondition = TestFixtures.makeLocationCondition(
            ruleRevision: 1,
            state: .inside
        )
        try await workingRepository.saveRule(TestFixtures.makeRule(revision: 1))
        try await workingRepository.saveLocationCondition(originalCondition)
        let failingRepository = SharedSnapshotRepository(
            containerURL: directory,
            fileWriter: FailingSnapshotFileWriter()
        )

        await expectRepositoryError(
            .atomicWriteFailed(fileName: SharedIdentifiers.locationConditionFileName)
        ) {
            try await failingRepository.saveLocationCondition(
                TestFixtures.makeLocationCondition(
                    ruleRevision: 1,
                    state: .outside
                )
            )
        }

        #expect(
            try await workingRepository.loadLocationConditionCollection()?.conditions
                == [originalCondition]
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    private func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    private func replaceJSONInteger(
        key: String,
        value: Int,
        in fileURL: URL
    ) throws {
        let data = try Data(contentsOf: fileURL)
        var object = try #require(
            JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        object[key] = value
        try JSONSerialization.data(withJSONObject: object).write(to: fileURL)
    }

    private func expectRepositoryError<T>(
        _ expectedError: SharedSnapshotRepositoryError,
        operation: () async throws -> T
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected repository error: \(expectedError)")
        } catch let error as SharedSnapshotRepositoryError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}

private struct LegacyRuleTestSnapshot: Codable {
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

private struct LegacyLocationConditionTestSnapshot: Codable {
    let schemaVersion: Int
    let ruleRevision: Int
    let state: LocationConditionState
    let observedAt: Date
    let distanceMeters: Double?
    let horizontalAccuracyMeters: Double?
    let source: LocationConditionSource
}

private struct FailingSnapshotFileWriter: SnapshotFileWriting {
    func write(_ data: Data, to destinationURL: URL) throws {
        throw Failure.expected
    }

    private enum Failure: Error {
        case expected
    }
}
