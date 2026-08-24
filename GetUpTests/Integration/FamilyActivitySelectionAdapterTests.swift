import FamilyControls
import Testing
@testable import GetUp

@MainActor
@Suite("Family activity selection adapter")
struct FamilyActivitySelectionAdapterTests {
    @Test("An existing individual authorization does not request again")
    func approvedAuthorizationIsReused() async throws {
        let session = FakeFamilyControlsAuthorizationSession(
            currentStatus: .approved,
            requestResult: .approved
        )
        let adapter = FamilyActivitySelectionAdapter(
            authorizationSession: session
        )

        let status = try await adapter.requestIndividualAuthorizationIfNeeded()

        #expect(status == .approved)
        #expect(session.requestCount == 0)
    }

    @Test("An undetermined authorization requests the individual member scope")
    func undeterminedAuthorizationRequestsIndividualScope() async throws {
        let session = FakeFamilyControlsAuthorizationSession(
            currentStatus: .notDetermined,
            requestResult: .approved
        )
        let adapter = FamilyActivitySelectionAdapter(
            authorizationSession: session
        )

        let status = try await adapter.requestIndividualAuthorizationIfNeeded()

        #expect(status == .approved)
        #expect(session.requestCount == 1)
    }

    @Test("A denied authorization can be explicitly requested again")
    func deniedAuthorizationCanBeRequestedAgain() async throws {
        let session = FakeFamilyControlsAuthorizationSession(
            currentStatus: .denied,
            requestResult: .denied
        )
        let adapter = FamilyActivitySelectionAdapter(
            authorizationSession: session
        )

        let status = try await adapter.requestIndividualAuthorizationIfNeeded()

        #expect(status == .denied)
        #expect(session.requestCount == 1)
    }

    @Test("The picker result is preserved as an opaque selection")
    func pickerResultIsPreserved() {
        let adapter = FamilyActivitySelectionAdapter()
        let pickerResult = FamilyActivitySelection(includeEntireCategory: true)

        adapter.replaceSelection(with: pickerResult)

        #expect(adapter.selection == pickerResult)
        #expect(adapter.applicationTokenCount == pickerResult.applicationTokens.count)
        #expect(!adapter.hasSelectedApplications)
    }

    @Test("Clearing replaces the picker result with an empty selection")
    func selectionCanBeCleared() {
        let pickerResult = FamilyActivitySelection(includeEntireCategory: true)
        let adapter = FamilyActivitySelectionAdapter(selection: pickerResult)

        adapter.clearSelection()

        #expect(adapter.selection == FamilyActivitySelection())
        #expect(adapter.applicationTokenCount == 0)
    }
}

@MainActor
private final class FakeFamilyControlsAuthorizationSession:
    FamilyControlsAuthorizationSession
{
    private let currentStatus: FamilyControlsAuthorizationStatus
    private let requestResult: FamilyControlsAuthorizationStatus

    private(set) var requestCount = 0

    init(
        currentStatus: FamilyControlsAuthorizationStatus,
        requestResult: FamilyControlsAuthorizationStatus
    ) {
        self.currentStatus = currentStatus
        self.requestResult = requestResult
    }

    func authorizationStatus() -> FamilyControlsAuthorizationStatus {
        currentStatus
    }

    func requestIndividualAuthorization() async throws
        -> FamilyControlsAuthorizationStatus
    {
        requestCount += 1
        return requestResult
    }
}
