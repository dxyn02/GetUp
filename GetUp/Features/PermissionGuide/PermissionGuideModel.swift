import Foundation
import Observation

enum PermissionGuideCapability: CaseIterable, Equatable, Sendable {
    case familyControls
    case alwaysLocation
    case fullAccuracy
    case backgroundRefresh

    var icon: String {
        switch self {
        case .familyControls: "🛡️"
        case .alwaysLocation: "📍"
        case .fullAccuracy: "🎯"
        case .backgroundRefresh: "🔄"
        }
    }

    var title: String {
        switch self {
        case .familyControls: AppLocalizedCopy.string("앱 사용 제한")
        case .alwaysLocation: AppLocalizedCopy.string("위치 접근")
        case .fullAccuracy: AppLocalizedCopy.string("정확한 위치")
        case .backgroundRefresh: AppLocalizedCopy.string("백그라운드 앱 새로고침")
        }
    }
}

enum PermissionGuideCapabilityStatus: Equatable, Sendable {
    case ready
    case actionRequired
    case limited
}

struct PermissionGuideCapabilityItem: Equatable, Sendable {
    let capability: PermissionGuideCapability
    let status: PermissionGuideCapabilityStatus
    let cause: String
    let recovery: String

    var icon: String { capability.icon }
    var title: String { capability.title }
}

enum PermissionGuideScreenKind: Equatable, Sendable {
    case overview
    case familyControls
    case location
    case backgroundRefresh
    case locationUnavailable(isRestrictionApplied: Bool)
}

enum PermissionGuidePresentationMode: Equatable, Sendable {
    case onboarding
    case recovery
}

struct PermissionOnboardingStateStore {
    private static let liveKey = "permissionOnboarding.hasCompleted.v1"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = Self.liveKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    var hasCompleted: Bool {
        defaults.bool(forKey: key)
    }

    func markCompleted() {
        defaults.set(true, forKey: key)
    }

    func reset() {
        defaults.removeObject(forKey: key)
    }
}

@MainActor
enum PermissionGuideLaunchRouter {
    static func makeInitialModel(
        authorization: AuthorizationSnapshot,
        presentationState: RestrictionPresentationState,
        onboardingStateStore: PermissionOnboardingStateStore
    ) -> PermissionGuideModel {
        let presentationMode: PermissionGuidePresentationMode =
            onboardingStateStore.hasCompleted ? .recovery : .onboarding

        return PermissionGuideModel(
            authorization: authorization,
            presentationState: presentationState,
            presentationMode: presentationMode
        )
    }
}

enum PermissionGuideAction: Equatable, Hashable, Sendable {
    case next
    case confirm
    case completeOnboarding
    case requestFamilyControlsAuthorization
    case requestLocationAuthorization
    case requestAlwaysLocationAuthorization
    case openSettings
    case retryLocation
}

struct PermissionGuideScreenState: Equatable, Sendable {
    let kind: PermissionGuideScreenKind
    let eyebrow: String
    let title: String
    let message: String
    let capabilityItems: [PermissionGuideCapabilityItem]
    let primaryAction: PermissionGuideAction
    let secondaryAction: PermissionGuideAction?
    let isPrimaryActionEnabled: Bool
    let automaticAction: PermissionGuideAction?
}

@MainActor
@Observable
final class PermissionGuideModel {
    private(set) var authorization: AuthorizationSnapshot
    private(set) var presentationState: RestrictionPresentationState
    private(set) var selectedScreenKind: PermissionGuideScreenKind?
    private(set) var alwaysLocationRequestWasDeclined = false
    let presentationMode: PermissionGuidePresentationMode

    init(
        authorization: AuthorizationSnapshot,
        presentationState: RestrictionPresentationState,
        initialScreenKind: PermissionGuideScreenKind? = nil,
        presentationMode: PermissionGuidePresentationMode? = nil
    ) {
        self.authorization = authorization
        self.presentationState = presentationState
        self.presentationMode = presentationMode
            ?? Self.inferredPresentationMode(
                authorization: authorization,
                initialScreenKind: initialScreenKind
            )
        selectedScreenKind = initialScreenKind
            ?? Self.recommendedScreenKind(
                authorization: authorization,
                presentationState: presentationState,
                presentationMode: self.presentationMode
            )
    }

