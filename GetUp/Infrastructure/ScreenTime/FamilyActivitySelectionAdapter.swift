@preconcurrency import FamilyControls
import Foundation

@MainActor
protocol FamilyControlsAuthorizationSession {
    func authorizationStatus() -> FamilyControlsAuthorizationStatus
    func requestIndividualAuthorization() async throws -> FamilyControlsAuthorizationStatus
}

@MainActor
struct SystemFamilyControlsAuthorizationSession: FamilyControlsAuthorizationSession {
    private let authorizationCenter: AuthorizationCenter

    init(authorizationCenter: AuthorizationCenter = .shared) {
        self.authorizationCenter = authorizationCenter
    }

    func authorizationStatus() -> FamilyControlsAuthorizationStatus {
        Self.normalizedStatus(authorizationCenter.authorizationStatus)
    }

    func requestIndividualAuthorization() async throws -> FamilyControlsAuthorizationStatus {
        try await authorizationCenter.requestAuthorization(for: .individual)
        return authorizationStatus()
    }

    private static func normalizedStatus(
        _ status: AuthorizationStatus
    ) -> FamilyControlsAuthorizationStatus {
        return switch status {
        case .approved:
            .approved
        case .approvedWithDataAccess:
            .approved
        case .denied:
            .denied
        case .notDetermined:
            .notDetermined
        @unknown default:
            .notDetermined
        }
    }
}

@MainActor
final class FamilyActivitySelectionAdapter {
    private let authorizationSession: any FamilyControlsAuthorizationSession

    private(set) var selection: FamilyActivitySelection

    var applicationTokenCount: Int {
        selection.applicationTokens.count
    }

    var hasSelectedApplications: Bool {
        !selection.applicationTokens.isEmpty
    }

    init(
        selection: FamilyActivitySelection = FamilyActivitySelection(),
        authorizationSession: any FamilyControlsAuthorizationSession =
            SystemFamilyControlsAuthorizationSession()
    ) {
        self.selection = selection
        self.authorizationSession = authorizationSession
    }

    func authorizationStatus() -> FamilyControlsAuthorizationStatus {
        authorizationSession.authorizationStatus()
    }

    @discardableResult
    func requestIndividualAuthorizationIfNeeded() async throws
        -> FamilyControlsAuthorizationStatus
    {
        let currentStatus = authorizationSession.authorizationStatus()
        guard currentStatus != .approved else {
            return currentStatus
        }

        return try await authorizationSession.requestIndividualAuthorization()
    }

    func replaceSelection(with pickerResult: FamilyActivitySelection) {
        selection = pickerResult
    }

    func clearSelection() {
        selection = FamilyActivitySelection()
    }
}
