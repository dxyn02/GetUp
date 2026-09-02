import Foundation
import Testing
@testable import GetUp

@Suite("Live Activity and coin shared snapshots", .serialized)
struct LiveActivityCoinSnapshotRepositoryTests {
    @Test("New snapshot files round-trip independently")
    func snapshotsRoundTrip() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        let activeRestriction = try makeActiveRestrictionSnapshot()
        let balance = makeBalanceSnapshot()
        let exceptions = [try makeReleaseException()]

        try await repository.saveActiveRestrictionSnapshot(activeRestriction)
        try await repository.saveCoinBalanceSnapshot(balance)
        try await repository.saveReleaseExceptions(exceptions)

        #expect(try await repository.loadActiveRestrictionSnapshot() == activeRestriction)
        #expect(try await repository.loadCoinBalanceSnapshot() == balance)
        #expect(try await repository.loadReleaseExceptions() == exceptions)
    }

    @Test("Missing new files migrate an existing installation to safe empty state without changing 001 files")
    func missingNewFilesPreserveExistingSnapshots() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        let rule = TestFixtures.makeRule(revision: 7)
        let condition = TestFixtures.makeLocationCondition(ruleRevision: 7)

        try await repository.saveRule(rule)
        try await repository.saveLocationCondition(condition)
        let rulesData = try Data(contentsOf: directory.appendingPathComponent(
            SharedIdentifiers.restrictionRulesFileName
        ))
        let locationData = try Data(contentsOf: directory.appendingPathComponent(
            SharedIdentifiers.locationConditionFileName
        ))

        #expect(try await repository.loadActiveRestrictionSnapshot() == nil)
        #expect(try await repository.loadCoinBalanceSnapshot() == nil)
        #expect(try await repository.loadReleaseExceptions().isEmpty)
        #expect(try await repository.loadRule() == rule)
        #expect(
            try await repository.loadLocationConditionCollection()?.conditions
                == [condition]
        )
        #expect(try Data(contentsOf: directory.appendingPathComponent(
            SharedIdentifiers.restrictionRulesFileName
        )) == rulesData)
        #expect(try Data(contentsOf: directory.appendingPathComponent(
            SharedIdentifiers.locationConditionFileName
        )) == locationData)
    }

    @Test(
        "Corrupted new snapshot JSON reports its file-specific decoding error",
        arguments: SnapshotKind.allCases
    )
    func corruptedSnapshotIsRejected(kind: SnapshotKind) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await saveFixture(kind, repository: repository)
        try Data("not-json".utf8).write(
            to: directory.appendingPathComponent(kind.fileName)
        )

        await expectRepositoryError(.decodingFailed(fileName: kind.fileName)) {
            try await load(kind, repository: repository)
        }
    }

    @Test(
        "A newer schema for each new snapshot is rejected",
        arguments: SnapshotKind.allCases
    )
    func unsupportedSnapshotSchemaIsRejected(kind: SnapshotKind) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await saveFixture(kind, repository: repository)
        try replaceJSONInteger(
            key: "schemaVersion",
            value: kind.supportedSchemaVersion + 1,
            in: directory.appendingPathComponent(kind.fileName)
        )

        await expectRepositoryError(
            .unsupportedSchema(
                fileName: kind.fileName,
                found: kind.supportedSchemaVersion + 1,
                supported: kind.supportedSchemaVersion
            )
        ) {
            try await load(kind, repository: repository)
        }
    }

    @Test(
        "Atomic write failure preserves each previous snapshot",
        arguments: SnapshotKind.allCases
    )
    func atomicWriteFailurePreservesPreviousSnapshot(kind: SnapshotKind) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = SharedSnapshotRepository(containerURL: directory)
        try await saveFixture(kind, repository: repository)
        let originalData = try Data(contentsOf: directory.appendingPathComponent(kind.fileName))
        let failingRepository = SharedSnapshotRepository(
            containerURL: directory,
            fileWriter: LiveActivityCoinFailingFileWriter()
        )

        await expectRepositoryError(.atomicWriteFailed(fileName: kind.fileName)) {
            try await saveReplacement(kind, repository: failingRepository)
        }

        #expect(
            try Data(contentsOf: directory.appendingPathComponent(kind.fileName))
                == originalData
        )
    }

    @Test("New snapshot files use the existing protected atomic writer")
    func snapshotFilesUseProtectedAtomicWriter() async throws {
        #expect(
            AtomicSnapshotFileWriter.writingOptions.contains(.atomic)
        )
        #expect(
            AtomicSnapshotFileWriter.writingOptions.contains(
                .completeFileProtectionUntilFirstUserAuthentication
            )
        )

        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let writer = RecordingSnapshotFileWriter()
        let repository = SharedSnapshotRepository(
            containerURL: directory,
            fileWriter: writer
        )

        try await repository.saveActiveRestrictionSnapshot(makeActiveRestrictionSnapshot())
        try await repository.saveCoinBalanceSnapshot(makeBalanceSnapshot())
        try await repository.saveReleaseExceptions([try makeReleaseException()])

        #expect(writer.destinations.map(\.lastPathComponent).sorted() == [
            SharedIdentifiers.activeRestrictionSnapshotFileName,
            SharedIdentifiers.coinBalanceSnapshotFileName,
            SharedIdentifiers.releaseExceptionsFileName,
        ].sorted())
    }

    private func saveFixture(
        _ kind: SnapshotKind,
        repository: SharedSnapshotRepository
    ) async throws {
        switch kind {
        case .activeRestriction:
            try await repository.saveActiveRestrictionSnapshot(makeActiveRestrictionSnapshot())
        case .coinBalance:
            try await repository.saveCoinBalanceSnapshot(makeBalanceSnapshot())
        case .releaseExceptions:
            try await repository.saveReleaseExceptions([try makeReleaseException()])
        }
    }

    private func saveReplacement(
        _ kind: SnapshotKind,
        repository: SharedSnapshotRepository
    ) async throws {
        switch kind {
        case .activeRestriction:
            try await repository.saveActiveRestrictionSnapshot(
                try makeActiveRestrictionSnapshot(revision: 2)
            )
        case .coinBalance:
            try await repository.saveCoinBalanceSnapshot(
                makeBalanceSnapshot(purchasedAvailable: 4)
            )
        case .releaseExceptions:
            try await repository.saveReleaseExceptions([])
        }
    }

    private func load(
        _ kind: SnapshotKind,
        repository: SharedSnapshotRepository
    ) async throws {
        switch kind {
        case .activeRestriction:
            _ = try await repository.loadActiveRestrictionSnapshot()
        case .coinBalance:
            _ = try await repository.loadCoinBalanceSnapshot()
        case .releaseExceptions:
            _ = try await repository.loadReleaseExceptions()
        }
    }
}