    var isPresented: Bool { selectedScreenKind != nil }

    var missingRequiredPermissions: Set<RequiredPermission> {
        var permissions: Set<RequiredPermission> = []
        if authorization.familyControls != .approved {
            permissions.insert(.familyControls)
        }
        if authorization.locationAuthorization != .always {
            permissions.insert(.alwaysLocation)
        }
        if authorization.locationAccuracy != .full {
            permissions.insert(.fullAccuracy)
        }
        return permissions
    }

    var capabilityItems: [PermissionGuideCapabilityItem] {
        PermissionGuideCapability.allCases.map(makeCapabilityItem)
    }

    var currentScreen: PermissionGuideScreenState? {
        selectedScreenKind.map(makeScreen)
    }

    func advancePermissionSetup() {
        selectedScreenKind = switch selectedScreenKind {
        case .overview: .familyControls
        case .familyControls: .location
        case .location: .backgroundRefresh
        case .backgroundRefresh: nil
        case .locationUnavailable, .none: selectedScreenKind
        }
    }

    func select(_ screenKind: PermissionGuideScreenKind) {
        selectedScreenKind = screenKind
    }

    func showOverview() {
        selectedScreenKind = .overview
    }

    func dismiss() {
        selectedScreenKind = nil
    }

    func update(
        authorization: AuthorizationSnapshot,
        presentationState: RestrictionPresentationState,
        requestedAction: PermissionGuideAction? = nil
    ) {
        let previousAuthorization = self.authorization
        let previousScreenKind = selectedScreenKind
        self.authorization = authorization
        self.presentationState = presentationState
        if requestedAction == .requestAlwaysLocationAuthorization {
            alwaysLocationRequestWasDeclined = authorization.locationAuthorization != .always
        } else if authorization.locationAuthorization == .always {
            alwaysLocationRequestWasDeclined = false
        }

        if transitionAfterAuthorizationChange(
            from: previousAuthorization,
            on: previousScreenKind
        ) {
            return
        }

        let recommended = Self.recommendedScreenKind(
            authorization: authorization,
            presentationState: presentationState,
            presentationMode: presentationMode
        )

        if presentationMode == .recovery {
            selectedScreenKind = recommended
        } else if selectedScreenIsLocationUnavailable {
            selectedScreenKind = recommended
        }
    }

    private func transitionAfterAuthorizationChange(
        from previousAuthorization: AuthorizationSnapshot,
        on screenKind: PermissionGuideScreenKind?
    ) -> Bool {
        switch screenKind {
        case .familyControls:
            guard
                previousAuthorization.familyControls != .approved,
                authorization.familyControls == .approved
            else {
                return false
            }
            selectedScreenKind = presentationMode == .onboarding ? .location : nil
            return true

        case .location:
            let wasReady = Self.locationIsReady(previousAuthorization)
            let isReady = Self.locationIsReady(authorization)
            guard !wasReady, isReady else {
                return false
            }
            selectedScreenKind = presentationMode == .onboarding
                ? .backgroundRefresh
                : nil
            return true

        case .overview, .backgroundRefresh, .locationUnavailable, .none:
            return false
        }
    }

    private static func locationIsReady(
        _ authorization: AuthorizationSnapshot
    ) -> Bool {
        authorization.locationAuthorization == .always
            && authorization.locationAccuracy == .full
    }

    private var selectedScreenIsLocationUnavailable: Bool {
        if case .some(.locationUnavailable) = selectedScreenKind {
            return true
        }
        return false
    }

