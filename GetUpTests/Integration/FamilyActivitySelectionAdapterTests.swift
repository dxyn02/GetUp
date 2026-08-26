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

    @Test("A selected category is counted as a restriction target")
    func selectedCategoryIsCounted() throws {
        var pickerResult = FamilyActivitySelection()
        pickerResult.categoryTokens = [
            try TestFixtures.activityCategoryToken(seed: 1),
        ]
        let adapter = FamilyActivitySelectionAdapter()

        adapter.replaceSelection(with: pickerResult)

        #expect(adapter.applicationTokenCount == 1)
        #expect(adapter.hasSelectedApplications)
        #expect(
            adapter.selection.restrictionSelectionSummary(
                countedTargets: adapter.applicationTokenCount
            ) == .multiple
        )
    }

    @Test("An individual application selection keeps its exact count")
    func individualSelectionKeepsExactCount() {
        let selection = FamilyActivitySelection(includeEntireCategory: true)

        #expect(selection.restrictionSelectionSummary(countedTargets: 3) == .exact(3))
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
