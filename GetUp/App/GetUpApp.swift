@preconcurrency import FamilyControls
import SwiftUI
import UIKit

@main
@MainActor
struct GetUpApp: App {
    private let runtime = AppRuntime.make()

    var body: some Scene {
        WindowGroup {
            switch runtime {
            case .ready(let environment):
                GetUpRootView(environment: environment)
            case .unavailable:
                StartupUnavailableView()
            }
        }
    }
}

@MainActor
private struct GetUpRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel
    @State private var permissionGuideModel: PermissionGuideModel?
    private let lifecycleCoordinator: AppLifecycleCoordinator?
    private let currentLocationProvider: any CurrentLocationProviding
    private let defaultCoordinate: ReferenceLocation
    private let applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)?
    private let showsRestrictionProbe: Bool
    private let permissionGuideRetryResult: String?

    init(environment: AppEnvironment) {
        _model = State(initialValue: environment.model)
        _permissionGuideModel = State(initialValue: environment.permissionGuideModel)
        lifecycleCoordinator = environment.lifecycleCoordinator
        currentLocationProvider = environment.currentLocationProvider
        defaultCoordinate = environment.defaultCoordinate
        applicationSelectionOverride = environment.applicationSelectionOverride
        showsRestrictionProbe = environment.showsRestrictionProbe
        permissionGuideRetryResult = environment.permissionGuideRetryResult
    }

    var body: some View {
        Group {
            if let permissionGuideModel, permissionGuideModel.isPresented {
                PermissionGuideView(
                    model: permissionGuideModel,
                    onAction: handlePermissionGuideAction
                )
            } else {
                NavigationStack {
                    content
                        .navigationDestination(isPresented: editorIsPresented) {
                            editorDestination
                        }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
        .task {
            guard model.loadingState == .idle else {
                return
            }
            _ = await restoreRuntimeState(refreshRestrictionStatus: false)
            await model.load()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, lifecycleCoordinator != nil else {
                return
            }
            Task {
                _ = await restoreRuntimeState()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.loadingState {
        case .idle, .loading:
            ProgressView("규칙을 불러오는 중")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(HomeColor.background.ignoresSafeArea())
        case .loaded:
            HomeView(
                model: model,
                showsRestrictionProbe: showsRestrictionProbe
            )
        case .failed:
            LoadFailureView {
                Task { await model.load() }
            }
        }
    }

    private func handlePermissionGuideAction(
        _ action: PermissionGuideAction
    ) async -> PermissionGuideUpdate? {
        switch action {
        case .requestFamilyControlsAuthorization:
            guard lifecycleCoordinator != nil else {
                return nil
            }
            do {
                _ = try await SystemFamilyControlsAuthorizationSession()
                    .requestIndividualAuthorization()
                return await restoreRuntimeState()
            } catch is CancellationError {
                return nil
            } catch {
                return await restoreRuntimeState()
            }
        case .requestLocationAuthorization:
            guard lifecycleCoordinator != nil else {
                return nil
            }
            _ = try? await currentLocationProvider.currentLocation()
            return await restoreRuntimeState()
        case .openSettings:
            openSettings()
            return nil
        case .retryLocation:
            if lifecycleCoordinator != nil {
                return await restoreRuntimeState()
            }
            await model.refreshRestrictionStatus()
            let state: RestrictionPresentationState = permissionGuideRetryResult == "inside"
                ? .active
                : .inactive
            return PermissionGuideUpdate(
                authorization: permissionGuideModel?.authorization
                    ?? AuthorizationSnapshot(
                        familyControls: .approved,
                        locationAuthorization: .always,
                        locationAccuracy: .full,
                        backgroundRefresh: .available
                    ),
                presentationState: state
            )
        case .next, .later:
            return nil
        }
    }

    private func restoreRuntimeState(
        refreshRestrictionStatus: Bool = true
    ) async -> PermissionGuideUpdate? {
        guard
            let lifecycleCoordinator,
            let result = try? await lifecycleCoordinator.restore()
        else {
            return nil
        }

        if refreshRestrictionStatus {
            await model.refreshRestrictionStatus()
        }

        guard let presentationState = result.presentationState else {
            reconcilePermissionGuide(
                authorization: result.authorization,
                presentationState: permissionGuideModel?.presentationState ?? .inactive
            )
            return nil
        }

        let update = PermissionGuideUpdate(
            authorization: result.authorization,
            presentationState: presentationState
        )
        reconcilePermissionGuide(
            authorization: update.authorization,
            presentationState: update.presentationState
        )
        return update
    }

    private func reconcilePermissionGuide(
        authorization: AuthorizationSnapshot,
        presentationState: RestrictionPresentationState
    ) {
        if let permissionGuideModel {
            if permissionGuideModel.isPresented {
                permissionGuideModel.update(
                    authorization: authorization,
                    presentationState: presentationState
                )
                return
            }

            let recoveryModel = PermissionGuideModel(
                authorization: authorization,
                presentationState: presentationState,
                presentationMode: .recovery
            )
            self.permissionGuideModel = recoveryModel
            return
        }

        let initialModel = PermissionGuideModel(
            authorization: authorization,
            presentationState: presentationState
        )
        permissionGuideModel = initialModel
    }

    @ViewBuilder
    private var editorDestination: some View {
        if let editorModel = model.editorModel {
            RuleEditorView(
                model: editorModel,
                currentLocationProvider: currentLocationProvider,
                defaultCoordinate: defaultCoordinate,
                applicationSelectionOverride: applicationSelectionOverride,
                onOpenSettings: openSettings,
                onSave: { draft, savedPlaces in
                    try await model.save(draft: draft, savedPlaces: savedPlaces)
                },
                onDelete: deleteAction
            )
        } else {
            EmptyView()
        }
    }

    private var editorIsPresented: Binding<Bool> {
        Binding(
            get: { model.editorModel != nil },
            set: { isPresented in
                if !isPresented {
                    model.cancelEditing()
                }
            }
        )
    }

    private var deleteAction: RuleEditorView.DeleteAction? {
        guard model.canDeleteEditingRule else {
            return nil
        }
        return {
            try await model.deleteEditingRule()
        }
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else {
            return
        }
        UIApplication.shared.open(url)
    }
}

@MainActor
private struct HomeView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var model: AppModel
    let showsRestrictionProbe: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header

                if model.homeRules.isEmpty {
                    emptyState
                } else {
                    rulePager
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(HomeColor.background.ignoresSafeArea())
        .foregroundStyle(HomeColor.textPrimary)
        .toolbarBackground(HomeColor.background, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if showsRestrictionProbe {
                RestrictionActivationProbeView(
                    isRestrictionActive: model.restrictionStatus.hasActiveRestriction
                )
            }
        }
    }

    private var header: some View {
        HStack {
            Text("GETUP")
                .font(.title3)
                .fontWeight(.bold)
            Spacer()
            Button {
                model.beginCreatingRule()
            } label: {
                Image(systemName: "plus")
                    .font(.title2)
                    .foregroundStyle(HomeColor.accent)
                    .frame(width: 48, height: 48)
                    .background(HomeColor.surfaceElevated, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("새 규칙")
            .accessibilityIdentifier("home.createRule")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text("NO FOCUS RULES")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(HomeColor.textTertiary)
                Text("첫 규칙을\n만들어보세요")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("소중한 내 시간을 지켜요")
                    .font(.headline)
                    .foregroundStyle(HomeColor.textSecondary)
            }

            VStack(spacing: 24) {
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(HomeColor.accent)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 14) {
                    emptyInstruction("01", "기상 후 휴대폰 보는 시간을 줄여봐요")
                    emptyInstruction("02", "취침 전 휴대폰 보는 시간을 줄여봐요")
                    emptyInstruction("03", "근무 또는 학습 중 휴대폰 보는 시간을 줄여봐요")
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(HomeColor.surface, in: .rect(cornerRadius: 28))

            Button("새 규칙 만들기") {
                model.beginCreatingRule()
            }
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, minHeight: 56)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 18))
            .tint(HomeColor.accent)
            .foregroundStyle(HomeColor.background)
            .accessibilityIdentifier("home.createRule")
        }
    }

    private func emptyInstruction(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(HomeColor.accent)
            Text(text)
                .font(.body)
                .fontWeight(.semibold)
        }
    }

    private var rulePager: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                TabView(selection: selectedRuleBinding) {
                    ForEach(Array(model.homeRules.enumerated()), id: \.element.id) { index, item in
                        if model.restrictionStatus.isActive(item.rule) {
                            RestrictionStatusView(
                                item: item,
                                rulePosition: index + 1,
                                ruleCount: model.homeRules.count
                            )
                            .padding(.horizontal, 2)
                            .tag(item.id)
                        } else {
                            HomeRuleCard(
                                item: item,
                                rulePosition: index + 1,
                                ruleCount: model.homeRules.count
                            ) {
                                model.beginEditingRule(id: item.id)
                            }
                            .padding(.horizontal, 2)
                            .tag(item.id)
                        }
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .frame(height: rulePagerHeight)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.rulePager")

            HStack(spacing: 7) {
                ForEach(model.homeRules.indices, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? HomeColor.accent : HomeColor.textTertiary)
                        .frame(width: 8, height: 8)
                }
            }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(pageIndicatorLabel)
                .accessibilityIdentifier("home.rulePageIndicator")

            Text("좌우로 밀어 보기")
                .font(.caption)
                .foregroundStyle(HomeColor.textTertiary)
        }
    }

    private var selectedRuleBinding: Binding<UUID> {
        Binding(
            get: { model.selectedRuleID ?? model.homeRules[0].id },
            set: { model.selectedRuleID = $0 }
        )
    }

    private var pageIndicatorLabel: String {
        return "\(selectedIndex + 1) / \(model.homeRules.count)"
    }

    private var selectedIndex: Int {
        model.homeRules.firstIndex { $0.id == model.selectedRuleID } ?? 0
    }

    private var rulePagerHeight: CGFloat {
        dynamicTypeSize.isAccessibilitySize ? 760 : 548
    }
}