    private static func recommendedScreenKind(
        authorization: AuthorizationSnapshot,
        presentationState: RestrictionPresentationState,
        presentationMode: PermissionGuidePresentationMode
    ) -> PermissionGuideScreenKind? {
        if presentationMode == .onboarding {
            return .overview
        }

        if authorization.familyControls == .denied {
            return .familyControls
        }

        let locationRequiresRecovery: Bool = switch authorization.locationAuthorization {
        case .whenInUse, .denied, .restricted:
            true
        case .always, .notDetermined:
            false
        }
        if locationRequiresRecovery || authorization.locationAccuracy == .reduced {
            return .location
        }

        if case .locationUnavailable(let isRestrictionApplied) = presentationState {
            return .locationUnavailable(isRestrictionApplied: isRestrictionApplied)
        }
        return nil
    }

    private static func inferredPresentationMode(
        authorization: AuthorizationSnapshot,
        initialScreenKind: PermissionGuideScreenKind?
    ) -> PermissionGuidePresentationMode {
        if initialScreenKind == .overview
            || authorization.familyControls == .notDetermined
            || authorization.locationAuthorization == .notDetermined {
            return .onboarding
        }
        return .recovery
    }

    private func makeCapabilityItem(
        _ capability: PermissionGuideCapability
    ) -> PermissionGuideCapabilityItem {
        switch capability {
        case .familyControls:
            return PermissionGuideCapabilityItem(
                capability: capability,
                status: authorization.familyControls == .approved ? .ready : .actionRequired,
                cause: AppLocalizedCopy.string("선택한 앱에 사용 제한 화면을 적용하는 데 필요해요."),
                recovery: authorization.familyControls == .approved
                    ? AppLocalizedCopy.string("승인됨")
                    : AppLocalizedCopy.string("개인용 권한을 다시 승인한 뒤 제한할 앱을 다시 선택해 주세요.")
            )
        case .alwaysLocation:
            return PermissionGuideCapabilityItem(
                capability: capability,
                status: authorization.locationAuthorization == .always ? .ready : .actionRequired,
                cause: AppLocalizedCopy.string("나서 앱이 열려 있지 않을 때도 설정한 장소를 확인하는 데 필요해요."),
                recovery: authorization.locationAuthorization == .always
                    ? AppLocalizedCopy.string("항상 허용됨")
                    : AppLocalizedCopy.string("설정에서 위치 접근을 ‘항상 허용’으로 바꿔 주세요.")
            )
        case .fullAccuracy:
            return PermissionGuideCapabilityItem(
                capability: capability,
                status: authorization.locationAccuracy == .full ? .ready : .actionRequired,
                cause: AppLocalizedCopy.string("설정한 반경의 안과 밖을 안전하게 판단하는 데 필요해요."),
                recovery: authorization.locationAccuracy == .full
                    ? AppLocalizedCopy.string("정확한 위치 사용 중")
                    : AppLocalizedCopy.string("설정에서 ‘정확한 위치’를 켜 주세요.")
            )
        case .backgroundRefresh:
            return PermissionGuideCapabilityItem(
                capability: capability,
                status: authorization.backgroundRefresh == .available ? .ready : .limited,
                cause: AppLocalizedCopy.string("앱이 닫힌 동안 상태 복구가 지연되지 않도록 도와줘요."),
                recovery: authorization.backgroundRefresh == .available
                    ? AppLocalizedCopy.string("사용 가능")
                    : AppLocalizedCopy.string("설정과 저전력 모드를 확인해 주세요.")
            )
        }
    }

