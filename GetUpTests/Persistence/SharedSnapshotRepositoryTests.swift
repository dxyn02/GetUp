import Foundation
import Testing
@testable import GetUp

@Suite("Shared snapshot repository", .serialized)
struct SharedSnapshotRepositoryTests {
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
        #expect(try await repository.loadLocationCondition() == condition)
    }

    @Test("Snapshot files use complete-until-first-unlock protection")
    func snapshotFilesAreProtected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)

        try await repository.saveRule(TestFixtures.makeRule())
        try await repository.saveLocationCondition(TestFixtures.makeLocationCondition())

        for fileName in [
            SharedIdentifiers.restrictionRuleFileName,
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
    }

    @Test("Missing snapshot files load as nil")
    func missingFilesReturnNil() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)

        #expect(try await repository.loadRule() == nil)
        #expect(try await repository.loadLocationCondition() == nil)
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
            _ = try await repository.loadLocationCondition()
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
            _ = try await repository.loadLocationCondition()
        }
    }

    @Test("A location snapshot for another rule revision is rejected")
    func mismatchedRuleRevisionIsRejected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await repository.saveRule(TestFixtures.makeRule(revision: 1))
        try await repository.saveLocationCondition(
            TestFixtures.makeLocationCondition(ruleRevision: 1)
        )
        try replaceJSONInteger(
            key: "ruleRevision",
            value: 2,
            in: directory.appendingPathComponent(
                SharedIdentifiers.locationConditionFileName
            )
        )

        await expectRepositoryError(
            .revisionMismatch(expected: 1, actual: 2)
        ) {
            _ = try await repository.loadLocationCondition()
        }
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
            try await workingRepository.loadLocationCondition()
                == originalCondition
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

private struct FailingSnapshotFileWriter: SnapshotFileWriting {
    func write(_ data: Data, to destinationURL: URL) throws {
        throw Failure.expected
    }

    private enum Failure: Error {
        case expected
    }
}