private struct HomeRuleCard: View {
    let item: HomeRuleItem
    let rulePosition: Int
    let ruleCount: Int
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(occurrenceEyebrow)
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundStyle(HomeColor.accent)
                .accessibilityIdentifier("restrictionStatus.inactive")
            Text(item.rule.name ?? item.savedPlace.name)
                .font(.largeTitle)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 16) {
                Text("RULE \(rulePosition) OF \(ruleCount) · \(weekdayLabel)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(HomeColor.textTertiary)
                    .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID).schedule")

                timeText
                    .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID).time")

                Divider().overlay(HomeColor.disabled)

                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "door.left.hand.open")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(HomeColor.accent)
                        .frame(width: 78, height: 78)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(item.savedPlace.name)에서 \(radiusLabel) 나가면")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text("선택한 앱 \(item.applicationCount)개를\n다시 사용할 수 있어요")
                            .font(.subheadline)
                            .foregroundStyle(HomeColor.textSecondary)
                    }
                }

                conditionRow(label: "LOCATION", value: "\(item.savedPlace.name) · \(radiusLabel)", identifier: "home.ruleCard.\(item.accessibilityID).location")
                conditionRow(label: "BLOCKED", value: "\(item.applicationCount)개 앱", identifier: "home.ruleCard.\(item.accessibilityID).applications")

                Spacer(minLength: 0)
                Button("규칙 수정", action: onEdit)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, minHeight: 42)
                    .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 14))
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID).edit")
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 456, alignment: .topLeading)
            .background(HomeColor.surface, in: .rect(cornerRadius: 28))
            .overlay {
                RoundedRectangle(cornerRadius: 28).stroke(HomeColor.accent, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID)")
    }

    private func conditionRow(
        label: String,
        value: String,
        identifier: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: label == "LOCATION" ? "scope" : "square.grid.3x3.fill")
                .foregroundStyle(HomeColor.accent)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(label).font(.caption2).fontWeight(.bold).foregroundStyle(HomeColor.textTertiary)
                Text(value).font(.subheadline).fontWeight(.bold).accessibilityIdentifier(identifier)
            }
            Spacer()
        }
        .frame(minHeight: 54)
    }

    private var timeText: Text {
        Text(
            "\(Text(Self.clock(item.rule.startTime)).font(.system(size: 38, weight: .bold))) \(Text(Self.period(item.rule.startTime)).font(.caption).foregroundColor(HomeColor.textSecondary)) \(Text("→").font(.title2).foregroundColor(HomeColor.accent)) \(Text(Self.clock(item.rule.endTime)).font(.system(size: 38, weight: .bold))) \(Text(Self.period(item.rule.endTime)).font(.caption).foregroundColor(HomeColor.textSecondary))"
        )
    }

    private var weekdayLabel: String {
        Weekday.allCases
            .filter(item.rule.weekdays.contains)
            .map(Self.shortWeekday)
            .joined(separator: "–")
    }

    private var occurrenceEyebrow: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return item.isScheduledToday
            ? "TODAY · \(formatter.string(from: item.nextStart).uppercased())"
            : "NEXT · \(formatter.string(from: item.nextStart).uppercased())"
    }

    private var radiusLabel: String { RadiusPicker.displayName(for: item.rule.radius) }
    private static func clock(_ time: TimeOfDay) -> String {
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        return String(format: "%02d:%02d", hour, time.minute)
    }

    private static func period(_ time: TimeOfDay) -> String { time.hour < 12 ? "AM" : "PM" }

    private static func shortWeekday(_ weekday: Weekday) -> String {
        switch weekday {
        case .monday: "MON"
        case .tuesday: "TUE"
        case .wednesday: "WED"
        case .thursday: "THU"
        case .friday: "FRI"
        case .saturday: "SAT"
        case .sunday: "SUN"
        }
    }
}

