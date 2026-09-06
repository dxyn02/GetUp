import Darwin
import Foundation

/// Cooperative lock for all restriction writers sharing one App Group.
/// A busy caller returns immediately; process exit closes the descriptor and releases ownership.
final class RuleReleaseLocalLease: @unchecked Sendable {
    private let descriptor: Int32
    private let coordinatedDirectory: URL

    init(directory: URL) throws {
        coordinatedDirectory = directory.standardizedFileURL.resolvingSymlinksInPath()
        let path = coordinatedDirectory.appendingPathComponent("release-coordination.lock").path
        let descriptor = open(path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw RuleReleaseCoordinationError.applicationFailed }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            throw RuleReleaseCoordinationError.applicationFailed
        }
        self.descriptor = descriptor
    }

    func coordinates(directory: URL) -> Bool {
        coordinatedDirectory == directory.standardizedFileURL.resolvingSymlinksInPath()
    }

    deinit {
        flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
