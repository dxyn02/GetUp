import Foundation

enum DependencyContainerError: Error, Equatable, Sendable {
    case missingAppGroupIdentifier
    case appGroupContainerUnavailable
}

struct DependencyContainer: Sendable {
    let sharedSnapshotRepository: SharedSnapshotRepository
    let diagnostics: any DiagnosticsLogging

    var ruleRepository: any RuleRepository {
        sharedSnapshotRepository
    }

    var savedPlaceRepository: any SavedPlaceRepository {
        sharedSnapshotRepository
    }

    var locationConditionRepository: any LocationConditionRepository {
        sharedSnapshotRepository
    }

    init(
        containerURL: URL,
        fileWriter: any SnapshotFileWriting = AtomicSnapshotFileWriter(),
        diagnostics: any DiagnosticsLogging = DiagnosticsLogger()
    ) {
        sharedSnapshotRepository = SharedSnapshotRepository(
            containerURL: containerURL,
            fileWriter: fileWriter
        )
        self.diagnostics = diagnostics
    }

    static func live(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> DependencyContainer {
        guard let appGroupIdentifier = SharedIdentifiers.appGroupIdentifier(in: bundle) else {
            throw DependencyContainerError.missingAppGroupIdentifier
        }
        guard
            let containerURL = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else {
            throw DependencyContainerError.appGroupContainerUnavailable
        }

        return DependencyContainer(
            containerURL: containerURL
        )
    }
}