private struct LoadFailureView: View {
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(HomeColor.error)
            Text("규칙을 불러오지 못했어요")
                .font(.title2)
                .fontWeight(.bold)
            Text("저장된 내용은 변경하지 않았어요. 다시 시도해 주세요.")
                .foregroundStyle(HomeColor.textSecondary)
                .multilineTextAlignment(.center)
            Button("다시 시도", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(HomeColor.accent)
                .foregroundStyle(HomeColor.background)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeColor.background.ignoresSafeArea())
    }
}

private struct StartupUnavailableView: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
                .font(.largeTitle)
                .foregroundStyle(HomeColor.error)
            Text("공유 저장소를 열 수 없어요")
                .font(.title2)
                .fontWeight(.bold)
            Text("앱을 다시 실행해 주세요.")
                .foregroundStyle(HomeColor.textSecondary)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(HomeColor.background.ignoresSafeArea())
        .preferredColorScheme(.dark)
    }
}

enum HomeColor {
    static let background = Color(red: 8 / 255, green: 9 / 255, blue: 11 / 255)
    static let surface = Color(red: 21 / 255, green: 23 / 255, blue: 27 / 255)
    static let surfaceElevated = Color(red: 32 / 255, green: 35 / 255, blue: 41 / 255)
    static let disabled = Color(red: 58 / 255, green: 61 / 255, blue: 68 / 255)
    static let accent = Color(red: 244 / 255, green: 214 / 255, blue: 0)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 166 / 255, green: 168 / 255, blue: 173 / 255)
    static let textTertiary = Color(red: 125 / 255, green: 128 / 255, blue: 135 / 255)
    static let error = Color(red: 255 / 255, green: 105 / 255, blue: 97 / 255)
}

