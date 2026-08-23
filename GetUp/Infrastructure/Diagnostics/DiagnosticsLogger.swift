import Foundation
import OSLog

enum DiagnosticOperation: String, CaseIterable, Sendable {
    case dependencyAssembly = "dependency_assembly"
    case ruleLoad = "rule_load"
    case ruleSave = "rule_save"
    case ruleDelete = "rule_delete"
    case locationConditionLoad = "location_condition_load"
    case locationConditionSave = "location_condition_save"
    case locationConditionDelete = "location_condition_delete"
    case authorizationRefresh = "authorization_refresh"
    case scheduleReplace = "schedule_replace"
    case scheduleRemove = "schedule_remove"
    case locationMonitoringReplace = "location_monitoring_replace"
    case locationMonitoringStop = "location_monitoring_stop"
    case locationConditionRefresh = "location_condition_refresh"
    case restrictionEvaluate = "restriction_evaluate"
    case restrictionApply = "restriction_apply"
    case restrictionRemove = "restriction_remove"
    case lifecycleRestore = "lifecycle_restore"
}

enum DiagnosticErrorCode: String, CaseIterable, Sendable {
    case missingAppGroupIdentifier = "missing_app_group_identifier"
    case appGroupContainerUnavailable = "app_group_container_unavailable"
    case snapshotEncodingFailed = "snapshot_encoding_failed"
    case snapshotDecodingFailed = "snapshot_decoding_failed"
    case unsupportedSchema = "unsupported_schema"
    case revisionMismatch = "revision_mismatch"
    case snapshotReadFailed = "snapshot_read_failed"
    case snapshotWriteFailed = "snapshot_write_failed"
    case snapshotDeletionFailed = "snapshot_deletion_failed"
    case cancelled
    case unknown
}

enum DiagnosticResult: Equatable, Sendable {
    case success
    case failure(DiagnosticErrorCode)
}

struct DiagnosticEvent: Equatable, Sendable {
    let operation: DiagnosticOperation
    let result: DiagnosticResult

    static func failure(
        operation: DiagnosticOperation,
        error: any Error
    ) -> DiagnosticEvent {
        DiagnosticEvent(
            operation: operation,
            result: .failure(DiagnosticErrorClassifier.classify(error))
        )
    }

    var logMessage: String {
        switch result {
        case .success:
            "operation=\(operation.rawValue) result=success"
        case .failure(let errorCode):
            "operation=\(operation.rawValue) result=failure error=\(errorCode.rawValue)"
        }
    }
}

protocol DiagnosticsLogging: Sendable {
    func record(_ event: DiagnosticEvent)
    func record(_ error: any Error, operation: DiagnosticOperation)
}

struct DiagnosticsLogger: DiagnosticsLogging {
    private let logger: Logger

    init(
        subsystem: String = Bundle.main.bundleIdentifier ?? "com.getup.GetUp"
    ) {
        logger = Logger(subsystem: subsystem, category: "diagnostics")
    }

    func record(_ event: DiagnosticEvent) {
        switch event.result {
        case .success:
            logger.info("\(event.logMessage, privacy: .public)")
        case .failure(.cancelled):
            logger.notice("\(event.logMessage, privacy: .public)")
        case .failure:
            logger.error("\(event.logMessage, privacy: .public)")
        }
    }

    func record(_ error: any Error, operation: DiagnosticOperation) {
        record(.failure(operation: operation, error: error))
    }
}

enum DiagnosticErrorClassifier {
    static func classify(_ error: any Error) -> DiagnosticErrorCode {
        if error is CancellationError {
            return .cancelled
        }

        if let error = error as? DependencyContainerError {
            switch error {
            case .missingAppGroupIdentifier:
                return .missingAppGroupIdentifier
            case .appGroupContainerUnavailable:
                return .appGroupContainerUnavailable
            }
        }

        if let error = error as? SharedSnapshotRepositoryError {
            switch error {
            case .encodingFailed:
                return .snapshotEncodingFailed
            case .decodingFailed:
                return .snapshotDecodingFailed
            case .unsupportedSchema:
                return .unsupportedSchema
            case .revisionMismatch:
                return .revisionMismatch
            case .readFailed:
                return .snapshotReadFailed
            case .atomicWriteFailed:
                return .snapshotWriteFailed
            case .deletionFailed:
                return .snapshotDeletionFailed
            }
        }

        return .unknown
    }
}
