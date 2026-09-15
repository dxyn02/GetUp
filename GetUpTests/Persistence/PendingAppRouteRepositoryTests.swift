import Foundation
import Testing
@testable import GetUp

@Suite("Pending app route repository", .serialized)
struct PendingAppRouteRepositoryTests {
    @Test("A route is eligible immediately after creation and is atomically removed")
    func immediateRouteIsConsumedOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        let route = makeRoute()
        try await repository.save(route)

        let consumed = try await repository.consumeIfEligible(
            now: Self.createdAt,
            activeOccurrenceIDs: [Self.occurrenceID]
        )

        #expect(consumed == route)
        #expect(try await repository.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: routeFileURL(in: directory).path))
        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt,
            activeOccurrenceIDs: [Self.occurrenceID]
        ) == nil)
    }

    @Test("A newer successful action atomically discards an obsolete route")
    func successfulActionDiscardsObsoleteRoute() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeRoute(destination: .iCloudRecovery))

        try await repository.discard()

        #expect(try await repository.load() == nil)
        try await repository.discard()
        #expect(try await repository.load() == nil)
    }

    @Test("A route at exactly five minutes is expired and deleted")
    func exactFiveMinuteBoundaryIsExpired() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeRoute())

        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt.addingTimeInterval(300),
            activeOccurrenceIDs: [Self.occurrenceID]
        ) == nil)
        #expect(try await repository.load() == nil)
    }

    @Test("A route older than five minutes is expired and deleted")
    func routeBeyondFiveMinutesIsExpired() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeRoute())

        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt.addingTimeInterval(301),
            activeOccurrenceIDs: [Self.occurrenceID]
        ) == nil)
        #expect(try await repository.load() == nil)
    }

    @Test("A route is not eligible before its creation time and is deleted")
    func futureRouteIsRejected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeRoute())

        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt.addingTimeInterval(-1),
            activeOccurrenceIDs: [Self.occurrenceID]
        ) == nil)
        #expect(try await repository.load() == nil)
    }

    @Test("A route linked to an ended occurrence is deleted without navigation")
    func endedOccurrenceRouteIsDiscarded() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeRoute())

        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt,
            activeOccurrenceIDs: []
        ) == nil)
        #expect(try await repository.load() == nil)
    }

    @Test("A route without occurrence context remains eligible within five minutes")
    func routeWithoutOccurrenceContextIsEligible() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        let route = makeRoute(occurrenceID: nil)
        try await repository.save(route)

        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt.addingTimeInterval(299),
            activeOccurrenceIDs: []
        ) == route)
    }

    @Test("An already-consumed route is deleted and never returned")
    func consumedRouteIsDiscarded() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeRoute(consumedAt: Self.createdAt))

        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt.addingTimeInterval(1),
            activeOccurrenceIDs: [Self.occurrenceID]
        ) == nil)
        #expect(try await repository.load() == nil)
    }

    @Test("Saving the same route ID twice remains a single consumable route")
    func duplicateSaveIsIdempotent() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        let route = makeRoute()

        try await repository.save(route)
        try await repository.save(route)

        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt,
            activeOccurrenceIDs: [Self.occurrenceID]
        ) == route)
        #expect(try await repository.consumeIfEligible(
            now: Self.createdAt,
            activeOccurrenceIDs: [Self.occurrenceID]
        ) == nil)
    }

    @Test("Concurrent repository instances return the route at most once")
    func concurrentConsumersClaimRouteOnce() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let firstRepository = PendingAppRouteRepository(containerURL: directory)
        let secondRepository = PendingAppRouteRepository(containerURL: directory)
        let route = makeRoute()
        try await firstRepository.save(route)

        async let firstResult = firstRepository.consumeIfEligible(
            now: Self.createdAt,
            activeOccurrenceIDs: [Self.occurrenceID]
        )
        async let secondResult = secondRepository.consumeIfEligible(
            now: Self.createdAt,
            activeOccurrenceIDs: [Self.occurrenceID]
        )
        let (first, second) = try await (firstResult, secondResult)
        let results = [first, second]

        #expect(results.compactMap { $0 } == [route])
        #expect(try await firstRepository.load() == nil)
    }

    @Test("Corrupted route JSON reports a decoding failure and never navigates")
    func corruptedRouteIsRejected() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeRoute())
        try Data("not-json".utf8).write(to: routeFileURL(in: directory))

        await #expect(throws: SharedSnapshotRepositoryError.decodingFailed(
            fileName: SharedIdentifiers.pendingAppRouteFileName
        )) {
            _ = try await repository.consumeIfEligible(
                now: Self.createdAt,
                activeOccurrenceIDs: [Self.occurrenceID]
            )
        }
    }

    @Test("Atomic route write failure preserves the previous route")
    func atomicWriteFailurePreservesPreviousRoute() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        let original = makeRoute(destination: .coinStore)
        try await repository.save(original)
        let failingRepository = PendingAppRouteRepository(
            containerURL: directory,
            fileWriter: PendingRouteFailingFileWriter()
        )

        await #expect(throws: SharedSnapshotRepositoryError.atomicWriteFailed(
            fileName: SharedIdentifiers.pendingAppRouteFileName
        )) {
            try await failingRepository.save(makeRoute(destination: .iCloudRecovery))
        }

        #expect(try await repository.load() == original)
    }

    @Test("An eligible release route is atomically claimed and remains persisted")
    func releaseRouteIsClaimedWithoutDeletion() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeReleaseRoute())

        let claimed = try await repository.claimIfEligible(
            now: Self.createdAt.addingTimeInterval(299),
            activeOccurrenceIDs: [Self.occurrenceID]
        )

        #expect(claimed?.state == .processing)
        #expect(claimed?.commandID == Self.commandID)
        #expect(try await repository.load() == claimed)
        #expect(FileManager.default.fileExists(atPath: routeFileURL(in: directory).path))
    }

    @Test("A release route at exactly five minutes expires before claim")
    func releaseRouteAtFiveMinutesExpiresBeforeClaim() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeReleaseRoute())

        #expect(try await repository.claimIfEligible(
            now: Self.createdAt.addingTimeInterval(300),
            activeOccurrenceIDs: [Self.occurrenceID]
        ) == nil)
        #expect(try await repository.load() == nil)
    }

    @Test("A release route for an ended occurrence is deleted before claim")
    func endedReleaseOccurrenceIsDeletedBeforeClaim() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeReleaseRoute())

        #expect(try await repository.claimIfEligible(
            now: Self.createdAt.addingTimeInterval(1),
            activeOccurrenceIDs: []
        ) == nil)
        #expect(try await repository.load() == nil)
    }

    @Test("A duplicate claim returns the same processing handoff")
    func duplicateClaimReturnsExistingHandoff() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let firstRepository = PendingAppRouteRepository(containerURL: directory)
        try await firstRepository.save(makeReleaseRoute())

        let first = try await firstRepository.claimIfEligible(
            now: Self.createdAt.addingTimeInterval(1),
            activeOccurrenceIDs: [Self.occurrenceID]
        )
        let relaunchedRepository = PendingAppRouteRepository(containerURL: directory)
        let relaunched = try await relaunchedRepository.claimIfEligible(
            now: Self.createdAt.addingTimeInterval(901),
            activeOccurrenceIDs: [Self.occurrenceID]
        )

        #expect(first?.state == .processing)
        #expect(relaunched == first)
        #expect(relaunched?.commandID == Self.commandID)
        #expect(try await relaunchedRepository.load() == first)
    }

    @Test("Terminal presentation persists until an explicit acknowledgement")
    func terminalPresentationPersistsUntilAcknowledgement() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeReleaseRoute())
        _ = try await repository.claimIfEligible(
            now: Self.createdAt.addingTimeInterval(1),
            activeOccurrenceIDs: [Self.occurrenceID]
        )
        let terminal = try await repository.recordTerminal(
            routeID: Self.routeID,
            outcome: .completed,
            retryAfter: nil,
            at: Self.createdAt.addingTimeInterval(2)
        )
        let presented = try await repository.markPresented(
            routeID: Self.routeID,
            at: Self.createdAt.addingTimeInterval(3)
        )

        #expect(terminal.state == .terminal)
        #expect(presented.presentedAt == Self.createdAt.addingTimeInterval(3))
        #expect(presented.acknowledgedAt == nil)
        #expect(try await PendingAppRouteRepository(containerURL: directory).load() == presented)

        try await repository.acknowledgeAndDelete(
            routeID: Self.routeID,
            at: Self.createdAt.addingTimeInterval(4)
        )
        #expect(try await repository.load() == nil)
    }

    @Test("Retry atomically restarts only a retryable terminal handoff")
    func retryRestartsSameCommand() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeReleaseRoute())
        _ = try await repository.claimIfEligible(
            now: Self.createdAt.addingTimeInterval(1),
            activeOccurrenceIDs: [Self.occurrenceID]
        )
        let retryAfter = Self.createdAt.addingTimeInterval(20)
        _ = try await repository.recordTerminal(
            routeID: Self.routeID,
            outcome: .retryable,
            retryAfter: retryAfter,
            at: Self.createdAt.addingTimeInterval(2)
        )
        _ = try await repository.markPresented(
            routeID: Self.routeID,
            at: Self.createdAt.addingTimeInterval(3)
        )

        #expect(try await repository.retry(routeID: Self.routeID, at: retryAfter.addingTimeInterval(-1)) == nil)
        let retried = try await repository.retry(routeID: Self.routeID, at: retryAfter)

        #expect(retried?.state == .processing)
        #expect(retried?.commandID == Self.commandID)
        #expect(retried?.terminalOutcome == nil)
        #expect(retried?.presentedAt == nil)
        #expect(try await repository.load() == retried)
    }

    @Test("A failed claim write preserves the pending release route")
    func failedClaimPreservesPendingRoute() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        let pending = try makeReleaseRoute()
        try await repository.save(pending)
        let failingRepository = PendingAppRouteRepository(
            containerURL: directory,
            fileWriter: PendingRouteFailingFileWriter()
        )

        await #expect(throws: SharedSnapshotRepositoryError.atomicWriteFailed(
            fileName: SharedIdentifiers.pendingAppRouteFileName
        )) {
            _ = try await failingRepository.claimIfEligible(
                now: Self.createdAt.addingTimeInterval(1),
                activeOccurrenceIDs: [Self.occurrenceID]
            )
        }

        #expect(try await repository.load() == pending)
    }

    @Test("A failed terminal write preserves the processing release route")
    func failedTerminalWritePreservesProcessingRoute() async throws {
        let directory = try makeTemporaryDirectory()
        defer { removeTemporaryDirectory(directory) }
        let repository = PendingAppRouteRepository(containerURL: directory)
        try await repository.save(makeReleaseRoute())
        let processing = try await repository.claimIfEligible(
            now: Self.createdAt.addingTimeInterval(1),
            activeOccurrenceIDs: [Self.occurrenceID]
        )
        let failingRepository = PendingAppRouteRepository(
            containerURL: directory,
            fileWriter: PendingRouteFailingFileWriter()
        )

        await #expect(throws: SharedSnapshotRepositoryError.atomicWriteFailed(
            fileName: SharedIdentifiers.pendingAppRouteFileName
        )) {
            _ = try await failingRepository.recordTerminal(
                routeID: Self.routeID,
                outcome: .completed,
                retryAfter: nil,
                at: Self.createdAt.addingTimeInterval(2)
            )
        }

        #expect(try await repository.load() == processing)
    }
}

private struct PendingRouteFailingFileWriter: SnapshotFileWriting {
    func write(_ data: Data, to destinationURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private extension PendingAppRouteRepositoryTests {
    static let routeID = UUID(uuidString: "00000000-0000-4000-8000-000000000401")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000402")!
    static let occurrenceID = "occurrence-1"
    static let createdAt = Date(timeIntervalSince1970: 1_788_192_000)

    func makeRoute(
        destination: PendingAppRouteDestination = .coinStore,
        occurrenceID: String? = Self.occurrenceID,
        consumedAt: Date? = nil
    ) -> PendingAppRoute {
        try! PendingAppRoute(
            routeID: Self.routeID,
            destination: destination,
            createdAt: Self.createdAt,
            occurrenceID: occurrenceID,
            consumedAt: consumedAt
        )
    }

    func makeReleaseRoute() throws -> PendingAppRoute {
        try PendingAppRoute.releaseProcessing(
            routeID: Self.routeID,
            commandID: Self.commandID,
            createdAt: Self.createdAt,
            occurrenceID: Self.occurrenceID
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

    func routeFileURL(in directory: URL) -> URL {
        directory.appendingPathComponent(SharedIdentifiers.pendingAppRouteFileName)
    }
}
