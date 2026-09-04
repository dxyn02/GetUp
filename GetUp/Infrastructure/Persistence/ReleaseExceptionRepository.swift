import Foundation

actor AppGroupReleaseExceptionRepository: ReleaseExceptionRepository {
    private let store: ReleaseExceptionFileStore

    init(containerURL: URL, fileWriter: any SnapshotFileWriting = AtomicSnapshotFileWriter()) {
        store = ReleaseExceptionFileStore(containerURL: containerURL, fileWriter: fileWriter)
    }

    func loadReleaseExceptions() async throws -> [ReleaseException] {
        do { return try store.load() }
        catch { throw ReleaseExceptionRepositoryError.readFailed }
    }

    /// Replaces the complete collection; callers must not use a stale read as a merge.
    func saveReleaseExceptions(_ exceptions: [ReleaseException]) async throws {
        do { try store.save(exceptions) }
        catch { throw ReleaseExceptionRepositoryError.writeFailed }
    }

    func insertReleaseException(_ exception: ReleaseException) async throws -> [ReleaseException] {
        try store.insert(exception)
    }

    func removeReleaseException(commandID: UUID, occurrenceID: String) async throws -> [ReleaseException] {
        try store.remove(commandID: commandID, occurrenceID: occurrenceID)
    }

    /// Revisions must describe all saved rules, not only currently active rules.
    func loadApplicableReleaseExceptions(
        at date: Date,
        activeOccurrenceIDs: Set<String>,
        currentRuleRevisions: [UUID: Int]
    ) async throws -> [ReleaseException] {
        guard date.timeIntervalSince1970.isFinite else {
            throw ReleaseExceptionRepositoryError.readFailed
        }
        do {
            return try store.withCoordinatedWrite { url in
                let stored = try store.read(from: url)
                let retained = stored.filter {
                    date < $0.expiresAt && currentRuleRevisions[$0.ruleID] == $0.ruleRevision
                }
                // Inactivity alone is not expiration: location can change again in this interval.
                if retained != stored { try store.write(retained, to: url) }
                return retained.filter {
                    $0.effectiveAt <= date && activeOccurrenceIDs.contains($0.occurrenceID)
                }
            }
        } catch SharedSnapshotRepositoryError.atomicWriteFailed {
            throw ReleaseExceptionRepositoryError.writeFailed
        } catch SharedSnapshotRepositoryError.encodingFailed {
            throw ReleaseExceptionRepositoryError.writeFailed
        } catch {
            throw ReleaseExceptionRepositoryError.readFailed
        }
    }
}

/// All in-repo writers share file coordination, including the legacy snapshot facade.
/// Atomic replacement protects bytes; coordination also protects cleanup's read-modify-write.
struct ReleaseExceptionFileStore: Sendable {
    let containerURL: URL
    let fileWriter: any SnapshotFileWriting
    private var fileName: String { SharedIdentifiers.releaseExceptionsFileName }
    private var fileURL: URL { containerURL.appendingPathComponent(fileName) }

    func load() throws -> [ReleaseException] {
        var coordinationError: NSError?
        var result: Result<[ReleaseException], Error>?
        NSFileCoordinator().coordinate(readingItemAt: fileURL, options: [], error: &coordinationError) { url in
            result = Result { try read(from: url) }
        }
        guard coordinationError == nil, let result else {
            throw SharedSnapshotRepositoryError.readFailed(fileName: fileName)
        }
        return try result.get()
    }

    func save(_ exceptions: [ReleaseException]) throws {
        try withCoordinatedWrite { try write(exceptions, to: $0) }
    }

    func withCoordinatedWrite<Value>(_ body: (URL) throws -> Value) throws -> Value {
        var coordinationError: NSError?
        var result: Result<Value, Error>?
        NSFileCoordinator().coordinate(writingItemAt: fileURL, options: [], error: &coordinationError) { url in
            result = Result { try body(url) }
        }
        guard coordinationError == nil, let result else {
            throw SharedSnapshotRepositoryError.atomicWriteFailed(fileName: fileName)
        }
        return try result.get()
    }

    func insert(_ exception: ReleaseException) throws -> [ReleaseException] {
        try mutate { entries in
            if let existing = entries.first(where: {
                $0.commandID == exception.commandID || $0.occurrenceID == exception.occurrenceID
            }) {
                // Compare at the established ISO8601 snapshot precision after a disk round trip.
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.sortedKeys]
                guard try encoder.encode(existing) == encoder.encode(exception) else {
                    throw ReleaseExceptionRepositoryError.conflict
                }
                return entries
            }
            return entries + [exception]
        }
    }

    func remove(commandID: UUID, occurrenceID: String) throws -> [ReleaseException] {
        try mutate { entries in
            entries.filter { !($0.commandID == commandID && $0.occurrenceID == occurrenceID) }
        }
    }

    private func mutate(_ transform: ([ReleaseException]) throws -> [ReleaseException]) throws -> [ReleaseException] {
        do {
            return try withCoordinatedWrite { url in
                let previous = try read(from: url)
                let next = try transform(previous)
                if next != previous { try write(next, to: url) }
                return next
            }
        } catch let error as ReleaseExceptionRepositoryError {
            throw error
        } catch SharedSnapshotRepositoryError.atomicWriteFailed {
            throw ReleaseExceptionRepositoryError.writeFailed
        } catch SharedSnapshotRepositoryError.encodingFailed {
            throw ReleaseExceptionRepositoryError.writeFailed
        } catch {
            throw ReleaseExceptionRepositoryError.readFailed
        }
    }

    func read(from url: URL) throws -> [ReleaseException] {
        let data: Data
        do { data = try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return [] }
        catch { throw SharedSnapshotRepositoryError.readFailed(fileName: fileName) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let header: Header
        do { header = try decoder.decode(Header.self, from: data) }
        catch { throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName) }
        guard header.schemaVersion == ReleaseExceptionCollectionSnapshot.currentSchemaVersion else {
            throw SharedSnapshotRepositoryError.unsupportedSchema(
                fileName: fileName, found: header.schemaVersion,
                supported: ReleaseExceptionCollectionSnapshot.currentSchemaVersion
            )
        }
        do { return try decoder.decode(ReleaseExceptionCollectionSnapshot.self, from: data).exceptions }
        catch { throw SharedSnapshotRepositoryError.decodingFailed(fileName: fileName) }
    }

    func write(_ exceptions: [ReleaseException], to url: URL) throws {
        let data: Data
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            data = try encoder.encode(ReleaseExceptionCollectionSnapshot(exceptions: exceptions))
        } catch { throw SharedSnapshotRepositoryError.encodingFailed(fileName: fileName) }
        do { try fileWriter.write(data, to: url) }
        catch { throw SharedSnapshotRepositoryError.atomicWriteFailed(fileName: fileName) }
    }

    private struct Header: Decodable { let schemaVersion: Int }
}