private struct RestrictionActivationProbeView: View {
    let isRestrictionActive: Bool
    @State private var showsShield = false
    @State private var showsSelectedApplication = false
    @State private var showsUnselectedApplication = false

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button("선택 앱 열기") {
                    if isRestrictionActive {
                        showsShield = true
                        showsSelectedApplication = false
                    } else {
                        showsSelectedApplication = true
                    }
                }
                .accessibilityIdentifier("restrictionProbe.selectedApplication.open")

                Button("비대상 앱 열기") {
                    showsUnselectedApplication = true
                    showsShield = false
                }
                .accessibilityIdentifier("restrictionProbe.unselectedApplication.open")
            }
            .buttonStyle(.bordered)

            if showsShield {
                HStack {
                    Text("제한 적용 중")
                    Spacer()
                    Button {
                        showsShield = false
                    } label: {
                        Text("앱 닫기")
                            .frame(minWidth: 44, minHeight: 44)
                            .contentShape(.rect)
                    }
                    .accessibilityIdentifier("restrictionProbe.shield.close")
                }
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("restrictionProbe.shield")
            }

            if showsSelectedApplication {
                Color.clear
                    .frame(height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("restrictionProbe.selectedApplication.content")
            }

            if showsUnselectedApplication {
                Color.clear
                    .frame(height: 1)
                    .accessibilityElement()
                    .accessibilityIdentifier("restrictionProbe.unselectedApplication.content")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(HomeColor.background)
    }
}

