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
                        VStack(alignment: .leading, spacing: 18) {
                            header(screen)
                            detail(for: screen)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 0)
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(HomeColor.background.ignoresSafeArea())
        .foregroundStyle(HomeColor.textPrimary)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }

    private func header(_ screen: PermissionGuideScreenState) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(screen.eyebrow)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(eyebrowColor(for: screen.kind))

            Text(screen.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("permissionGuide.title")
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
            familyControlsPermissionMockup(screen)
        case .location:
            locationSettings(screen)
        case .backgroundRefresh:
            backgroundRefreshSettings
        case .locationUnavailable(let isRestrictionApplied):
            unavailableLocationState(isRestrictionApplied: isRestrictionApplied)
        }
    }

    private func familyControlsPermissionMockup(
        _ screen: PermissionGuideScreenState
    ) -> some View {
        centeredPermissionPreview(
            minHeight: 484,
            hint: AppLocalizedCopy.string("↑ ‘계속’을 눌러 진행")
        ) {
            VStack(spacing: 0) {
                VStack(spacing: 14) {
                    Text("“나서”가 화면 사용 시간에\n접근하도록 허용할까요?")
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("permissionGuide.mockup.familyControlsTitle")

                    skeletonLines(widths: [269, 246, 258, 170])
                }
                .padding(.horizontal, 22)
                .padding(.top, 22)
                .padding(.bottom, 20)

                HStack(spacing: 1) {
                    permissionPreviewAction(
                        AppLocalizedCopy.string("계속"),
                        isHighlighted: true,
                        action: screen.primaryAction == .requestFamilyControlsAuthorization
                            ? .requestFamilyControlsAuthorization
                            : nil
                    )
                    permissionPreviewAction(
                        AppLocalizedCopy.string("허용 안 함"),
                        isHighlighted: false
                    )
                }
                .background(Color.white.opacity(0.16))
            }
            .permissionAlertSurface()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("화면 사용 시간 권한 팝업 예시. 계속을 누르면 실제 권한 요청이 열립니다.")
            .accessibilityIdentifier("permissionGuide.mockup.familyControls")
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

    @ViewBuilder
    private func locationSettings(
        _ screen: PermissionGuideScreenState
    ) -> some View {
        switch screen.primaryAction {
        case .requestLocationAuthorization:
            locationPermissionAlertMockup
        case .requestAlwaysLocationAuthorization:
            locationAlwaysPermissionAlertMockup
        default:
            VStack(alignment: .leading, spacing: 18) {
                locationSettingsMockup

                VStack(alignment: .leading, spacing: 4) {
                    Text("위치 접근 · 항상 허용")
                        .fontWeight(.semibold)
                    Text("설정  ›  개인정보 보호 및 보안  ›  위치 서비스  ›  나서")
                        .foregroundStyle(HomeColor.textSecondary)
                }

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
    }

    private var locationPermissionAlertMockup: some View {
        centeredPermissionPreview(
            minHeight: 521,
            hint: AppLocalizedCopy.string("↑ 지도 왼쪽 상단에서 ‘정확한 위치’를 켜주세요.")
        ) {
            VStack(spacing: 0) {
                locationPermissionPreviewHeader(
                    title: AppLocalizedCopy.string("“나서”가 사용자의\n위치를 사용하도록 허용할까요?")
                )

                ZStack(alignment: .topLeading) {
                    Image("LocationWhenInUsePreview")
                        .resizable()
                        .interpolation(.high)

                    Text(AppLocalizedCopy.string("정확한 위치: 켬"))
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(Color(red: 0, green: 0.48, blue: 1))
                        .padding(.horizontal, 16)
                        .frame(height: 26)
                        .background(.white, in: .capsule)
                        .padding(.leading, 9)
                        .padding(.top, 9)
                        .accessibilityIdentifier(
                            "permissionGuide.mockup.preciseLocationStatus"
                        )
                }
                .frame(width: 273, height: 167)
                .clipShape(.rect(cornerRadius: 17))

                VStack(spacing: 1) {
                    permissionPreviewAction(
                        AppLocalizedCopy.string("한 번 허용"),
                        isHighlighted: false
                    )
                    permissionPreviewAction(
                        AppLocalizedCopy.string("앱을 사용하는 동안 허용"),
                        isHighlighted: true,
                        action: .requestLocationAuthorization
                    )
                    permissionPreviewAction(
                        AppLocalizedCopy.string("허용 안 함"),
                        isHighlighted: false
                    )
                }
                .background(Color.white.opacity(0.16))
            }
            .permissionAlertSurface()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("위치 권한 팝업 예시. 정확한 위치를 켠 뒤 앱을 사용하는 동안 허용을 누르면 실제 권한 요청이 열립니다.")
            .accessibilityIdentifier("permissionGuide.mockup.locationPrompt")
        }
    }

    private var locationAlwaysPermissionAlertMockup: some View {
        centeredPermissionPreview(
            minHeight: 494,
            hint: AppLocalizedCopy.string("↑ ‘항상 허용으로 변경’을 눌러 주세요.")
        ) {
            VStack(spacing: 0) {
                locationPermissionPreviewHeader(
                    title: AppLocalizedCopy.string("“나서”가 사용자의\n위치를 항상 사용하도록\n허용할까요?")
                )

                Image("LocationAlwaysPreview")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 273, height: 167)
                    .clipShape(.rect(cornerRadius: 17))

                VStack(spacing: 1) {
                    permissionPreviewAction(
                        AppLocalizedCopy.string("앱 사용 중 허용 유지"),
                        isHighlighted: false
                    )
                    permissionPreviewAction(
                        AppLocalizedCopy.string("항상 허용으로 변경"),
                        isHighlighted: true,
                        action: .requestAlwaysLocationAuthorization
                    )
                }
                .background(Color.white.opacity(0.16))
            }
            .permissionAlertSurface()
            .accessibilityElement(children: .contain)
            .accessibilityLabel("항상 위치 권한 팝업 예시. 항상 허용으로 변경을 누르면 실제 권한 요청이 열립니다.")
            .accessibilityIdentifier("permissionGuide.mockup.locationAlwaysPrompt")
        }
    }

    private func locationPermissionPreviewHeader(
        title: String
    ) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(PermissionPreviewColor.systemBlue, in: .rect(cornerRadius: 12))

                Text(title)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            skeletonLines(widths: [269, 246, 182])
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 18)
    }

    private func centeredPermissionPreview<Content: View>(
        minHeight: CGFloat,
        hint: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 12) {
            content()
                .frame(width: 313)

            Text(hint)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(HomeColor.accent)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(HomeColor.accent.opacity(0.12), in: .capsule)
                .fixedSize(horizontal: true, vertical: false)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .center)
    }

    private func skeletonLines(
        widths: [CGFloat]
    ) -> some View {
        VStack(spacing: 7) {
            ForEach(Array(widths.enumerated()), id: \.offset) { _, width in
                Capsule()
                    .fill(HomeColor.textSecondary)
                    .frame(width: width, height: 5)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func permissionPreviewAction(
        _ title: String,
        isHighlighted: Bool,
        action: PermissionGuideAction? = nil
    ) -> some View {
        if let action {
            Button {
                perform(action)
            } label: {
                permissionPreviewActionLabel(title, isHighlighted: isHighlighted)
            }
            .buttonStyle(.plain)
            .disabled(isPerformingAction)
            .accessibilityLabel(title)
            .accessibilityIdentifier(identifier(for: action))
            .accessibilityHint(hint(for: action))
        } else {
            permissionPreviewActionLabel(title, isHighlighted: isHighlighted)
                .accessibilityHidden(true)
        }
    }

    private func permissionPreviewActionLabel(
        _ title: String,
        isHighlighted: Bool
    ) -> some View {
        Group {
            if isPerformingAction && isHighlighted {
                ProgressView()
                    .tint(.white)
            } else {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(isHighlighted ? .bold : .semibold)
            }
        }
        .foregroundStyle(isHighlighted ? .white : PermissionPreviewColor.systemBlueText)
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(isHighlighted ? PermissionPreviewColor.systemBlue : HomeColor.surfaceElevated)
        .contentShape(.rect)
    }

    private var locationSettingsMockup: some View {
        systemMockupCard(
            icon: "gearshape.fill",
            title: AppLocalizedCopy.string("설정 · 나서 · 위치"),
            accessibilityIdentifier: "permissionGuide.mockup.locationSettings",
            accessibilityLabel: AppLocalizedCopy.string("위치 설정 예시. 위치 접근은 항상, 정확한 위치는 켬으로 설정해 주세요.")
        ) {
            mockupSettingRow(
                title: AppLocalizedCopy.string("위치 접근"),
                value: AppLocalizedCopy.string("항상"),
                isHighlighted: true
            )
            mockupToggleRow(
                title: AppLocalizedCopy.string("정확한 위치"),
                isOn: true
            )
        }
    }

    private var backgroundRefreshSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            systemMockupCard(
                icon: "arrow.clockwise",
                title: AppLocalizedCopy.string("설정 · 일반"),
                accessibilityIdentifier: "permissionGuide.mockup.backgroundRefresh",
                accessibilityLabel: AppLocalizedCopy.string("백그라운드 앱 새로 고침 설정 예시. 기능과 나서를 켜 주세요.")
            ) {
                mockupSettingRow(
                    title: AppLocalizedCopy.string("백그라운드 앱 새로 고침"),
                    value: AppLocalizedCopy.string("켬"),
                    isHighlighted: true
                )
                mockupToggleRow(
                    title: AppLocalizedCopy.string("나서"),
                    isOn: true
                )
            }

            Text("설정  ›  일반  ›  백그라운드 앱 새로 고침")
                .fontWeight(.semibold)
            Text("나서 사용 가능 상태를 확인해 주세요. 저전력 모드에서는 시스템이 동작을 제한할 수 있어요.")
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
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier(accessibilityIdentifier)
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
                    ? AppLocalizedCopy.string("현재 상태 · 제한 활성 유지")
                    : AppLocalizedCopy.string("현재 상태 · 제한 비활성 유지")
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
        Group {
            if !screen.primaryAction.isEmbeddedPermissionRequest {
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
        }
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
        case .completeOnboarding:
            Task { @MainActor in
                await performAsynchronousAction(action)
            }
        case .requestFamilyControlsAuthorization,
             .requestLocationAuthorization,
             .requestAlwaysLocationAuthorization,
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
                presentationState: update.presentationState,
                requestedAction: action
            )
        }
        if action == .completeOnboarding {
            model.dismiss()
        }
        isPerformingAction = false
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
            AppLocalizedCopy.string("필수 권한을 허용해야 규칙을 적용할 수 있어요.")
        case .familyControls:
            screen.message
        case .location:
            screen.message
        case .backgroundRefresh:
            AppLocalizedCopy.string("꺼져 있으면 앱이 닫힌 동안 권한·위치 상태 복구가 늦어질 수 있어요.")
        case .locationUnavailable(let isRestrictionApplied):
            isRestrictionApplied
                ? AppLocalizedCopy.string("위치를 확인할 수 없어도 현재 제한을 유지해요.")
                : AppLocalizedCopy.string("위치를 추정하지 않고 새 제한을 시작하지 않아요.")
        }
    }

    private func overviewTitle(for capability: PermissionGuideCapability) -> String {
        switch capability {
        case .familyControls: AppLocalizedCopy.string("앱 사용 제한")
        case .alwaysLocation: AppLocalizedCopy.string("위치 접근 · 항상")
        case .fullAccuracy: AppLocalizedCopy.string("정확한 위치")
        case .backgroundRefresh: "Background App Refresh"
        }
    }

    private func overviewDescription(
        for capability: PermissionGuideCapability
    ) -> String {
        switch capability {
        case .familyControls: AppLocalizedCopy.string("선택한 앱을 제한하려면 필요")
        case .alwaysLocation: AppLocalizedCopy.string("앱이 닫혀 있어도 조건 확인")
        case .fullAccuracy: AppLocalizedCopy.string("반경 경계를 안전하게 판단")
        case .backgroundRefresh: AppLocalizedCopy.string("복구 가능 상태 확인")
        }
    }

    private func label(for action: PermissionGuideAction) -> String {
        switch action {
        case .next: AppLocalizedCopy.string("다음")
        case .confirm: AppLocalizedCopy.string("확인")
        case .completeOnboarding: AppLocalizedCopy.string("시작하기")
        case .requestFamilyControlsAuthorization: AppLocalizedCopy.string("권한 허용하기")
        case .requestLocationAuthorization: AppLocalizedCopy.string("위치 권한 허용하기")
        case .requestAlwaysLocationAuthorization: AppLocalizedCopy.string("항상 허용으로 변경")
        case .openSettings: AppLocalizedCopy.string("설정 열기")
        case .retryLocation: AppLocalizedCopy.string("위치 다시 확인")
        }
    }

    private func identifier(for action: PermissionGuideAction) -> String {
        switch action {
        case .next: "permissionGuide.next"
        case .confirm: "permissionGuide.confirm"
        case .completeOnboarding: "permissionGuide.completeOnboarding"
        case .requestFamilyControlsAuthorization:
            "permissionGuide.requestFamilyControlsAuthorization"
        case .requestLocationAuthorization:
            "permissionGuide.requestLocationAuthorization"
        case .requestAlwaysLocationAuthorization:
            "permissionGuide.requestAlwaysLocationAuthorization"
        case .openSettings: "permissionGuide.openSettings"
        case .retryLocation: "permissionGuide.retryLocation"
        }
    }

    private func accessibilityLabel(for action: PermissionGuideAction) -> String {
        label(for: action)
    }

    private func hint(for action: PermissionGuideAction) -> String {
        switch action {
        case .next: AppLocalizedCopy.string("다음 권한 안내로 이동합니다.")
        case .confirm: AppLocalizedCopy.string("안내를 확인하고 닫습니다.")
        case .completeOnboarding: AppLocalizedCopy.string("온보딩을 완료하고 나서 사용을 시작합니다.")
        case .requestFamilyControlsAuthorization:
            AppLocalizedCopy.string("앱 사용 제한을 위한 iOS 권한 요청을 표시합니다.")
        case .requestLocationAuthorization:
            AppLocalizedCopy.string("위치 접근을 위한 iOS 권한 요청을 표시합니다.")
        case .requestAlwaysLocationAuthorization:
            AppLocalizedCopy.string("항상 위치 접근을 위한 iOS 권한 요청을 표시합니다.")
        case .openSettings: AppLocalizedCopy.string("나서의 권한을 변경할 수 있는 시스템 설정을 엽니다.")
        case .retryLocation: AppLocalizedCopy.string("현재 위치를 다시 확인하고 제한 상태를 재평가합니다.")
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

private extension PermissionGuideAction {
    var isEmbeddedPermissionRequest: Bool {
        switch self {
        case .requestFamilyControlsAuthorization,
             .requestLocationAuthorization,
             .requestAlwaysLocationAuthorization:
            true
        case .next, .confirm, .completeOnboarding, .openSettings, .retryLocation:
            false
        }
    }
}

private enum PermissionPreviewColor {
    static let systemBlue = Color(red: 10 / 255, green: 122 / 255, blue: 1)
    static let systemBlueText = Color(red: 51 / 255, green: 148 / 255, blue: 1)
}

private extension View {
    func permissionAlertSurface() -> some View {
        self
            .background(HomeColor.surfaceElevated)
            .clipShape(.rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            }
            .shadow(
                color: Color.black.opacity(0.52),
                radius: 21,
                x: 0,
                y: 18
            )
    }
}
