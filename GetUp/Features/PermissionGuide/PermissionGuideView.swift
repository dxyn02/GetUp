import SwiftUI

struct PermissionGuideUpdate: Equatable, Sendable {
    let authorization: AuthorizationSnapshot
    let presentationState: RestrictionPresentationState
}

@MainActor
struct PermissionGuideView: View {
    typealias ActionHandler = @MainActor (
        PermissionGuideAction
    ) async -> PermissionGuideUpdate?

    @Bindable private var model: PermissionGuideModel
    private let onAction: ActionHandler

    @State private var isPerformingAction = false
    @State private var performedAutomaticActions: Set<PermissionGuideAction> = []
    @AccessibilityFocusState private var isHeadingFocused: Bool

    init(
        model: PermissionGuideModel,
        onAction: @escaping ActionHandler = { _ in nil }
    ) {
        self.model = model
        self.onAction = onAction
    }

    var body: some View {
        Group {
            if let screen = model.currentScreen {
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            header(screen)
                            detail(for: screen)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 24)
                        .padding(.bottom, 24)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    actions(screen)
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("permissionGuide.screen")
                .onAppear { isHeadingFocused = true }
                .onChange(of: screen.kind) { _, _ in
                    isHeadingFocused = true
                }
                .task(id: screen.automaticAction) {
                    guard
                        let action = screen.automaticAction,
                        performedAutomaticActions.insert(action).inserted
                    else {
                        return
                    }
                    await performAsynchronousAction(action)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HomeColor.background.ignoresSafeArea())
        .foregroundStyle(HomeColor.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func header(_ screen: PermissionGuideScreenState) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(eyebrow(for: screen.kind))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(eyebrowColor(for: screen.kind))

            Text(screen.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityFocused($isHeadingFocused)

            Text(subtitle(for: screen))
                .font(.subheadline)
                .foregroundStyle(HomeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private func detail(for screen: PermissionGuideScreenState) -> some View {
        switch screen.kind {
        case .overview:
            capabilityList(screen.capabilityItems)
        case .familyControls:
            familyControlsPermissionMockup
        case .location:
            locationSettings
        case .backgroundRefresh:
            backgroundRefreshSettings
        case .locationUnavailable(let isRestrictionApplied):
            unavailableLocationState(isRestrictionApplied: isRestrictionApplied)
        }
    }

    private var familyControlsPermissionMockup: some View {
        systemMockupCard(
            icon: "hourglass",
            title: "화면 사용 시간 접근",
            accessibilityIdentifier: "permissionGuide.mockup.familyControls",
            accessibilityLabel: "화면 사용 시간 권한 팝업 예시. Face ID로 허용을 선택해 주세요."
        ) {
            Text("‘GetUp’이 화면 사용 시간에 접근하도록 허용할까요?")
                .font(.headline)

            Text("선택한 앱을 제한하려면 화면 사용 시간 접근이 필요해요.")
                .font(.footnote)
                .foregroundStyle(HomeColor.textSecondary)

            mockupOption("Face ID로 허용", isHighlighted: true)
            mockupOption("허용 안 함", isHighlighted: false)
        }
    }

    private func capabilityList(
        _ items: [PermissionGuideCapabilityItem]
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.icon) \(overviewTitle(for: item.capability))")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(overviewDescription(for: item.capability))
                        .font(.subheadline)
                        .foregroundStyle(HomeColor.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(HomeColor.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("permissionGuide.permissionList")
    }

    private var locationSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            if model.authorization.locationAuthorization == .notDetermined {
                locationPermissionAlertMockup
            } else {
                locationSettingsMockup
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("위치 접근 · 항상 허용")
                    .fontWeight(.semibold)
                Text("설정  ›  개인정보 보호 및 보안  ›  위치 서비스  ›  GetUp")
                    .foregroundStyle(HomeColor.textSecondary)
            }

            Text("최초 권한 팝업에서는 ‘앱을 사용하는 동안 허용’을 선택해 주세요.")
                .foregroundStyle(HomeColor.textSecondary)

            Text("위 경로에서 \(Text("‘항상 허용’으로 변경해 주세요.").foregroundColor(HomeColor.accent).fontWeight(.semibold))")
            .foregroundStyle(HomeColor.textSecondary)
            .accessibilityIdentifier("permissionGuide.location.alwaysInstruction")

            VStack(alignment: .leading, spacing: 4) {
                Text("정확한 위치 · 켬")
                    .fontWeight(.semibold)
                Text("‘정확한 위치’를 켜 주세요.")
                    .foregroundStyle(HomeColor.accent)
                    .fontWeight(.semibold)
                    .accessibilityIdentifier("permissionGuide.location.accuracyInstruction")
            }

            Text("‘대략적인 위치’에서는 위치만으로 새 제한을 적용하거나 기존 제한을 해제하지 않아요.")
                .font(.footnote)
                .foregroundStyle(HomeColor.textSecondary)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(HomeColor.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private var locationPermissionAlertMockup: some View {
        systemMockupCard(
            icon: "location.fill",
            title: "위치 접근 허용",
            accessibilityIdentifier: "permissionGuide.mockup.locationPrompt",
            accessibilityLabel: "위치 권한 팝업 예시. 앱을 사용하는 동안 허용을 선택해 주세요."
        ) {
            Text("‘GetUp’이 사용자의 위치를 사용하도록 허용할까요?")
                .font(.headline)

            mockupOption("한 번 허용", isHighlighted: false)
            mockupOption("앱을 사용하는 동안 허용", isHighlighted: true)
            mockupOption("허용 안 함", isHighlighted: false)
        }
    }

    private var locationSettingsMockup: some View {
        systemMockupCard(
            icon: "gearshape.fill",
            title: "설정 · GetUp · 위치",
            accessibilityIdentifier: "permissionGuide.mockup.locationSettings",
            accessibilityLabel: "위치 설정 예시. 위치 접근은 항상, 정확한 위치는 켬으로 설정해 주세요."
        ) {
            mockupSettingRow(
                title: "위치 접근",
                value: "항상",
                isHighlighted: true
            )
            mockupToggleRow(title: "정확한 위치", isOn: true)
        }
    }

    private var backgroundRefreshSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            systemMockupCard(
                icon: "arrow.clockwise",
                title: "설정 · 일반",
                accessibilityIdentifier: "permissionGuide.mockup.backgroundRefresh",
                accessibilityLabel: "백그라운드 앱 새로 고침 설정 예시. 기능과 GetUp을 켜 주세요."
            ) {
                mockupSettingRow(
                    title: "백그라운드 앱 새로 고침",
                    value: "켬",
                    isHighlighted: true
                )
                mockupToggleRow(title: "GetUp", isOn: true)
            }

            Text("설정  ›  일반  ›  백그라운드 앱 새로 고침")
                .fontWeight(.semibold)
            Text("GetUp 사용 가능 상태를 확인해 주세요. 저전력 모드에서는 시스템이 동작을 제한할 수 있어요.")
                .foregroundStyle(HomeColor.textSecondary)
            Text("앱별 설정에서는 변경할 수 없어요. 위의 시스템 경로에서 직접 켜 주세요.")
                .foregroundStyle(HomeColor.textSecondary)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(HomeColor.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private func systemMockupCard<Content: View>(
        icon: String,
        title: String,
        accessibilityIdentifier: String,
        accessibilityLabel: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(HomeColor.accent)
                    .frame(width: 32, height: 32)
                    .background(HomeColor.accent.opacity(0.14), in: .rect(cornerRadius: 9))

                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .stroke(HomeColor.textTertiary.opacity(0.3), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
    }

    private func mockupOption(
        _ title: String,
        isHighlighted: Bool
    ) -> some View {
        Text(title)
            .font(.subheadline)
            .fontWeight(isHighlighted ? .bold : .medium)
            .foregroundStyle(
                isHighlighted ? HomeColor.background : HomeColor.textSecondary
            )
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                isHighlighted ? HomeColor.accent : HomeColor.disabled.opacity(0.45),
                in: .rect(cornerRadius: 13)
            )
    }

    private func mockupSettingRow(
        title: String,
        value: String,
        isHighlighted: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            Text(value)
                .fontWeight(.bold)
                .foregroundStyle(isHighlighted ? HomeColor.accent : HomeColor.textSecondary)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(HomeColor.textTertiary)
        }
        .font(.subheadline)
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(HomeColor.surface, in: .rect(cornerRadius: 13))
    }

    private func mockupToggleRow(
        title: String,
        isOn: Bool
    ) -> some View {
        HStack(spacing: 12) {
            Text(title)
            Spacer(minLength: 12)
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(isOn ? HomeColor.accent : HomeColor.disabled)
                    .frame(width: 48, height: 28)
                Circle()
                    .fill(isOn ? HomeColor.background : HomeColor.textSecondary)
                    .frame(width: 22, height: 22)
                    .padding(3)
            }
        }
        .font(.subheadline)
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .background(HomeColor.surface, in: .rect(cornerRadius: 13))
    }

    private func unavailableLocationState(
        isRestrictionApplied: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(
                isRestrictionApplied
                    ? "현재 상태 · 제한 활성 유지"
                    : "현재 상태 · 제한 비활성 유지"
            )
            .font(.headline)

            if isRestrictionApplied {
                Text("위치 오류만으로 제한을 해제하지 않아요.")
                Text("설정한 시간이 끝나면 위치와 관계없이 자동으로 해제해요.")
            } else {
                Text("확인할 항목")
                Text("위치 접근 권한\n정확한 위치 설정\n반경 경계와 오차 범위 중첩")
            }

            Text("신뢰 가능한 위치가 확인되면 조건을 다시 평가해요.")
                .font(.footnote)
        }
        .foregroundStyle(HomeColor.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 20)
        .background(HomeColor.surface, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .contain)
    }

    private func actions(_ screen: PermissionGuideScreenState) -> some View {
        VStack(spacing: 20) {
            if let secondaryAction = screen.secondaryAction {
                actionButton(
                    secondaryAction,
                    prominence: .secondary,
                    isEnabled: true
                )
            }
            actionButton(
                screen.primaryAction,
                prominence: .primary,
                isEnabled: screen.isPrimaryActionEnabled
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(HomeColor.background)
    }

    private enum ActionProminence {
        case primary
        case secondary
    }

    private func actionButton(
        _ action: PermissionGuideAction,
        prominence: ActionProminence,
        isEnabled: Bool
    ) -> some View {
        Button {
            perform(action)
        } label: {
            Group {
                if isPerformingAction {
                    ProgressView()
                        .tint(prominence == .primary ? HomeColor.background : HomeColor.textPrimary)
                } else {
                    Text(label(for: action))
                        .font(.subheadline)
                        .fontWeight(.bold)
                }
            }
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundStyle(
                foregroundColor(
                    prominence: prominence,
                    isEnabled: isEnabled
                )
            )
            .background(
                backgroundColor(
                    prominence: prominence,
                    isEnabled: isEnabled
                ),
                in: .rect(cornerRadius: 18)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 56)
        .contentShape(.rect)
        .disabled(isPerformingAction || !isEnabled)
        .accessibilityLabel(accessibilityLabel(for: action))
        .accessibilityIdentifier(identifier(for: action))
        .accessibilityHint(hint(for: action))
    }

    private func perform(_ action: PermissionGuideAction) {
        switch action {
        case .next:
            model.advancePermissionSetup()
        case .confirm:
            model.dismiss()
        case .requestFamilyControlsAuthorization,
             .requestLocationAuthorization,
             .openSettings,
             .retryLocation:
            Task { @MainActor in
                await performAsynchronousAction(action)
            }
        }
    }

    private func performAsynchronousAction(_ action: PermissionGuideAction) async {
        isPerformingAction = true
        let update = await onAction(action)
        if let update {
            model.update(
                authorization: update.authorization,
                presentationState: update.presentationState
            )
        }
        isPerformingAction = false
    }

    private func eyebrow(for kind: PermissionGuideScreenKind) -> String {
        switch kind {
        case .overview: "PERMISSION CHECK"
        case .familyControls: "SCREEN TIME ACCESS"
        case .location: "LOCATION ACCESS"
        case .backgroundRefresh: "BACKGROUND REFRESH"
        case .locationUnavailable: "LOCATION UNAVAILABLE"
        }
    }

    private func eyebrowColor(for kind: PermissionGuideScreenKind) -> Color {
        if case .locationUnavailable = kind {
            return HomeColor.error
        }
        return HomeColor.accent
    }

    private func subtitle(for screen: PermissionGuideScreenState) -> String {
        switch screen.kind {
        case .overview:
            "필수 권한을 허용해야 규칙을 적용할 수 있어요."
        case .familyControls:
            "권한이 없으면 규칙을 적용하지 않아요."
        case .location:
            "설정된 위치에서 특정 거리를 벗어나면 제한이 풀려요."
        case .backgroundRefresh:
            "꺼져 있으면 앱이 닫힌 동안 권한·위치 상태 복구가 늦어질 수 있어요."
        case .locationUnavailable(let isRestrictionApplied):
            isRestrictionApplied
                ? "위치를 확인할 수 없어도 현재 제한을 유지해요."
                : "위치를 추정하지 않고 새 제한을 시작하지 않아요."
        }
    }

    private func overviewTitle(for capability: PermissionGuideCapability) -> String {
        switch capability {
        case .familyControls: "앱 사용 제한"
        case .alwaysLocation: "위치 접근 · 항상"
        case .fullAccuracy: "정확한 위치"
        case .backgroundRefresh: "Background App Refresh"
        }
    }

    private func overviewDescription(
        for capability: PermissionGuideCapability
    ) -> String {
        switch capability {
        case .familyControls: "선택한 앱을 제한하려면 필요"
        case .alwaysLocation: "앱이 닫혀 있어도 조건 확인"
        case .fullAccuracy: "반경 경계를 안전하게 판단"
        case .backgroundRefresh: "복구 가능 상태 확인"
        }
    }

    private func label(for action: PermissionGuideAction) -> String {
        switch action {
        case .next: "다음"
        case .confirm: "확인"
        case .requestFamilyControlsAuthorization: "권한 허용하기"
        case .requestLocationAuthorization: "위치 권한 허용하기"
        case .openSettings: "설정 열기"
        case .retryLocation: "위치 다시 확인"
        }
    }

    private func identifier(for action: PermissionGuideAction) -> String {
        switch action {
        case .next: "permissionGuide.next"
        case .confirm: "permissionGuide.confirm"
        case .requestFamilyControlsAuthorization:
            "permissionGuide.requestFamilyControlsAuthorization"
        case .requestLocationAuthorization:
            "permissionGuide.requestLocationAuthorization"
        case .openSettings: "permissionGuide.openSettings"
        case .retryLocation: "permissionGuide.retryLocation"
        }
    }

    private func accessibilityLabel(for action: PermissionGuideAction) -> String {
        label(for: action)
    }

    private func hint(for action: PermissionGuideAction) -> String {
        switch action {
        case .next: "다음 권한 안내로 이동합니다."
        case .confirm: "안내를 확인하고 닫습니다."
        case .requestFamilyControlsAuthorization:
            "앱 사용 제한을 위한 iOS 권한 요청을 표시합니다."
        case .requestLocationAuthorization:
            "위치 접근을 위한 iOS 권한 요청을 표시합니다."
        case .openSettings: "GetUp의 권한을 변경할 수 있는 시스템 설정을 엽니다."
        case .retryLocation: "현재 위치를 다시 확인하고 제한 상태를 재평가합니다."
        }
    }

    private func foregroundColor(
        prominence: ActionProminence,
        isEnabled: Bool
    ) -> Color {
        guard isEnabled else {
            return HomeColor.textTertiary
        }
        if prominence == .primary {
            return HomeColor.background
        }
        return HomeColor.textPrimary
    }

    private func backgroundColor(
        prominence: ActionProminence,
        isEnabled: Bool
    ) -> Color {
        guard isEnabled else {
            return HomeColor.disabled
        }
        if prominence == .primary {
            return HomeColor.accent
        }
        return HomeColor.surfaceElevated
    }
}