    private func makeScreen(_ kind: PermissionGuideScreenKind) -> PermissionGuideScreenState {
        switch kind {
        case .overview:
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "PERMISSION CHECK",
                title: AppLocalizedCopy.string("원활한 사용을 위해 아래 권한이 필요해요"),
                message: AppLocalizedCopy.string("필요한 항목을 확인하면 자동 제한 상태를 안전하게 다시 평가해요."),
                capabilityItems: capabilityItems,
                primaryAction: .next,
                secondaryAction: nil,
                isPrimaryActionEnabled: true,
                automaticAction: nil
            )
        case .familyControls:
            let action: PermissionGuideAction
            switch authorization.familyControls {
            case .notDetermined:
                action = .requestFamilyControlsAuthorization
            case .approved:
                action = .next
            case .denied:
                action = .openSettings
            }
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "SCREEN TIME ACCESS",
                title: AppLocalizedCopy.string("앱 사용 제한 권한이 필요해요"),
                message: AppLocalizedCopy.string("내용을 확인한 뒤 아래 버튼을 눌러 주세요."),
                capabilityItems: [makeCapabilityItem(.familyControls)],
                primaryAction: action,
                secondaryAction: nil,
                isPrimaryActionEnabled: true,
                automaticAction: nil
            )
        case .location:
            let action: PermissionGuideAction = switch authorization.locationAuthorization {
            case .notDetermined:
                .requestLocationAuthorization
            case .whenInUse
                where authorization.locationAccuracy == .full
                    && !alwaysLocationRequestWasDeclined:
                .requestAlwaysLocationAuthorization
            case .always where authorization.locationAccuracy == .full:
                .next
            case .whenInUse, .always, .denied, .restricted:
                .openSettings
            }
            let isWhenInUseRequest = action == .requestLocationAuthorization
            let isAlwaysRequest = action == .requestAlwaysLocationAuthorization
            let message: String
            if isWhenInUseRequest {
                message = AppLocalizedCopy.string("정확한 위치를 ‘켬’으로 설정한 뒤, ‘앱을 사용하는 동안 허용’을 눌러 주세요.")
            } else if authorization.locationAuthorization == .whenInUse
                && alwaysLocationRequestWasDeclined
            {
                message = AppLocalizedCopy.string("‘한 번만 허용’을 선택했거나 ‘항상 허용’으로 변경하지 않았다면, 설정에서 위치 접근을 ‘항상’으로 바꿔 주세요.")
            } else {
                message = AppLocalizedCopy.string("앱이 닫혀 있어도 규칙을 자동으로 적용하거나 해제하려면 ‘항상 허용으로 변경’을 눌러주세요.")
            }
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: isAlwaysRequest ? "LOCATION ACCESS · ALWAYS" : "LOCATION ACCESS",
                title: isAlwaysRequest
                    ? AppLocalizedCopy.string("항상 위치 접근 권한이 필요해요")
                    : AppLocalizedCopy.string("정확한 위치 접근 권한이 필요해요"),
                message: message,
                capabilityItems: [
                    makeCapabilityItem(.alwaysLocation),
                    makeCapabilityItem(.fullAccuracy),
                ],
                primaryAction: action,
                secondaryAction: nil,
                isPrimaryActionEnabled: true,
                automaticAction: nil
            )
        case .backgroundRefresh:
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "BACKGROUND REFRESH",
                title: AppLocalizedCopy.string("백그라운드 새로 고침을 확인해 주세요"),
                message: AppLocalizedCopy.string("Background App Refresh가 제한되면 앱을 다시 열기 전까지 상태 복구가 늦어질 수 있어요. 저전력 모드에서도 시스템이 실행을 제한할 수 있어요."),
                capabilityItems: [makeCapabilityItem(.backgroundRefresh)],
                primaryAction: presentationMode == .onboarding
                    ? .completeOnboarding
                    : .confirm,
                secondaryAction: nil,
                isPrimaryActionEnabled: true,
                automaticAction: nil
            )
        case .locationUnavailable(let isRestrictionApplied):
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "LOCATION UNAVAILABLE",
                title: isRestrictionApplied
                    ? AppLocalizedCopy.string("위치를 확인할 수 없어 제한이 유지돼요")
                    : AppLocalizedCopy.string("현재 위치를 확인할 수 없어요"),
                message: isRestrictionApplied
                    ? AppLocalizedCopy.string("위치 실패만으로 제한을 해제하지 않고 현재 제한을 유지해요. 설정한 시간이 끝나면 위치와 관계없이 자동으로 해제돼요.")
                    : AppLocalizedCopy.string("위치를 확인할 수 없어 새 제한을 시작하지 않아요. 권한과 정확한 위치를 확인한 뒤 다시 시도해 주세요."),
                capabilityItems: [],
                primaryAction: .openSettings,
                secondaryAction: .retryLocation,
                isPrimaryActionEnabled: true,
                automaticAction: nil
            )
        }
    }
}