private extension Weekday {
    var shortKoreanName: String {
        switch self {
        case .monday: "월"
        case .tuesday: "화"
        case .wednesday: "수"
        case .thursday: "목"
        case .friday: "금"
        case .saturday: "토"
        case .sunday: "일"
        }
    }
}

@MainActor
private enum AppRuntime {
    case ready(AppEnvironment)
    case unavailable

    static func make() -> AppRuntime {
        do {
            if UITestConfiguration.isEnabled {
                return .ready(try UITestConfiguration.makeEnvironment())
            }
            return .ready(try AppEnvironment.live())
        } catch {
            return .unavailable
        }
    }
}

@MainActor
private struct AppEnvironment {
    let model: AppModel
    let lifecycleCoordinator: AppLifecycleCoordinator?
    let currentLocationProvider: any CurrentLocationProviding
    let defaultCoordinate: ReferenceLocation
    let applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)?
    let showsRestrictionProbe: Bool
    let permissionGuideModel: PermissionGuideModel?
    let permissionGuideRetryResult: String?

    static func live() throws -> AppEnvironment {
        let container = try DependencyContainer.live()
        let locationSession = CoreLocationCurrentLocationSession()
        let lifecycleCoordinator = try AppLifecycleCoordinator.live(
            container: container,
            authorizationProvider: SystemAuthorizationProvider.forApplication()
        )
        let restrictionAdapter = try ManagedSettingsRestrictionAdapter.live()
        return AppEnvironment(
            model: AppModel(
                ruleRepository: container.ruleRepository,
                savedPlaceRepository: container.savedPlaceRepository,
                synchronizeRuntimeAfterSave: { _ in
                    _ = try await lifecycleCoordinator.restore()
                },
                loadAppliedRestrictionState: {
                    await restrictionAdapter.currentAppliedState()
                }
            ),
            lifecycleCoordinator: lifecycleCoordinator,
            currentLocationProvider: CurrentLocationProvider(session: locationSession),
            defaultCoordinate: ReferenceLocation(latitude: 37.5665, longitude: 126.9780),
            applicationSelectionOverride: nil,
            showsRestrictionProbe: false,
            permissionGuideModel: nil,
            permissionGuideRetryResult: nil
        )
    }
}

private struct UITestCurrentLocationProvider: CurrentLocationProviding {
    func currentLocation() async throws -> ReferenceLocation {
        ReferenceLocation(latitude: 37.5665, longitude: 126.9780)
    }
}

@MainActor
private enum UITestConfiguration {
    static var isEnabled: Bool {
        arguments.contains("--ui-testing")
    }

