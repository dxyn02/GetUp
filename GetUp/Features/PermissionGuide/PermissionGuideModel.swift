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
        case .familyControls: "앱 사용 제한"
        case .alwaysLocation: "위치 접근"
        case .fullAccuracy: "정확한 위치"
        case .backgroundRefresh: "Background App Refresh"
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
    private static let liveKey = "permissionOnboarding.hasBeenPresented.v1"

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = Self.liveKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    var hasBeenPresented: Bool {
        defaults.bool(forKey: key)
    }

    func markPresented() {
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
        let presentationMode: PermissionGuidePresentationMode
        if onboardingStateStore.hasBeenPresented {
            presentationMode = .recovery
        } else {
            onboardingStateStore.markPresented()
            let isFreshAuthorizationState =
                authorization.familyControls == .notDetermined
                && authorization.locationAuthorization == .notDetermined
            presentationMode = isFreshAuthorizationState ? .onboarding : .recovery
        }

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
    case requestFamilyControlsAuthorization
    case requestLocationAuthorization
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
        presentationState: RestrictionPresentationState
    ) {
        self.authorization = authorization
        self.presentationState = presentationState

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
                cause: "선택한 앱에 사용 제한 화면을 적용하는 데 필요해요.",
                recovery: authorization.familyControls == .approved
                    ? "승인됨"
                    : "개인용 권한을 다시 승인한 뒤 제한할 앱을 다시 선택해 주세요."
            )
        case .alwaysLocation:
            return PermissionGuideCapabilityItem(
                capability: capability,
                status: authorization.locationAuthorization == .always ? .ready : .actionRequired,
                cause: "GetUp이 열려 있지 않을 때도 설정한 장소를 확인하는 데 필요해요.",
                recovery: authorization.locationAuthorization == .always
                    ? "항상 허용됨"
                    : "설정에서 위치 접근을 ‘항상 허용’으로 바꿔 주세요."
            )
        case .fullAccuracy:
            return PermissionGuideCapabilityItem(
                capability: capability,
                status: authorization.locationAccuracy == .full ? .ready : .actionRequired,
                cause: "설정한 반경의 안과 밖을 안전하게 판단하는 데 필요해요.",
                recovery: authorization.locationAccuracy == .full
                    ? "정확한 위치 사용 중"
                    : "설정에서 ‘정확한 위치’를 켜 주세요."
            )
        case .backgroundRefresh:
            return PermissionGuideCapabilityItem(
                capability: capability,
                status: authorization.backgroundRefresh == .available ? .ready : .limited,
                cause: "앱이 닫힌 동안 상태 복구가 지연되지 않도록 도와줘요.",
                recovery: authorization.backgroundRefresh == .available
                    ? "사용 가능"
                    : "설정과 저전력 모드를 확인해 주세요."
            )
        }
    }

    private func makeScreen(_ kind: PermissionGuideScreenKind) -> PermissionGuideScreenState {
        switch kind {
        case .overview:
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "PERMISSION REQUIRED",
                title: "원활한 사용을 위해 아래 권한이 필요해요",
                message: "필요한 항목을 확인하면 자동 제한 상태를 안전하게 다시 평가해요.",
                capabilityItems: capabilityItems,
                primaryAction: .next,
                secondaryAction: nil,
                isPrimaryActionEnabled: true,
                automaticAction: nil
            )
        case .familyControls:
            let action: PermissionGuideAction
            let isEnabled: Bool
            let automaticAction: PermissionGuideAction?
            switch authorization.familyControls {
            case .notDetermined:
                action = .next
                isEnabled = false
                automaticAction = .requestFamilyControlsAuthorization
            case .approved:
                action = .next
                isEnabled = true
                automaticAction = nil
            case .denied:
                action = .openSettings
                isEnabled = true
                automaticAction = nil
            }
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "APP RESTRICTION",
                title: "앱 사용 제한 권한이 필요해요",
                message: "개인용 앱 사용 제한을 승인해 주세요. 제한할 앱은 규칙 편집 화면의 시스템 선택기에서 선택할 수 있어요.",
                capabilityItems: [makeCapabilityItem(.familyControls)],
                primaryAction: action,
                secondaryAction: nil,
                isPrimaryActionEnabled: isEnabled,
                automaticAction: automaticAction
            )
        case .location:
            let isNotDetermined = authorization.locationAuthorization == .notDetermined
            let isApproved = authorization.locationAuthorization == .always
                && authorization.locationAccuracy == .full
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "LOCATION PERMISSION",
                title: "정확한 위치 접근 권한이 필요해요",
                message: "처음 요청에서는 ‘앱을 사용하는 동안 허용’을 선택해 주세요. 이후 설정에서 위치 접근을 ‘항상 허용’으로 바꾸고 ‘정확한 위치’를 켜야 자동 제한이 동작해요.",
                capabilityItems: [
                    makeCapabilityItem(.alwaysLocation),
                    makeCapabilityItem(.fullAccuracy),
                ],
                primaryAction: isApproved || isNotDetermined ? .next : .openSettings,
                secondaryAction: nil,
                isPrimaryActionEnabled: !isNotDetermined,
                automaticAction: isNotDetermined ? .requestLocationAuthorization : nil
            )
        case .backgroundRefresh:
            let isApproved = authorization.backgroundRefresh == .available
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "BACKGROUND REFRESH",
                title: "백그라운드 새로 고침을 확인해 주세요",
                message: "Background App Refresh가 제한되면 앱을 다시 열기 전까지 상태 복구가 늦어질 수 있어요. 저전력 모드에서도 시스템이 실행을 제한할 수 있어요.",
                capabilityItems: [makeCapabilityItem(.backgroundRefresh)],
                primaryAction: isApproved ? .next : .confirm,
                secondaryAction: nil,
                isPrimaryActionEnabled: true,
                automaticAction: nil
            )
        case .locationUnavailable(let isRestrictionApplied):
            return PermissionGuideScreenState(
                kind: kind,
                eyebrow: "LOCATION UNAVAILABLE",
                title: isRestrictionApplied
                    ? "위치를 확인할 수 없어 제한이 유지돼요"
                    : "현재 위치를 확인할 수 없어요",
                message: isRestrictionApplied
                    ? "위치 실패만으로 제한을 해제하지 않고 현재 제한을 유지해요. 설정한 시간이 끝나면 위치와 관계없이 자동으로 해제돼요."
                    : "위치를 확인할 수 없어 새 제한을 시작하지 않아요. 권한과 정확한 위치를 확인한 뒤 다시 시도해 주세요.",
                capabilityItems: [],
                primaryAction: .openSettings,
                secondaryAction: .retryLocation,
                isPrimaryActionEnabled: true,
                automaticAction: nil
            )
        }
    }
}
