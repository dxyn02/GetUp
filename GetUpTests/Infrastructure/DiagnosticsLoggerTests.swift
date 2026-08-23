import Testing
@testable import GetUp

@Suite("Diagnostics logger privacy")
struct DiagnosticsLoggerTests {
    @Test("Repository failures map to stable codes", arguments: repositoryFailures)
    func repositoryFailureClassification(
        error: SharedSnapshotRepositoryError,
        expectedCode: DiagnosticErrorCode
    ) {
        #expect(DiagnosticErrorClassifier.classify(error) == expectedCode)
    }

    @Test("Dependency assembly failures map to stable codes")
    func dependencyFailureClassification() {
        #expect(
            DiagnosticErrorClassifier.classify(
                DependencyContainerError.missingAppGroupIdentifier
            ) == .missingAppGroupIdentifier
        )
        #expect(
            DiagnosticErrorClassifier.classify(
                DependencyContainerError.appGroupContainerUnavailable
            ) == .appGroupContainerUnavailable
        )
    }

    @Test("Unknown error text cannot enter a diagnostic event")
    func sensitiveUnknownErrorTextIsDiscarded() {
        let sensitiveText = "latitude=37.5665 token=opaque-secret-token"
        let event = DiagnosticEvent.failure(
            operation: .restrictionApply,
            error: SensitiveError(description: sensitiveText)
        )

        #expect(event.result == .failure(.unknown))
        #expect(event.logMessage == "operation=restriction_apply result=failure error=unknown")
        #expect(!event.logMessage.contains(sensitiveText))
        #expect(!event.logMessage.contains("37.5665"))
        #expect(!event.logMessage.contains("opaque-secret-token"))
    }

    private static let repositoryFailures: [(
        SharedSnapshotRepositoryError,
        DiagnosticErrorCode
    )] = [
        (
            .encodingFailed(fileName: "sensitive-file-name"),
            .snapshotEncodingFailed
        ),
        (
            .decodingFailed(fileName: "sensitive-file-name"),
            .snapshotDecodingFailed
        ),
        (
            .unsupportedSchema(
                fileName: "sensitive-file-name",
                found: 99,
                supported: 1
            ),
            .unsupportedSchema
        ),
        (
            .revisionMismatch(expected: 1, actual: 99),
            .revisionMismatch
        ),
        (
            .readFailed(fileName: "sensitive-file-name"),
            .snapshotReadFailed
        ),
        (
            .atomicWriteFailed(fileName: "sensitive-file-name"),
            .snapshotWriteFailed
        ),
        (
            .deletionFailed(fileName: "sensitive-file-name"),
            .snapshotDeletionFailed
        ),
    ]
}

private struct SensitiveError: Error, CustomStringConvertible {
    let description: String
}