    static func makeEnvironment() throws -> AppEnvironment {
        let storeID = safeStoreID(value(after: "--ui-test-store-id") ?? "default")
        let scenario = value(after: "--ui-test-scenario")
        let shouldReset = arguments.contains("--ui-test-reset-store")
        let applicationResult = value(after: "--ui-test-family-picker-result")
        let fixtureNow = parsedDate(value(after: "--ui-test-now")) ?? Fixtures.now
        let locationState = value(after: "--ui-test-location-state")
        let permissionGuideRetryResult = value(
            after: "--ui-test-location-retry-result"
        )
        let fileManager = FileManager.default
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GetUpUITests", isDirectory: true)
            .appendingPathComponent(storeID, isDirectory: true)

        if shouldReset, fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let container = DependencyContainer(containerURL: root)
        let fixtures = Fixtures()
        let initialDraft = fixtures.initialDraft(for: scenario)
        let bootstrap: @Sendable () async throws -> Void = {
            guard shouldReset else {
                return
            }

            try await container.savedPlaceRepository.saveSavedPlaceCollection(
                SavedPlaceCollectionSnapshot(revision: 1, places: fixtures.places)
            )

            if scenario == "three-saved-rules" {
                try await container.ruleRepository.saveRuleCollection(
                    RestrictionRuleCollectionSnapshot(
                        revision: 1,
                        rules: fixtures.rules
                    )
                )
            } else if scenario == "restriction-activation"
                || scenario?.hasPrefix("location-unavailable-") == true {
                try await container.ruleRepository.saveRuleCollection(
                    RestrictionRuleCollectionSnapshot(
                        revision: 1,
                        rules: [fixtures.restrictionActivationRule]
                    )
                )
            }
        }

        let selectionOverride: (@MainActor () -> FamilyActivitySelection?)?
        if applicationResult == nil {
            selectionOverride = nil
        } else {
            selectionOverride = { @MainActor in
                FamilyActivitySelection(includeEntireCategory: true)
            }
        }

        return AppEnvironment(
            model: AppModel(
                ruleRepository: container.ruleRepository,
                savedPlaceRepository: container.savedPlaceRepository,
                now: { fixtureNow },
                calendar: Fixtures.calendar,
                timeZone: Fixtures.timeZone,
                applicationTokenCounter: { selection in
                    selection.includeEntireCategory ? 1 : 0
                },
                applicationCountForRule: fixtures.applicationCount,
                ruleAccessibilityID: fixtures.accessibilityID,
                initialEditorDraft: initialDraft,
                bootstrap: bootstrap,
                loadAppliedRestrictionState: {
                    let rule = fixtures.restrictionActivationRule
                    let scheduleIsActive = ScheduleEvaluator.isActive(
                        weekdays: rule.weekdays,
                        startTime: rule.startTime,
                        endTime: rule.endTime,
                        at: fixtureNow,
                        calendar: Fixtures.calendar,
                        timeZone: Fixtures.timeZone
                    )
                    let shouldApply = locationState == "inside"
                        || (
                            scenario == "location-unavailable-active"
                                && permissionGuideRetryResult == "inside"
                        )
                    let scheduleAllowsApplication = scheduleIsActive
                        || scenario == "location-unavailable-active"
                    let revisions: Set<ActiveRuleRevision> =
                        scheduleAllowsApplication && shouldApply
                        ? [ActiveRuleRevision(ruleID: rule.id, revision: rule.revision)]
                        : []
                    return AppliedRestrictionState(activeRuleRevisions: revisions)
                }
            ),
            lifecycleCoordinator: nil,
            currentLocationProvider: UITestCurrentLocationProvider(),
            defaultCoordinate: fixtures.home.coordinate,
            applicationSelectionOverride: selectionOverride,
            showsRestrictionProbe: scenario == "restriction-activation",
            permissionGuideModel: permissionGuideModel(for: scenario),
            permissionGuideRetryResult: permissionGuideRetryResult
        )
    }

