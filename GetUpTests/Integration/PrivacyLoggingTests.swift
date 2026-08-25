import Foundation
import Testing
@testable import GetUp

@Suite("Privacy-safe diagnostic logging")
struct PrivacyLoggingTests {
    @Test("Sensitive error context is discarded before the final writer")
    func sensitiveErrorContextNeverReachesWriter() {
        let writer = CapturingDiagnosticWriter()
        let logger = DiagnosticsLogger(writer: writer)
        let sensitiveFragments = [
            "37.5665",
            "127.1087",
            "horizontalAccuracy=842.25",
            "opaque-secret-application-token",
            "private-place-name",
        ]

        let errors: [any Error] = [
            SensitivePrivacyError(
                description: sensitiveFragments.joined(separator: " ")
            ),
            SharedSnapshotRepositoryError.encodingFailed(
                fileName: sensitiveFragments[3]
            ),
            SharedSnapshotRepositoryError.unsupportedSchema(
                fileName: sensitiveFragments[4],
                found: 37,
                supported: 1
            ),
            SharedSnapshotRepositoryError.revisionMismatch(
                expected: 37,
                actual: 127
            ),
        ]

        for (operation, error) in zip(DiagnosticOperation.allCases, errors) {
            logger.record(error, operation: operation)
        }

        let entries = writer.entries
        #expect(entries.count == errors.count)
        for entry in entries {
            for sensitiveFragment in sensitiveFragments {
                #expect(!entry.message.contains(sensitiveFragment))
            }
            #expect(!entry.message.contains("37"))
            #expect(!entry.message.contains("127"))
        }
    }

    @Test("Only closed operation, result, and error code fields are emitted")
    func emittedMessagesUseOnlyClosedFields() {
        let writer = CapturingDiagnosticWriter()
        let logger = DiagnosticsLogger(writer: writer)

        for operation in DiagnosticOperation.allCases {
            logger.record(
                DiagnosticEvent(operation: operation, result: .success)
            )
        }
        for errorCode in DiagnosticErrorCode.allCases {
            logger.record(
                DiagnosticEvent(
                    operation: .restrictionEvaluate,
                    result: .failure(errorCode)
                )
            )
        }

        let expectedMessages = Set(
            DiagnosticOperation.allCases.map {
                "operation=\($0.rawValue) result=success"
            }
            + DiagnosticErrorCode.allCases.map {
                "operation=restriction_evaluate result=failure error=\($0.rawValue)"
            }
        )
        let actualMessages = Set(writer.entries.map(\.message))

        #expect(actualMessages == expectedMessages)
    }

    @Test("Success, cancellation, and failure use their intended log levels")
    func diagnosticLogLevelsRemainStable() {
        let writer = CapturingDiagnosticWriter()
        let logger = DiagnosticsLogger(writer: writer)

        logger.record(
            DiagnosticEvent(operation: .ruleLoad, result: .success)
        )
        logger.record(
            DiagnosticEvent(
                operation: .ruleSave,
                result: .failure(.cancelled)
            )
        )
        logger.record(
            DiagnosticEvent(
                operation: .ruleDelete,
                result: .failure(.unknown)
            )
        )

        #expect(writer.entries.map(\.level) == [.info, .notice, .error])
    }
}

private struct CapturedDiagnosticEntry: Equatable, Sendable {
    let level: DiagnosticLogLevel
    let message: String
}

private final class CapturingDiagnosticWriter:
    DiagnosticEventWriting,
    @unchecked Sendable
{
    private let lock = NSLock()
    private var storedEntries: [CapturedDiagnosticEntry] = []

    var entries: [CapturedDiagnosticEntry] {
        lock.withLock { storedEntries }
    }

    func write(_ event: DiagnosticEvent, level: DiagnosticLogLevel) {
        lock.withLock {
            storedEntries.append(
                CapturedDiagnosticEntry(
                    level: level,
                    message: event.logMessage
                )
            )
        }
    }
}

private struct SensitivePrivacyError: Error, CustomStringConvertible {
    let description: String
}
