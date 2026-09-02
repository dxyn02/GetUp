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
}

private struct PendingRouteFailingFileWriter: SnapshotFileWriting {
    func write(_ data: Data, to destinationURL: URL) throws {
        throw CocoaError(.fileWriteUnknown)
    }
}

private extension PendingAppRouteRepositoryTests {
    static let routeID = UUID(uuidString: "00000000-0000-4000-8000-000000000401")!
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
