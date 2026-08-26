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
        #expect(
            model.capabilityItems[1].cause
                == "나서 앱이 열려 있지 않을 때도 설정한 장소를 확인하는 데 필요해요."
        )
        #expect(model.missingRequiredPermissions == [
            .familyControls,
            .alwaysLocation,
            .fullAccuracy,
        ])
        #expect(model.currentScreen?.primaryAction == .next)
    }

    @Test("Undetermined Family Controls waits for an explicit authorization tap")
    func undeterminedFamilyControlsRequestsAuthorization() {
        let model = makeModel(familyControls: .notDetermined)

        model.select(.familyControls)
        #expect(model.currentScreen?.kind == .familyControls)
        #expect(model.currentScreen?.primaryAction == .requestFamilyControlsAuthorization)
        #expect(model.currentScreen?.isPrimaryActionEnabled == true)
        #expect(model.currentScreen?.automaticAction == nil)

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive
        )
        #expect(model.currentScreen?.kind == .location)
    }

    @Test("Denied Family Controls remains visible and changes the primary action to Settings")
    func deniedFamilyControlsAfterRequestOpensSettings() {
        let model = makeModel(familyControls: .notDetermined)
        model.select(.familyControls)

        model.update(
            authorization: TestFixtures.makeAuthorization(familyControls: .denied),
            presentationState: .permissionRequired(missingPermissions: [.familyControls])
        )

        #expect(model.currentScreen?.kind == .familyControls)
        #expect(model.currentScreen?.primaryAction == .openSettings)
    }

    @Test("Repairing Family Controls during normal use closes the recovery screen")
    func approvedFamilyControlsRecoveryClosesGuide() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(familyControls: .denied),
            presentationState: .permissionRequired(missingPermissions: [.familyControls]),
            presentationMode: .recovery
        )

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive
        )

        #expect(!model.isPresented)
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
        #expect(model.currentScreen?.primaryAction == .completeOnboarding)

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

    @Test("An interrupted permission onboarding returns on the next launch")
    func incompletePermissionOnboardingReturnsAfterRelaunch() {
        let suiteName = "PermissionGuideModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PermissionOnboardingStateStore(
            defaults: defaults,
            key: "hasCompleted"
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
        #expect(!store.hasCompleted)
        #expect(secondLaunch.presentationMode == .onboarding)
        #expect(secondLaunch.currentScreen?.kind == .overview)
    }

    @Test("Determined permissions do not complete onboarding without the final action")
    func determinedPermissionsWithoutCompletionStillShowOnboarding() {
        let suiteName = "PermissionGuideModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PermissionOnboardingStateStore(
            defaults: defaults,
            key: "hasCompleted"
        )

        let model = PermissionGuideLaunchRouter.makeInitialModel(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive,
            onboardingStateStore: store
        )

        #expect(!store.hasCompleted)
        #expect(model.presentationMode == .onboarding)
        #expect(model.currentScreen?.kind == .overview)
    }

    @Test("The completed marker routes later launches directly to recovery")
    func completedPermissionOnboardingDoesNotReturn() {
        let suiteName = "PermissionGuideModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = PermissionOnboardingStateStore(
            defaults: defaults,
            key: "hasCompleted"
        )
        store.markCompleted()

        let model = PermissionGuideLaunchRouter.makeInitialModel(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive,
            onboardingStateStore: store
        )

        #expect(store.hasCompleted)
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

    @Test("Repairing the visible recovery permission closes that screen")
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

        #expect(!model.isPresented)
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

    @Test("When In Use location offers the approved explicit Always authorization request")
    func whenInUseLocationOffersAlwaysRequest() {
        let model = makeModel(
            locationAuthorization: .whenInUse,
            locationAccuracy: .full
        )

        model.select(.location)
        let screen = model.currentScreen

        #expect(screen?.kind == .location)
        #expect(screen?.capabilityItems.map(\.capability) == [
            .alwaysLocation,
            .fullAccuracy,
        ])
        #expect(screen?.primaryAction == .requestAlwaysLocationAuthorization)
        #expect(screen?.secondaryAction == nil)
        #expect(screen?.automaticAction == nil)
        #expect(screen?.title == "항상 위치 접근 권한이 필요해요")
        #expect(screen?.message.contains("항상 허용") == true)
    }

    @Test("Undetermined location waits for an explicit When In Use authorization tap")
    func undeterminedLocationRequestsAuthorization() {
        let model = makeModel(locationAuthorization: .notDetermined)

        model.select(.location)

        #expect(model.currentScreen?.primaryAction == .requestLocationAuthorization)
        #expect(model.currentScreen?.isPrimaryActionEnabled == true)
        #expect(model.currentScreen?.automaticAction == nil)
    }

    @Test("When In Use approval advances onboarding to the Always request on the same location step")
    func whenInUseApprovalAdvancesToAlwaysRequest() {
        let model = makeModel(locationAuthorization: .notDetermined)
        model.select(.location)

        model.update(
            authorization: TestFixtures.makeAuthorization(
                locationAuthorization: .whenInUse
            ),
            presentationState: .permissionRequired(missingPermissions: [.alwaysLocation])
        )

        #expect(model.currentScreen?.kind == .location)
        #expect(model.currentScreen?.primaryAction == .requestAlwaysLocationAuthorization)
    }

    @Test("Always and precise location approval advances onboarding to Background Refresh")
    func alwaysLocationApprovalAdvancesOnboarding() {
        let model = makeModel(locationAuthorization: .whenInUse)
        model.select(.location)

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive
        )

        #expect(model.currentScreen?.kind == .backgroundRefresh)
    }

    @Test("Repairing location during normal use closes the recovery screen")
    func approvedLocationRecoveryClosesGuide() {
        let model = PermissionGuideModel(
            authorization: TestFixtures.makeAuthorization(
                locationAuthorization: .whenInUse
            ),
            presentationState: .permissionRequired(missingPermissions: [.alwaysLocation]),
            presentationMode: .recovery
        )

        model.update(
            authorization: TestFixtures.makeAuthorization(),
            presentationState: .inactive
        )

        #expect(!model.isPresented)
    }

    @Test("Denied location remains visible and changes the primary action to Settings")
    func deniedLocationAfterRequestOpensSettings() {
        let model = makeModel(locationAuthorization: .notDetermined)
        model.select(.location)

        model.update(
            authorization: TestFixtures.makeAuthorization(
                locationAuthorization: .denied
            ),
            presentationState: .permissionRequired(missingPermissions: [.alwaysLocation])
        )

        #expect(model.currentScreen?.kind == .location)
        #expect(model.currentScreen?.primaryAction == .openSettings)
    }

    @Test("Declining the Always upgrade changes the next primary action to Settings")
    func declinedAlwaysLocationUpgradeOpensSettings() {
        let model = makeModel(locationAuthorization: .whenInUse)
        model.select(.location)

        model.update(
            authorization: TestFixtures.makeAuthorization(
                locationAuthorization: .whenInUse
            ),
            presentationState: .permissionRequired(missingPermissions: [.alwaysLocation]),
            requestedAction: .requestAlwaysLocationAuthorization
        )

        #expect(model.currentScreen?.kind == .location)
        #expect(model.currentScreen?.primaryAction == .openSettings)
    }

    @Test("Background refresh remains diagnostic and finishes onboarding with Start")
    func backgroundRefreshIsDiagnostic() {
        let model = makeModel(backgroundRefresh: .restricted)

        model.select(.backgroundRefresh)

        #expect(model.missingRequiredPermissions.isEmpty)
        #expect(model.currentScreen?.kind == .backgroundRefresh)
        #expect(model.currentScreen?.message.contains("복구가 늦어질") == true)
        #expect(model.currentScreen?.message.contains("저전력 모드") == true)
        #expect(model.currentScreen?.primaryAction == .completeOnboarding)
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