    private static func permissionGuideModel(
        for scenario: String?
    ) -> PermissionGuideModel? {
        let approved = AuthorizationSnapshot(
            familyControls: .approved,
            locationAuthorization: .always,
            locationAccuracy: .full,
            backgroundRefresh: .available
        )

        switch scenario {
        case "permission-overview":
            return PermissionGuideModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .denied,
                    locationAuthorization: .whenInUse,
                    locationAccuracy: .reduced,
                    backgroundRefresh: .restricted
                ),
                presentationState: .permissionRequired(
                    missingPermissions: [
                        .familyControls,
                        .alwaysLocation,
                        .fullAccuracy,
                    ]
                ),
                initialScreenKind: .overview,
                presentationMode: .onboarding
            )
        case "permission-family-controls-undetermined":
            return PermissionGuideModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .notDetermined,
                    locationAuthorization: .always,
                    locationAccuracy: .full,
                    backgroundRefresh: .available
                ),
                presentationState: .permissionRequired(
                    missingPermissions: [.familyControls]
                ),
                initialScreenKind: .familyControls,
                presentationMode: .onboarding
            )
        case "permission-family-controls-approved":
            return PermissionGuideModel(
                authorization: approved,
                presentationState: .inactive,
                initialScreenKind: .familyControls,
                presentationMode: .onboarding
            )
        case "permission-family-controls-denied":
            return PermissionGuideModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .denied,
                    locationAuthorization: .always,
                    locationAccuracy: .full,
                    backgroundRefresh: .available
                ),
                presentationState: .permissionRequired(
                    missingPermissions: [.familyControls]
                ),
                presentationMode: .recovery
            )
        case "permission-location-undetermined":
            return PermissionGuideModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .approved,
                    locationAuthorization: .notDetermined,
                    locationAccuracy: .full,
                    backgroundRefresh: .available
                ),
                presentationState: .permissionRequired(
                    missingPermissions: [.alwaysLocation]
                ),
                initialScreenKind: .location,
                presentationMode: .onboarding
            )
        case "permission-location-approved":
            return PermissionGuideModel(
                authorization: approved,
                presentationState: .inactive,
                initialScreenKind: .location,
                presentationMode: .onboarding
            )
        case "permission-location-denied":
            return PermissionGuideModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .approved,
                    locationAuthorization: .whenInUse,
                    locationAccuracy: .reduced,
                    backgroundRefresh: .available
                ),
                presentationState: .permissionRequired(
                    missingPermissions: [.alwaysLocation, .fullAccuracy]
                ),
                presentationMode: .recovery
            )
        case "permission-background-refresh-approved":
            return PermissionGuideModel(
                authorization: approved,
                presentationState: .inactive,
                initialScreenKind: .backgroundRefresh,
                presentationMode: .onboarding
            )
        case "permission-background-refresh-denied":
            return PermissionGuideModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .approved,
                    locationAuthorization: .always,
                    locationAccuracy: .full,
                    backgroundRefresh: .restricted
                ),
                presentationState: .inactive,
                initialScreenKind: .backgroundRefresh,
                presentationMode: .onboarding
            )
        case "permission-runtime-approved":
            return PermissionGuideModel(
                authorization: approved,
                presentationState: .inactive,
                presentationMode: .recovery
            )
        case "location-unavailable-inactive":
            return PermissionGuideModel(
                authorization: approved,
                presentationState: .locationUnavailable(
                    isRestrictionApplied: false
                )
            )
        case "location-unavailable-active":
            return PermissionGuideModel(
                authorization: approved,
                presentationState: .locationUnavailable(
                    isRestrictionApplied: true
                )
            )
        default:
            return nil
        }
    }

    private static var arguments: [String] {
        ProcessInfo.processInfo.arguments
    }

    private static func value(after key: String) -> String? {
        guard
            let index = arguments.firstIndex(of: key),
            arguments.indices.contains(index + 1)
        else {
            return nil
        }
        return arguments[index + 1]
    }

    private static func safeStoreID(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_")
        )
        let sanitized = value.components(separatedBy: allowed.inverted)
            .joined(separator: "_")
        return sanitized.isEmpty ? "default" : sanitized
    }

    private static func parsedDate(_ value: String?) -> Date? {
        guard let value else {
            return nil
        }
        return ISO8601DateFormatter().date(from: value)
    }

    private struct Fixtures: Sendable {
        static let timeZone = TimeZone(secondsFromGMT: 0)!
        static let now: Date = {
            var components = DateComponents()
            components.calendar = calendar
            components.timeZone = timeZone
            components.year = 2026
            components.month = 8
            components.day = 24
            components.hour = 5
            return components.date!
        }()
        static var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.locale = Locale(identifier: "ko_KR")
            calendar.timeZone = timeZone
            return calendar
        }

        let home = SavedPlaceSnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000501")!,
            name: "집",
            coordinate: ReferenceLocation(latitude: 37.5665, longitude: 126.9780),
            createdAt: now,
            updatedAt: now
        )
        let work = SavedPlaceSnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000502")!,
            name: "회사",
            coordinate: ReferenceLocation(latitude: 37.4021, longitude: 127.1087),
            createdAt: now,
            updatedAt: now
        )

        var places: [SavedPlaceSnapshot] { [home, work] }

        var rules: [RestrictionRuleSnapshot] {
            [
                makeRule(
                    id: Self.rule1ID,
                    name: "아침 집중",
                    weekdays: [.monday, .wednesday, .friday],
                    start: TimeOfDay(hour: 6, minute: 0),
                    end: TimeOfDay(hour: 9, minute: 0),
                    place: home,
                    radius: .meters1000
                ),
                makeRule(
                    id: Self.rule2ID,
                    name: "퇴근 준비",
                    weekdays: [.tuesday, .thursday],
                    start: TimeOfDay(hour: 18, minute: 0),
                    end: TimeOfDay(hour: 20, minute: 0),
                    place: work,
                    radius: .meters500
                ),
                makeRule(
                    id: Self.rule3ID,
                    name: "주중 정리",
                    weekdays: [.wednesday],
                    start: TimeOfDay(hour: 21, minute: 0),
                    end: TimeOfDay(hour: 22, minute: 0),
                    place: home,
                    radius: .meters2000
                ),
            ]
        }

        var restrictionActivationRule: RestrictionRuleSnapshot {
            makeRule(
                id: Self.rule1ID,
                name: "출근 준비",
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                start: TimeOfDay(hour: 6, minute: 0),
                end: TimeOfDay(hour: 9, minute: 0),
                place: home,
                radius: .meters1000
            )
        }

        func initialDraft(for scenario: String?) -> RuleEditorDraft? {
            switch scenario {
            case "empty-editor":
                RuleEditorDraft(
                    id: Self.rule1ID,
                    sourceRevision: nil,
                    isEnabled: true,
                    name: nil,
                    weekdays: [],
                    startTime: TimeOfDay(hour: 6, minute: 0),
                    endTime: TimeOfDay(hour: 9, minute: 0),
                    savedPlaceID: nil,
                    radius: .meters1000,
                    activitySelection: FamilyActivitySelection(),
                    createdAt: Self.now
                )
            case "valid-rule-draft":
                RuleEditorDraft(
                    id: Self.rule1ID,
                    sourceRevision: nil,
                    isEnabled: true,
                    name: "아침 집중",
                    weekdays: [.monday, .wednesday, .friday],
                    startTime: TimeOfDay(hour: 6, minute: 0),
                    endTime: TimeOfDay(hour: 9, minute: 0),
                    savedPlaceID: home.id,
                    radius: .meters1000,
                    activitySelection: FamilyActivitySelection(includeEntireCategory: true),
                    createdAt: Self.now
                )
            default:
                nil
            }
        }

        func applicationCount(for rule: RestrictionRuleSnapshot) -> Int {
            rule.id == Self.rule2ID ? 2 : 1
        }

        func accessibilityID(for rule: RestrictionRuleSnapshot) -> String {
            switch rule.id {
            case Self.rule1ID: "rule-1"
            case Self.rule2ID: "rule-2"
            case Self.rule3ID: "rule-3"
            default: rule.id.uuidString.lowercased()
            }
        }

        private func makeRule(
            id: UUID,
            name: String,
            weekdays: Set<Weekday>,
            start: TimeOfDay,
            end: TimeOfDay,
            place: SavedPlaceSnapshot,
            radius: RadiusOption
        ) -> RestrictionRuleSnapshot {
            RestrictionRuleSnapshot(
                id: id,
                revision: 1,
                name: name,
                isEnabled: true,
                weekdays: weekdays,
                startTime: start,
                endTime: end,
                savedPlaceID: place.id,
                radius: radius,
                activitySelection: FamilyActivitySelection(includeEntireCategory: true),
                createdAt: Self.now,
                updatedAt: Self.now
            )
        }

        private static let rule1ID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000511"
        )!
        private static let rule2ID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000512"
        )!
        private static let rule3ID = UUID(
            uuidString: "00000000-0000-4000-8000-000000000513"
        )!
    }
}
