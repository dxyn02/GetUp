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

enum PermissionGuideAction: Equatable, Sendable {
    case beginPermissionSetup
    case requestFamilyControlsAuthorization
    case openSettings
    case retryLocation
    case later
}

enum ApplicationReselectionState: Equatable, Sendable {
    case notRequired
    case requiredAfterFamilyControlsRecovery
    case completed
}

struct PermissionGuideScreenState: Equatable, Sendable {
    let kind: PermissionGuideScreenKind
    let eyebrow: String
    let title: String
    let message: String
    let capabilityItems: [PermissionGuideCapabilityItem]
    let primaryAction: PermissionGuideAction
    let secondaryAction: PermissionGuideAction?
}

@MainActor
@Observable
final class PermissionGuideModel {
    private(set) var authorization: AuthorizationSnapshot
    private(set) var presentationState: RestrictionPresentationState
    private(set) var selectedScreenKind: PermissionGuideScreenKind?
    private(set) var applicationReselectionState: ApplicationReselectionState

    init(
        authorization: AuthorizationSnapshot,
        presentationState: RestrictionPresentationState,
        initialScreenKind: PermissionGuideScreenKind? = nil
    ) {
        self.authorization = authorization
        self.presentationState = presentationState
        applicationReselectionState = authorization.familyControls == .approved
            ? .notRequired
            : .requiredAfterFamilyControlsRecovery
        selectedScreenKind = initialScreenKind
            ?? Self.recommendedScreenKind(
                authorization: authorization,
                presentationState: presentationState,
                requiresApplicationReselection: authorization.familyControls != .approved
            )
    }

    var isPresented: Bool { selectedScreenKind != nil }

    var requiresApplicationReselection: Bool {
        applicationReselectionState == .requiredAfterFamilyControlsRecovery
    }

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

    func beginPermissionSetup() {
        selectedScreenKind = firstRecoveryScreenKind ?? .overview
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
        if self.authorization.familyControls != .approved,
           authorization.familyControls == .approved {
            applicationReselectionState = .completed
        }
        if self.authorization.familyControls == .approved,
           authorization.familyControls != .approved {
            applicationReselectionState = .requiredAfterFamilyControlsRecovery
        }

        self.authorization = authorization
        self.presentationState = presentationState

        let recommended = Self.recommendedScreenKind(
            authorization: authorization,
            presentationState: presentationState,
            requiresApplicationReselection: requiresApplicationReselection
        )
        if selectedScreenKind == nil
            || selectedScreenIsResolved
            || selectedScreenIsLocationUnavailable {
            selectedScreenKind = recommended
        }
    }

    func markApplicationsReselected() {
        guard authorization.familyControls == .approved else {
            return
        }
        applicationReselectionState = .completed
        if selectedScreenKind == .familyControls {
            selectedScreenKind = Self.recommendedScreenKind(
                authorization: authorization,
                presentationState: presentationState,
                requiresApplicationReselection: false
            )
        }
    }

    private var firstRecoveryScreenKind: PermissionGuideScreenKind? {
        if authorization.familyControls != .approved || requiresApplicationReselection {
            return .familyControls
        }
        if authorization.locationAuthorization != .always
            || authorization.locationAccuracy != .full {
            return .location
        }
        if authorization.backgroundRefresh != .available {
            return .backgroundRefresh
        }
        return nil
    }

    private var selectedScreenIsResolved: Bool {
        switch selectedScreenKind {
        case .familyControls:
            authorization.familyControls == .approved && !requiresApplicationReselection
        case .location:
            authorization.locationAuthorization == .always
                && authorization.locationAccuracy == .full
        case .backgroundRefresh:
            authorization.backgroundRefresh == .available
        case .locationUnavailable:
            if case .locationUnavailable = presentationState { false } else { true }
        case .overview:
            Self.recommendedScreenKind(
                authorization: authorization,
                presentationState: presentationState,
                requiresApplicationReselection: requiresApplicationReselection
            ) == nil
        case .none:
            false
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
        requiresApplicationReselection: Bool
    ) -> PermissionGuideScreenKind? {
        if case .locationUnavailable(let isRestrictionApplied) = presentationState {
            return .locationUnavailable(isRestrictionApplied: isRestrictionApplied)
        }
        if case .permissionRequired = presentationState {
            return .overview
        }
        if requiresApplicationReselection
            || authorization.familyControls != .approved
            || authorization.locationAuthorization != .always
            || authorization.locationAccuracy != .full
            || authorization.backgroundRefresh != .available {
            return .overview
        }
        return nil
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
            PermissionGuideScreenState(
                kind: kind,
                eyebrow: "PERMISSION REQUIRED",
                title: "원활한 사용을 위해 아래 권한이 필요해요",
                message: "필요한 항목을 확인하면 자동 제한 상태를 안전하게 다시 평가해요.",
                capabilityItems: capabilityItems,
                primaryAction: .beginPermissionSetup,
                secondaryAction: nil
            )
        case .familyControls:
            PermissionGuideScreenState(
                kind: kind,
                eyebrow: "APP RESTRICTION",
                title: "앱 사용 제한 권한이 필요해요",
                message: "개인용 앱 사용 제한을 승인해 주세요. 제한할 앱은 규칙 편집 화면의 시스템 선택기에서 선택할 수 있어요.",
                capabilityItems: [makeCapabilityItem(.familyControls)],
                primaryAction: .requestFamilyControlsAuthorization,
                secondaryAction: nil
            )
        case .location:
            PermissionGuideScreenState(
                kind: kind,
                eyebrow: "LOCATION PERMISSION",
                title: "정확한 위치 접근 권한이 필요해요",
                message: "설정에서 위치 접근을 ‘항상 허용’으로 바꾸고 ‘정확한 위치’를 켜 주세요. 확인할 수 없는 위치는 추정하지 않아요.",
                capabilityItems: [
                    makeCapabilityItem(.alwaysLocation),
                    makeCapabilityItem(.fullAccuracy),
                ],
                primaryAction: .openSettings,
                secondaryAction: .later
            )
        case .backgroundRefresh:
            PermissionGuideScreenState(
                kind: kind,
                eyebrow: "BACKGROUND REFRESH",
                title: "백그라운드 새로 고침을 확인해 주세요",
                message: "Background App Refresh가 제한되면 앱을 다시 열기 전까지 상태 복구가 늦어질 수 있어요. 저전력 모드에서도 시스템이 실행을 제한할 수 있어요.",
                capabilityItems: [makeCapabilityItem(.backgroundRefresh)],
                primaryAction: .openSettings,
                secondaryAction: .later
            )
        case .locationUnavailable(let isRestrictionApplied):
            PermissionGuideScreenState(
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
                secondaryAction: .retryLocation
            )
        }
    }
}
