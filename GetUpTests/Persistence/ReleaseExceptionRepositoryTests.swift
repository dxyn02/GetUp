import Foundation
import Testing
@testable import GetUp

@Suite("Release exception repository", .serialized)
struct ReleaseExceptionRepositoryTests {
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