enum SnapshotKind: CaseIterable, CustomTestStringConvertible, Sendable {
    case activeRestriction
    case coinBalance
    case releaseExceptions

    var testDescription: String { fileName }

    var fileName: String {
        switch self {
        case .activeRestriction:
            SharedIdentifiers.activeRestrictionSnapshotFileName
        case .coinBalance:
            SharedIdentifiers.coinBalanceSnapshotFileName
        case .releaseExceptions:
            SharedIdentifiers.releaseExceptionsFileName
        }
    }

    var supportedSchemaVersion: Int {
        switch self {
        case .activeRestriction:
            ActiveRestrictionSnapshot.currentSchemaVersion
        case .coinBalance:
            CoinBalanceSnapshot.currentSchemaVersion
        case .releaseExceptions:
            ReleaseExceptionCollectionSnapshot.currentSchemaVersion
        }
    }
}

private final class RecordingSnapshotFileWriter: SnapshotFileWriting, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedDestinations: [URL] = []

    var destinations: [URL] {
        lock.withLock { recordedDestinations }
    }

    func write(_ data: Data, to destinationURL: URL) throws {
        lock.withLock {
            recordedDestinations.append(destinationURL)
        }
        try data.write(to: destinationURL, options: AtomicSnapshotFileWriter.writingOptions)
    }
}

private struct LiveActivityCoinFailingFileWriter: SnapshotFileWriting {
    func write(_ data: Data, to destinationURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private extension LiveActivityCoinSnapshotRepositoryTests {
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000301")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000302")!
    static let observedAt = Date(timeIntervalSince1970: 1_788_192_000)
    static let endAt = observedAt.addingTimeInterval(3_600)

    func makeActiveRestrictionSnapshot(
        revision: Int = 1
    ) throws -> ActiveRestrictionSnapshot {
        try ActiveRestrictionSnapshot(
            revision: revision,
            occurrences: [
                try RestrictionOccurrence(
                    ruleID: Self.ruleID,
                    ruleRevision: 3,
                    startAt: Self.observedAt,
                    endAt: Self.endAt,
                    activatedAt: Self.observedAt
                ),
            ],
            observedAt: Self.observedAt
        )
    }

    func makeBalanceSnapshot(
        purchasedAvailable: Int = 3
    ) -> CoinBalanceSnapshot {
        CoinBalanceSnapshot(
            purchasedAvailable: purchasedAvailable,
            currentMonthID: "2026-09",
            freeAvailable: 2,
            syncState: .current,
            syncedAt: Self.observedAt,
            ledgerEpochID: UUID(uuidString: "00000000-0000-4000-8000-000000000303")!,
            hadConfirmedLedger: true
        )
    }

    func makeReleaseException() throws -> ReleaseException {
        try ReleaseException(
            commandID: Self.commandID,
            occurrenceID: "occurrence-1",
            ruleID: Self.ruleID,
            ruleRevision: 3,
            effectiveAt: Self.observedAt,
            expiresAt: Self.endAt
        )
    }

    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }

    func replaceJSONInteger(
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

    func expectRepositoryError<T>(
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
