import Foundation
import Testing
@testable import GetUp

@Suite("Release exception repository", .serialized)
struct ReleaseExceptionRepositoryTests {
    @Test("Concurrent command inserts retain every occurrence across repository instances")
    func concurrentCommandInserts() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let entries = try (0..<100).map { index in
            try ReleaseException(commandID: UUID(), occurrenceID: "occurrence-\(index)", ruleID: UUID(),
                ruleRevision: 4, effectiveAt: Self.now, expiresAt: Self.occurrence.endAt)
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for entry in entries {
                group.addTask {
                    let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
                    _ = try await repository.insertReleaseException(entry)
                }
            }
            try await group.waitForAll()
        }
        let stored = try await SharedSnapshotRepository(containerURL: directory).loadReleaseExceptions()
        #expect(Set(stored) == Set(entries))
    }

    @Test("Repeated insertion is idempotent even if the writer would fail")
    func idempotentCommandInsert() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let entry = try makeException()
        _ = try await SharedSnapshotRepository(containerURL: directory).insertReleaseException(entry)
        let failing = AppGroupReleaseExceptionRepository(containerURL: directory, fileWriter: FailingReleaseExceptionFileWriter())
        #expect(try await failing.insertReleaseException(entry) == [entry])
    }

    @Test("Command or occurrence conflicts preserve the original entry", arguments: [true, false])
    func conflictingCommandInsert(sameCommand: Bool) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        let original = try makeException()
        _ = try await repository.insertReleaseException(original)
        let conflicting = try ReleaseException(
            commandID: sameCommand ? original.commandID : UUID(),
            occurrenceID: sameCommand ? "other-occurrence" : original.occurrenceID,
            ruleID: original.ruleID, ruleRevision: 4, effectiveAt: Self.now, expiresAt: original.expiresAt)
        await #expect(throws: ReleaseExceptionRepositoryError.conflict) {
            try await repository.insertReleaseException(conflicting)
        }
        #expect(try await repository.loadReleaseExceptions() == [original])
    }

    @Test("Removing one owner preserves concurrent success and late removal preserves the new owner")
    func ownerScopedRemoval() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        let shared = SharedSnapshotRepository(containerURL: directory)
        let original = try makeException()
        let other = try ReleaseException(commandID: UUID(), occurrenceID: "other", ruleID: UUID(),
            ruleRevision: 4, effectiveAt: Self.now, expiresAt: original.expiresAt)
        _ = try await repository.insertReleaseException(original)
        async let remove = repository.removeReleaseException(commandID: original.commandID, occurrenceID: original.occurrenceID)
        async let insert = shared.insertReleaseException(other)
        _ = try await (remove, insert)
        #expect(try await repository.loadReleaseExceptions() == [other])
        let replacement = try ReleaseException(commandID: UUID(), occurrenceID: original.occurrenceID,
            ruleID: original.ruleID, ruleRevision: 4, effectiveAt: Self.now, expiresAt: original.expiresAt)
        _ = try await repository.insertReleaseException(replacement)
        _ = try await shared.removeReleaseException(commandID: original.commandID, occurrenceID: original.occurrenceID)
        #expect(try await Set(repository.loadReleaseExceptions()) == Set([other, replacement]))
    }

    @Test("Failed command mutations retain the previous collection")
    func commandMutationFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        let original = try makeException()
        _ = try await repository.insertReleaseException(original)
        let failing = AppGroupReleaseExceptionRepository(containerURL: directory, fileWriter: FailingReleaseExceptionFileWriter())
        await #expect(throws: ReleaseExceptionRepositoryError.writeFailed) {
            try await failing.removeReleaseException(commandID: original.commandID, occurrenceID: original.occurrenceID)
        }
        #expect(try await failing.removeReleaseException(commandID: original.commandID, occurrenceID: "wrong") == [original])
        let another = try ReleaseException(commandID: UUID(), occurrenceID: "another", ruleID: UUID(),
            ruleRevision: 4, effectiveAt: Self.now, expiresAt: original.expiresAt)
        await #expect(throws: ReleaseExceptionRepositoryError.writeFailed) {
            try await failing.insertReleaseException(another)
        }
        #expect(try await repository.loadReleaseExceptions() == [original])
    }

    @Test("Subsecond request replay compares the existing on-disk timestamp representation")
    func subsecondReplay() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let entry = try ReleaseException(commandID: UUID(), occurrenceID: "fractional", ruleID: UUID(),
            ruleRevision: 4, effectiveAt: Self.now.addingTimeInterval(0.123), expiresAt: Self.occurrence.endAt)
        _ = try await AppGroupReleaseExceptionRepository(containerURL: directory).insertReleaseException(entry)
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory, fileWriter: FailingReleaseExceptionFileWriter())
        let result = try await repository.insertReleaseException(entry)
        #expect(result.count == 1)
        #expect(result.first?.commandID == entry.commandID)
    }

    @Test("Command mutations do not replace unreadable storage")
    func corruptCommandMutation() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appendingPathComponent(SharedIdentifiers.releaseExceptionsFileName)
        let original = Data("not-json".utf8)
        try original.write(to: url)
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        let entry = try makeException()
        await #expect(throws: ReleaseExceptionRepositoryError.readFailed) {
            try await repository.insertReleaseException(entry)
        }
        await #expect(throws: ReleaseExceptionRepositoryError.readFailed) {
            try await repository.removeReleaseException(commandID: entry.commandID, occurrenceID: entry.occurrenceID)
        }
        #expect(try Data(contentsOf: url) == original)
    }

    @Test("Missing storage is empty and does not create an exception file")
    func missingStorage() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        #expect(try await repository.loadReleaseExceptions().isEmpty)
        #expect(try await repository.loadApplicableReleaseExceptions(
            at: Self.now, activeOccurrenceIDs: [], currentRuleRevisions: [:]
        ).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(
            SharedIdentifiers.releaseExceptionsFileName
        ).path))
    }

    @Test("Future-effective and temporarily inactive exceptions are retained but not applied")
    func retainedWithoutApplying() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        let exception = try makeException()
        try await repository.saveReleaseExceptions([exception])
        for (date, ids) in [(exception.effectiveAt.addingTimeInterval(-1), Set([Self.occurrence.id])), (Self.now, Set<String>())] {
            #expect(try await repository.loadApplicableReleaseExceptions(
                at: date, activeOccurrenceIDs: ids, currentRuleRevisions: [Self.ruleID: 4]
            ).isEmpty)
            #expect(try await repository.loadReleaseExceptions() == [exception])
        }
        #expect(try await repository.loadApplicableReleaseExceptions(
            at: exception.effectiveAt, activeOccurrenceIDs: [Self.occurrence.id],
            currentRuleRevisions: [Self.ruleID: 4]
        ) == [exception])
    }

    @Test("Cleanup write failure propagates and preserves the original bytes")
    func cleanupFailure() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        let exception = try makeException()
        try await repository.saveReleaseExceptions([exception])
        let failing = AppGroupReleaseExceptionRepository(containerURL: directory, fileWriter: FailingReleaseExceptionFileWriter())
        await #expect(throws: ReleaseExceptionRepositoryError.writeFailed) {
            try await failing.loadApplicableReleaseExceptions(
                at: Self.occurrence.endAt, activeOccurrenceIDs: [], currentRuleRevisions: [Self.ruleID: 4]
            )
        }
        #expect(try await repository.loadReleaseExceptions() == [exception])
        // A valid read does not unnecessarily rewrite storage.
        #expect(try await failing.loadApplicableReleaseExceptions(
            at: Self.now, activeOccurrenceIDs: [Self.occurrence.id], currentRuleRevisions: [Self.ruleID: 4]
        ) == [exception])
    }

    @Test("Malformed and unsupported snapshots fail closed without replacing their bytes", arguments: ["not-json", "{\"schemaVersion\":99,\"exceptions\":[]}"])
    func corruptStorage(payload: String) async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let url = directory.appendingPathComponent(SharedIdentifiers.releaseExceptionsFileName)
        let data = Data(payload.utf8)
        try data.write(to: url)
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        await #expect(throws: ReleaseExceptionRepositoryError.readFailed) {
            try await repository.loadApplicableReleaseExceptions(
                at: Self.now, activeOccurrenceIDs: [], currentRuleRevisions: [:]
            )
        }
        #expect(try Data(contentsOf: url) == data)
    }

    @Test("Invalid duplicate collection cannot replace a valid snapshot")
    func duplicateCollection() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        let exception = try makeException()
        try await repository.saveReleaseExceptions([exception])
        await #expect(throws: ReleaseExceptionRepositoryError.writeFailed) {
            try await repository.saveReleaseExceptions([exception, exception])
        }
        #expect(try await repository.loadReleaseExceptions() == [exception])
    }

    @Test("The shared snapshot facade and dedicated repository use the same schema and file")
    func sharedFacadeCompatibility() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let shared = SharedSnapshotRepository(containerURL: directory)
        let dedicated = AppGroupReleaseExceptionRepository(containerURL: directory)
        let exception = try makeException()
        try await shared.saveReleaseExceptions([exception])
        #expect(try await dedicated.loadReleaseExceptions() == [exception])
        _ = try await dedicated.loadApplicableReleaseExceptions(
            at: Self.now, activeOccurrenceIDs: [Self.occurrence.id], currentRuleRevisions: [:]
        )
        #expect(try await shared.loadReleaseExceptions().isEmpty)
    }

    @Test("Cleanup and another facade's save cannot overwrite each other's in-flight transaction")
    func concurrentCleanupAndSave() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let expired = try makeException()
        let fresh = try ReleaseException(commandID: UUID(), occurrenceID: "fresh-occurrence",
            ruleID: Self.ruleID, ruleRevision: 4, effectiveAt: Self.occurrence.endAt,
            expiresAt: Self.occurrence.endAt.addingTimeInterval(3600))
        for _ in 0..<50 {
            let shared = SharedSnapshotRepository(containerURL: directory)
            let cleaner = AppGroupReleaseExceptionRepository(containerURL: directory)
            try await shared.saveReleaseExceptions([expired])
            async let clean = cleaner.loadApplicableReleaseExceptions(
                at: Self.occurrence.endAt, activeOccurrenceIDs: [fresh.occurrenceID],
                currentRuleRevisions: [Self.ruleID: 4]
            )
            async let save: Void = shared.saveReleaseExceptions([fresh])
            _ = try await (clean, save)
            #expect(try await cleaner.loadReleaseExceptions() == [fresh])
        }
    }

    @Test("An active exception survives fresh repository instances after relaunch and reboot")
    func activeExceptionSurvivesRelaunchAndReboot() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let exception = try makeException()

        let initialProcess = AppGroupReleaseExceptionRepository(containerURL: directory)
        try await initialProcess.saveReleaseExceptions([exception])

        let relaunchedProcess = AppGroupReleaseExceptionRepository(containerURL: directory)
        #expect(try await relaunchedProcess.loadReleaseExceptions() == [exception])

        let rebootedProcess = AppGroupReleaseExceptionRepository(containerURL: directory)
        #expect(try await rebootedProcess.loadApplicableReleaseExceptions(
            at: Self.now,
            activeOccurrenceIDs: [Self.occurrence.id],
            currentRuleRevisions: [Self.ruleID: Self.occurrence.ruleRevision]
        ) == [exception])
    }

    @Test("An exception remains applicable immediately before its occurrence ends")
    func activeUntilExpirationBoundary() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        let exception = try makeException()
        try await repository.saveReleaseExceptions([exception])

        let applicable = try await repository.loadApplicableReleaseExceptions(
            at: Self.occurrence.endAt.addingTimeInterval(-0.001),
            activeOccurrenceIDs: [Self.occurrence.id],
            currentRuleRevisions: [Self.ruleID: Self.occurrence.ruleRevision]
        )

        #expect(applicable == [exception])
    }

    @Test("An exception expires at endsAt and is removed from persisted storage")
    func expirationBoundaryIsCleaned() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        try await repository.saveReleaseExceptions([try makeException()])

        #expect(try await repository.loadApplicableReleaseExceptions(
            at: Self.occurrence.endAt,
            activeOccurrenceIDs: [Self.occurrence.id],
            currentRuleRevisions: [Self.ruleID: Self.occurrence.ruleRevision]
        ).isEmpty)

        let nextProcess = AppGroupReleaseExceptionRepository(containerURL: directory)
        #expect(try await nextProcess.loadReleaseExceptions().isEmpty)
    }

    @Test("A rule revision mismatch is ignored and removed from persisted storage")
    func revisionMismatchIsCleaned() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        try await repository.saveReleaseExceptions([try makeException()])

        #expect(try await repository.loadApplicableReleaseExceptions(
            at: Self.now,
            activeOccurrenceIDs: [Self.occurrence.id],
            currentRuleRevisions: [Self.ruleID: Self.occurrence.ruleRevision + 1]
        ).isEmpty)
        #expect(try await repository.loadReleaseExceptions().isEmpty)
    }

    @Test("An exception for one occurrence never applies to the next occurrence")
    func nextOccurrenceIsNotReleased() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        try await repository.saveReleaseExceptions([try makeException()])

        let nextOccurrence = try RestrictionOccurrence(
            ruleID: Self.ruleID,
            ruleRevision: Self.occurrence.ruleRevision,
            startAt: Self.occurrence.endAt.addingTimeInterval(3_600),
            endAt: Self.occurrence.endAt.addingTimeInterval(7_200),
            activatedAt: Self.occurrence.endAt.addingTimeInterval(3_600)
        )

        #expect(try await repository.loadApplicableReleaseExceptions(
            at: nextOccurrence.startAt,
            activeOccurrenceIDs: [nextOccurrence.id],
            currentRuleRevisions: [Self.ruleID: nextOccurrence.ruleRevision]
        ).isEmpty)
    }

    @Test("An atomic write failure preserves the previous exception collection")
    func failedAtomicWritePreservesPreviousCollection() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let original = try makeException()
        let repository = AppGroupReleaseExceptionRepository(containerURL: directory)
        try await repository.saveReleaseExceptions([original])
        let failingRepository = AppGroupReleaseExceptionRepository(
            containerURL: directory,
            fileWriter: FailingReleaseExceptionFileWriter()
        )

        await #expect(throws: ReleaseExceptionRepositoryError.writeFailed) {
            try await failingRepository.saveReleaseExceptions([])
        }

        let nextProcess = AppGroupReleaseExceptionRepository(containerURL: directory)
        #expect(try await nextProcess.loadReleaseExceptions() == [original])
    }
}

private extension ReleaseExceptionRepositoryTests {
    static let ruleID = UUID(uuidString: "00000000-0000-4000-8000-000000000501")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000502")!
    static let now = Date(timeIntervalSince1970: 1_788_192_000)
    static let occurrence = try! RestrictionOccurrence(
        ruleID: ruleID,
        ruleRevision: 4,
        startAt: now.addingTimeInterval(-600),
        endAt: now.addingTimeInterval(3_600),
        activatedAt: now.addingTimeInterval(-590)
    )

    func makeException() throws -> ReleaseException {
        try ReleaseException(
            commandID: Self.commandID,
            occurrenceID: Self.occurrence.id,
            ruleID: Self.ruleID,
            ruleRevision: Self.occurrence.ruleRevision,
            effectiveAt: Self.now.addingTimeInterval(-1),
            expiresAt: Self.occurrence.endAt
        )
    }

    func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString,
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func removeTemporaryDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}

private struct FailingReleaseExceptionFileWriter: SnapshotFileWriting {
    func write(_ data: Data, to destinationURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}
