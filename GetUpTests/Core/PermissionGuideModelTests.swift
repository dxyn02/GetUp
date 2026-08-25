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
            ),
            presentationMode: .onboarding
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
        #expect(model.currentScreen?.primaryAction == .next)
    }

    @Test("Undetermined Family Controls requests authorization with Next disabled")
    func undeterminedFamilyControlsRequestsAuthorization() {
        let model = makeModel(familyControls: .notDetermined)

        model.select(.familyControls)
        #expect(model.currentScreen?.kind == .familyControls)
        #expect(model.currentScreen?.primaryAction == .next)
        #expect(model.currentScreen?.isPrimaryActionEnabled == false)
        #expect(
            model.currentScreen?.automaticAction
                == .requestFamilyControlsAuthorization
        )

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive
        )
        #expect(model.currentScreen?.kind == .familyControls)
        #expect(model.currentScreen?.primaryAction == .next)
        #expect(model.currentScreen?.isPrimaryActionEnabled == true)
    }

    @Test("Denied Family Controls opens Settings")
    func deniedFamilyControlsOpensSettings() {
        let model = makeModel(familyControls: .denied)

        model.select(.familyControls)

        #expect(model.currentScreen?.primaryAction == .openSettings)
        #expect(model.currentScreen?.isPrimaryActionEnabled == true)
        #expect(model.currentScreen?.automaticAction == nil)
    }

    @Test("Approved permissions advance through every detail screen")
    func approvedPermissionsAdvanceSequentially() {
        let model = makeModel()

        model.advancePermissionSetup()
        #expect(model.currentScreen?.kind == .familyControls)
        #expect(model.currentScreen?.primaryAction == .next)

        model.advancePermissionSetup()
        #expect(model.currentScreen?.kind == .location)
        #expect(model.currentScreen?.primaryAction == .next)

        model.advancePermissionSetup()
        #expect(model.currentScreen?.kind == .backgroundRefresh)
        #expect(model.currentScreen?.primaryAction == .next)

        model.advancePermissionSetup()
        #expect(!model.isPresented)
    }

    @Test("A fully approved recovery never presents the onboarding permission check")
    func approvedRecoveryDoesNotPresentGuide() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive,
            presentationMode: .recovery
        )

        #expect(!model.isPresented)
    }

    @Test("Permission onboarding is presented only once across app launches")
    func permissionOnboardingPersistsFirstPresentation() {
        let suiteName = "PermissionGuideModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PermissionOnboardingStateStore(
            defaults: defaults,
            key: "hasPresented"
        )

        let firstLaunch = PermissionGuideLaunchRouter.makeInitialModel(
            authorization: TestFixtures.makeAuthorization(
                familyControls: .notDetermined,
                locationAuthorization: .notDetermined
            ),
            presentationState: .permissionRequired(
                missingPermissions: [.familyControls, .alwaysLocation]
            ),
            onboardingStateStore: store
        )
        let secondLaunch = PermissionGuideLaunchRouter.makeInitialModel(
            authorization: TestFixtures.makeAuthorization(
                familyControls: .notDetermined,
                locationAuthorization: .notDetermined
            ),
            presentationState: .permissionRequired(
                missingPermissions: [.familyControls, .alwaysLocation]
            ),
            onboardingStateStore: store
        )

        #expect(firstLaunch.presentationMode == .onboarding)
        #expect(firstLaunch.currentScreen?.kind == .overview)
        #expect(store.hasBeenPresented)
        #expect(secondLaunch.presentationMode == .recovery)
        #expect(!secondLaunch.isPresented)
    }

    @Test("A legacy install with determined permissions migrates directly to recovery")
    func determinedPermissionsWithoutMarkerSkipOnboarding() {
        let suiteName = "PermissionGuideModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PermissionOnboardingStateStore(
            defaults: defaults,
            key: "hasPresented"
        )

        let model = PermissionGuideLaunchRouter.makeInitialModel(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive,
            onboardingStateStore: store
        )

        #expect(store.hasBeenPresented)
        #expect(model.presentationMode == .recovery)
        #expect(!model.isPresented)
    }

    @Test("Recovery opens only the denied Family Controls screen")
    func recoveryRoutesDirectlyToDeniedFamilyControls() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(familyControls: .denied),
            presentationState: .permissionRequired(missingPermissions: [.familyControls]),
            presentationMode: .recovery
        )

        #expect(model.currentScreen?.kind == .familyControls)
    }

    @Test("Recovery opens only the insufficient location screen")
    func recoveryRoutesDirectlyToLocation() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(
                locationAuthorization: .whenInUse,
                locationAccuracy: .reduced
            ),
            presentationState: .permissionRequired(
                missingPermissions: [.alwaysLocation, .fullAccuracy]
            ),
            presentationMode: .recovery
        )

        #expect(model.currentScreen?.kind == .location)
    }

    @Test("Recovery advances from a repaired permission to the next denied permission")
    func recoveryTracksOnlyCurrentDeniedPermission() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(
                familyControls: .denied,
                locationAuthorization: .whenInUse
            ),
            presentationState: .permissionRequired(
                missingPermissions: [.familyControls, .alwaysLocation]
            ),
            presentationMode: .recovery
        )

        model.update(
            authorization: TestFixtures.makeAuthorization(
                locationAuthorization: .whenInUse
            ),
            presentationState: .permissionRequired(missingPermissions: [.alwaysLocation])
        )

        #expect(model.currentScreen?.kind == .location)
    }

    @Test("Undetermined permission screens are reserved for onboarding")
    func undeterminedRecoveryDoesNotPresentGuide() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(familyControls: .notDetermined),
            presentationState: .permissionRequired(missingPermissions: [.familyControls]),
            presentationMode: .recovery
        )

        #expect(!model.isPresented)
    }

    @Test("Location recovery combines Always and Full Accuracy")
    func locationRecoveryCombinesSettings() {
        let model = makeModel(
            locationAuthorization: .whenInUse,
            locationAccuracy: .reduced
        )

        model.select(.location)
        let screen = model.currentScreen

        #expect(screen?.kind == .location)
        #expect(screen?.capabilityItems.map(\.capability) == [
            .alwaysLocation,
            .fullAccuracy,
        ])
        #expect(screen?.primaryAction == .openSettings)
        #expect(screen?.secondaryAction == .later)
        #expect(screen?.automaticAction == nil)
        #expect(screen?.message.contains("항상 허용") == true)
        #expect(screen?.message.contains("앱을 사용하는 동안 허용") == true)
        #expect(screen?.message.contains("정확한 위치") == true)
    }

    @Test("Undetermined location requests the first system prompt with Next disabled")
    func undeterminedLocationRequestsAuthorization() {
        let model = makeModel(locationAuthorization: .notDetermined)

        model.select(.location)

        #expect(model.currentScreen?.primaryAction == .next)
        #expect(model.currentScreen?.isPrimaryActionEnabled == false)
        #expect(
            model.currentScreen?.automaticAction
                == .requestLocationAuthorization
        )
    }

    @Test("Background refresh is a diagnostic limitation, not a required permission")
    func backgroundRefreshIsDiagnostic() {
        let model = makeModel(backgroundRefresh: .restricted)

        model.select(.backgroundRefresh)

        #expect(model.missingRequiredPermissions.isEmpty)
        #expect(model.currentScreen?.kind == .backgroundRefresh)
        #expect(model.currentScreen?.message.contains("복구가 늦어질") == true)
        #expect(model.currentScreen?.message.contains("저전력 모드") == true)
        #expect(model.currentScreen?.primaryAction == .later)
        #expect(model.currentScreen?.secondaryAction == nil)
    }

    @Test("Background refresh alone does not interrupt an active app session")
    func backgroundRefreshAloneDoesNotPresentGuide() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(backgroundRefresh: .restricted),
            presentationState: .inactive
        )

        #expect(!model.isPresented)
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

    @Test("An approved onboarding flow stays visible until the user advances")
    func approvedOnboardingWaitsForUserAdvance() {
        let model = makeModel(locationAuthorization: .whenInUse)

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive
        )

        #expect(model.currentScreen?.kind == .overview)
        #expect(model.currentScreen?.primaryAction == .next)
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
            ),
            presentationMode: .onboarding
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
