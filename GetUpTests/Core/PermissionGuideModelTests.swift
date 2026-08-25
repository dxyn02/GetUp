import Foundation
import Testing
@testable import GetUp

@MainActor
@Suite("Permission guide model")
struct PermissionGuideModelTests {
    @Test("Overview keeps all capabilities in the approved visual order")
    func overviewCapabilityOrder() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(
                familyControls: .denied,
                locationAuthorization: .whenInUse,
                locationAccuracy: .reduced,
                backgroundRefresh: .denied
            ),
            presentationState: .permissionRequired(
                missingPermissions: [.familyControls, .alwaysLocation, .fullAccuracy]
            )
        )

        #expect(model.currentScreen?.kind == .overview)
        #expect(model.capabilityItems.map(\.capability) == [
            .familyControls,
            .alwaysLocation,
            .fullAccuracy,
            .backgroundRefresh,
        ])
        #expect(model.capabilityItems.map(\.icon) == ["🛡️", "📍", "🎯", "🔄"])
        #expect(model.missingRequiredPermissions == [
            .familyControls,
            .alwaysLocation,
            .fullAccuracy,
        ])
    }

    @Test("Family Controls recovery requests authorization and closes after approval")
    func familyControlsRecoveryRequestsSystemAuthorization() {
        let model = makeModel(familyControls: .denied)

        model.beginPermissionSetup()
        #expect(model.currentScreen?.kind == .familyControls)
        #expect(model.requiresApplicationReselection)
        #expect(
            model.currentScreen?.primaryAction
                == .requestFamilyControlsAuthorization
        )

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive
        )
        #expect(!model.requiresApplicationReselection)
        #expect(!model.isPresented)
    }

    @Test("Location recovery combines Always and Full Accuracy")
    func locationRecoveryCombinesSettings() {
        let model = makeModel(
            locationAuthorization: .whenInUse,
            locationAccuracy: .reduced
        )

        model.beginPermissionSetup()
        let screen = model.currentScreen

        #expect(screen?.kind == .location)
        #expect(screen?.capabilityItems.map(\.capability) == [
            .alwaysLocation,
            .fullAccuracy,
        ])
        #expect(screen?.primaryAction == .openSettings)
        #expect(screen?.secondaryAction == .later)
        #expect(screen?.message.contains("항상 허용") == true)
        #expect(screen?.message.contains("정확한 위치") == true)
    }

    @Test("Background refresh is a diagnostic limitation, not a required permission")
    func backgroundRefreshIsDiagnostic() {
        let model = makeModel(backgroundRefresh: .restricted)

        model.beginPermissionSetup()

        #expect(model.missingRequiredPermissions.isEmpty)
        #expect(model.currentScreen?.kind == .backgroundRefresh)
        #expect(model.currentScreen?.message.contains("복구가 늦어질") == true)
        #expect(model.currentScreen?.message.contains("저전력 모드") == true)
    }

    @Test("Unavailable location distinguishes inactive and preserved active states", arguments: [false, true])
    func locationUnavailablePreservesAppliedState(isRestrictionApplied: Bool) {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .locationUnavailable(
                isRestrictionApplied: isRestrictionApplied
            )
        )

        #expect(
            model.currentScreen?.kind
                == .locationUnavailable(isRestrictionApplied: isRestrictionApplied)
        )
        #expect(model.currentScreen?.primaryAction == .openSettings)
        #expect(model.currentScreen?.secondaryAction == .retryLocation)
        #expect(
            model.currentScreen?.message.contains(
                isRestrictionApplied ? "제한을 유지" : "새 제한을 시작하지"
            ) == true
        )
    }

    @Test("A recovered location closes the unavailable guide")
    func recoveredLocationClosesGuide() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .locationUnavailable(isRestrictionApplied: true)
        )

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .active
        )

        #expect(!model.isPresented)
        #expect(model.currentScreen == nil)
    }

    @Test("A fully recovered permission overview closes")
    func recoveredPermissionsCloseOverview() {
        let model = makeModel(locationAuthorization: .whenInUse)

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive
        )

        #expect(!model.isPresented)
    }

    private func makeModel(
        familyControls: FamilyControlsAuthorizationStatus = .approved,
        locationAuthorization: LocationAuthorizationStatus = .always,
        locationAccuracy: LocationAccuracyStatus = .full,
        backgroundRefresh: BackgroundRefreshStatus = .available
    ) -> PermissionGuideModel {
        let authorization = TestFixtures.makeAuthorization(
            familyControls: familyControls,
            locationAuthorization: locationAuthorization,
            locationAccuracy: locationAccuracy,
            backgroundRefresh: backgroundRefresh
        )
        return PermissionGuideModel(
            authorization: authorization,
            presentationState: .permissionRequired(
                missingPermissions: missingPermissions(in: authorization)
            )
        )
    }

    private func missingPermissions(
        in authorization: AuthorizationSnapshot
    ) -> Set<RequiredPermission> {
        var result: Set<RequiredPermission> = []
        if authorization.familyControls != .approved { result.insert(.familyControls) }
        if authorization.locationAuthorization != .always { result.insert(.alwaysLocation) }
        if authorization.locationAccuracy != .full { result.insert(.fullAccuracy) }
        return result
    }
}
