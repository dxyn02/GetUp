@preconcurrency import CoreLocation
@preconcurrency import FamilyControls
import Foundation
import ManagedSettings
import SwiftUI
import UIKit

@main
@MainActor
struct GetUpApp: App {
    @UIApplicationDelegateAdaptor(LocationRegionAppDelegate.self)
    private var appDelegate
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
final class LocationRegionAppDelegate: NSObject,
    UIApplicationDelegate,
    @preconcurrency CLLocationManagerDelegate
{
    private let locationManager: CLLocationManager
    private let diagnostics: any DiagnosticsLogging
    private var eventHandler: LocationRegionEventHandler?

    override init() {
        locationManager = CLLocationManager()
        diagnostics = DiagnosticsLogger()
        super.init()
        locationManager.delegate = self
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions:
            [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Creating a main-run-loop manager with a delegate at launch lets Core
        // Location deliver pending region events after a background relaunch.
        locationManager.delegate = self
        return true
    }

    func locationManager(
        _ manager: CLLocationManager,
        didEnterRegion region: CLRegion
    ) {
        handle(region: region, transition: .entered)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didExitRegion region: CLRegion
    ) {
        handle(region: region, transition: .exited)
    }

    func locationManager(
        _ manager: CLLocationManager,
        monitoringDidFailFor region: CLRegion?,
        withError error: any Error
    ) {
        diagnostics.record(error, operation: .locationConditionRefresh)
    }

    func locationManager(
        _ manager: CLLocationManager,
        didFailWithError error: any Error
    ) {
        diagnostics.record(error, operation: .locationConditionRefresh)
    }

    private func handle(
        region: CLRegion,
        transition: LocationRegionTransition
    ) {
        let confirmedAt = Date()
        let regionIdentifier = region.identifier

        Task {
            do {
                let handler = try eventHandler ?? makeEventHandler()
                eventHandler = handler
                _ = try await handler.handle(
                    regionIdentifier: regionIdentifier,
                    transition: transition,
                    confirmedAt: confirmedAt
                )
            } catch {
                diagnostics.record(error, operation: .restrictionEvaluate)
            }
        }
    }

    private func makeEventHandler() throws -> LocationRegionEventHandler {
        let container = try DependencyContainer.live()
        return try container.makeLocationRegionEventHandler()
    }
}

@MainActor
private extension DependencyContainer {
    func makeLocationRegionEventHandler(
        bundle: Bundle = .main,
        authorizationProvider: any AuthorizationProviding =
            SystemAuthorizationProvider.forApplication()
    ) throws -> LocationRegionEventHandler {
        LocationRegionEventHandler(
            ruleRepository: ruleRepository,
            conditionRepository: locationConditionRepository,
            restrictionCoordinator: try makeRestrictionCoordinator(
                bundle: bundle,
                authorizationProvider: authorizationProvider
            )
        )
    }
}

@MainActor
private struct GetUpRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel
    @State private var permissionGuideModel: PermissionGuideModel?
    @State private var isRestoringRuntime = false
    private let runtimeRecovery: AppEnvironment.RuntimeRecovery?
    private let currentLocationProvider: any CurrentLocationProviding & LocationAuthorizationRequesting
    private let defaultCoordinate: ReferenceLocation
    private let applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)?
    private let familyControlsAuthorizationStatusOverride:
        (@MainActor () -> FamilyControlsAuthorizationStatus)?
    private let showsRestrictionProbe: Bool
    private let permissionGuideRetryResult: String?
    private let permissionGuideActionUpdate: PermissionGuideUpdate?
    private let permissionOnboardingStateStore: PermissionOnboardingStateStore

    init(environment: AppEnvironment) {
        _model = State(initialValue: environment.model)
        _permissionGuideModel = State(initialValue: environment.permissionGuideModel)
        runtimeRecovery = environment.runtimeRecovery
        currentLocationProvider = environment.currentLocationProvider
        defaultCoordinate = environment.defaultCoordinate
        applicationSelectionOverride = environment.applicationSelectionOverride
        familyControlsAuthorizationStatusOverride =
            environment.familyControlsAuthorizationStatusOverride
        showsRestrictionProbe = environment.showsRestrictionProbe
        permissionGuideRetryResult = environment.permissionGuideRetryResult
        permissionGuideActionUpdate = environment.permissionGuideActionUpdate
        permissionOnboardingStateStore = environment.permissionOnboardingStateStore
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
            await model.load()
            guard !Task.isCancelled else {
                return
            }
            _ = await restoreRuntimeState()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, runtimeRecovery != nil else {
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
        if let permissionGuideActionUpdate {
            switch action {
            case .requestFamilyControlsAuthorization,
                 .requestLocationAuthorization,
                 .requestAlwaysLocationAuthorization:
                return permissionGuideActionUpdate
            case .next, .confirm, .completeOnboarding, .openSettings, .retryLocation:
                break
            }
        }

        switch action {
        case .requestFamilyControlsAuthorization:
            guard runtimeRecovery != nil else {
                return nil
            }
            do {
                _ = try await SystemFamilyControlsAuthorizationSession()
                    .requestIndividualAuthorization()
                return await restoreRuntimeState(reconcilePermissionGuide: false)
            } catch is CancellationError {
                return nil
            } catch {
                return await restoreRuntimeState(reconcilePermissionGuide: false)
            }
        case .requestLocationAuthorization:
            guard runtimeRecovery != nil else {
                return nil
            }
            _ = await currentLocationProvider.requestWhenInUseAuthorization()
            return await restoreRuntimeState(reconcilePermissionGuide: false)
        case .requestAlwaysLocationAuthorization:
            guard runtimeRecovery != nil else {
                return nil
            }
            _ = await currentLocationProvider.requestAlwaysAuthorization()
            return await restoreRuntimeState(reconcilePermissionGuide: false)
        case .openSettings:
            openSettings()
            return nil
        case .completeOnboarding:
            permissionOnboardingStateStore.markCompleted()
            return nil
        case .retryLocation:
            if runtimeRecovery != nil {
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
        case .next, .confirm:
            return nil
        }
    }

    private func restoreRuntimeState(
        reconcilePermissionGuide shouldReconcilePermissionGuide: Bool = true
    ) async -> PermissionGuideUpdate? {
        guard let runtimeRecovery, !isRestoringRuntime else {
            return nil
        }
        isRestoringRuntime = true
        defer { isRestoringRuntime = false }

        guard let result = await runtimeRecovery() else {
            return nil
        }

        await model.refreshRestrictionStatus()

        let update = PermissionGuideUpdate(
            authorization: result.authorization,
            presentationState: result.presentationState
                ?? permissionGuideModel?.presentationState
                ?? .inactive
        )
        if shouldReconcilePermissionGuide {
            reconcilePermissionGuide(
                authorization: update.authorization,
                presentationState: update.presentationState
            )
        }
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

        let initialModel = PermissionGuideLaunchRouter.makeInitialModel(
            authorization: authorization,
            presentationState: presentationState,
            onboardingStateStore: permissionOnboardingStateStore
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
                familyControlsAuthorizationStatusOverride:
                    familyControlsAuthorizationStatusOverride,
                onPresentFamilyControlsPermissionGuide: presentFamilyControlsPermissionGuide,
                onOpenSettings: openSettings,
                onSave: { draft, savedPlaces in
                    try await model.save(draft: draft, savedPlaces: savedPlaces)
                },
                onDelete: deleteAction,
                onDeleteSavedPlace: { id in
                    try await model.deleteSavedPlace(id: id)
                }
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

    private func presentFamilyControlsPermissionGuide(
        _ status: FamilyControlsAuthorizationStatus
    ) {
        let currentAuthorization = permissionGuideModel?.authorization
        let authorization = AuthorizationSnapshot(
            familyControls: status,
            locationAuthorization: currentAuthorization?.locationAuthorization ?? .always,
            locationAccuracy: currentAuthorization?.locationAccuracy ?? .full,
            backgroundRefresh: currentAuthorization?.backgroundRefresh ?? .available
        )
        permissionGuideModel = PermissionGuideModel(
            authorization: authorization,
            presentationState: .permissionRequired(missingPermissions: [.familyControls]),
            initialScreenKind: .familyControls,
            presentationMode: .recovery
        )
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
        VStack(alignment: .leading, spacing: 22) {
            header

            if model.homeRules.isEmpty {
                emptyState
            } else if model.homeRules.count == 1, let item = model.homeRules.first {
                singleRuleCard(item)
            } else {
                rulePager
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
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
            Text("나서")
                .font(.title3)
                .fontWeight(.bold)
                .accessibilityIdentifier("home.brandName")
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
                Text("READY TO STEP OUT")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(HomeColor.textTertiary)
                Text("밖으로 나설 첫 규칙을\n만들어보세요")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("밖으로 나가면 제한된 앱이 다시 열려요")
                    .font(.headline)
                    .foregroundStyle(HomeColor.textSecondary)
                    .accessibilityIdentifier("home.emptyState.description")
            }

            VStack(spacing: 24) {
                Image(systemName: "door.left.hand.open")
                    .font(.system(size: 72, weight: .light))
                    .foregroundStyle(HomeColor.accent)
                    .frame(maxWidth: .infinity)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 14) {
                    emptyInstruction(
                        "01",
                        AppLocalizedCopy.string("기상 후 휴대폰 보는 시간을 줄여봐요")
                    )
                    emptyInstruction(
                        "02",
                        AppLocalizedCopy.string("취침 전 휴대폰 보는 시간을 줄여봐요")
                    )
                    emptyInstruction(
                        "03",
                        AppLocalizedCopy.string("근무 또는 학습 중 휴대폰 보는 시간을 줄여봐요")
                    )
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
                        ruleCard(item, at: index)
                            .padding(.horizontal, 22)
                            .tag(Optional(item.id))
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .padding(.horizontal, -20)
                .accessibilityIdentifier("home.rulePager.viewport")
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

    private func singleRuleCard(_ item: HomeRuleItem) -> some View {
        ruleCard(item, at: 0)
            .padding(.horizontal, 2)
            .frame(height: rulePagerHeight)
    }

    @ViewBuilder
    private func ruleCard(_ item: HomeRuleItem, at index: Int) -> some View {
        if model.restrictionStatus.isActive(item.rule) {
            RestrictionStatusView(
                item: item,
                rulePosition: index + 1,
                ruleCount: model.homeRules.count
            )
        } else {
            HomeRuleCard(
                item: item,
                rulePosition: index + 1,
                ruleCount: model.homeRules.count
            ) {
                model.beginEditingRule(id: item.id)
            }
        }
    }

    private var selectedRuleBinding: Binding<UUID?> {
        Binding(
            get: { model.selectedRuleID ?? model.homeRules.first?.id },
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
            Text(item.rule.name ?? displayPlaceName)
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
                        Text("\(displayPlaceName)에서 \(radiusLabel) 밖으로 나서면")
                            .font(.title2)
                            .fontWeight(.bold)
                        Text(item.applicationReleaseDescription)
                            .font(.subheadline)
                            .foregroundStyle(HomeColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                conditionRow(label: "LOCATION", value: "\(displayPlaceName) · \(radiusLabel)", identifier: "home.ruleCard.\(item.accessibilityID).location")
                conditionRow(label: "BLOCKED", value: item.applicationSummary, identifier: "home.ruleCard.\(item.accessibilityID).applications")

                Spacer(minLength: 0)
                Button(action: onEdit) {
                    Text("규칙 수정")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 14))
                        .contentShape(.rect)
                }
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
        HomeWeekdayFormatter.label(for: item.rule.weekdays)
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
    private var displayPlaceName: String {
        AppLocalizedCopy.savedPlaceName(item.savedPlace.name)
    }
    private static func clock(_ time: TimeOfDay) -> String {
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        return String(format: "%02d:%02d", hour, time.minute)
    }

    private static func period(_ time: TimeOfDay) -> String { time.hour < 12 ? "AM" : "PM" }

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

enum AppLiveActivityRecovery {
    static func makeSnapshot(
        rules: [RestrictionRuleSnapshot],
        savedPlaces: [SavedPlaceSnapshot],
        activeSnapshot: ActiveRestrictionSnapshot?,
        locationConditions: [LocationConditionSnapshot],
        now: Date
    ) throws -> RestrictionLiveActivitySnapshot? {
        let enabledRules = rules.filter(\.isEnabled)
        let currentRuleRevisions = enabledRules.reduce(into: [UUID: Int]()) {
            $0[$1.id] = $1.revision
        }
        let evaluation = RestrictionOccurrenceEvaluator.evaluate(
            snapshot: activeSnapshot,
            currentRuleRevisions: currentRuleRevisions,
            now: now
        )
        guard let occurrence = evaluation.representative else {
            return nil
        }
        guard let rule = enabledRules.first(where: { candidate in
            candidate.id == occurrence.ruleID
                && candidate.revision == occurrence.ruleRevision
        }) else {
            return nil
        }

        let placeName = savedPlaces.first(where: { place in
            place.id == rule.savedPlaceID
        }).map { SavedPlaceNamePolicy.normalized($0.name) }
        let ruleName = rule.name.map(SavedPlaceNamePolicy.normalized)
        guard let displayName = [ruleName, placeName]
            .compactMap({ $0 })
            .first(where: { !$0.isEmpty })
        else {
            return nil
        }

        let locationCondition = locationConditions.first { condition in
            condition.ruleID == occurrence.ruleID
                && condition.ruleRevision == occurrence.ruleRevision
        }
        let contentState = try LiveActivityContentPolicy.makeContentState(
            occurrence: occurrence,
            ruleDisplayName: displayName,
            radiusMeters: rule.radius.meters,
            locationCondition: locationCondition,
            hasAdditionalRestrictions: evaluation.hasAdditionalRestrictions,
            now: now
        )
        return RestrictionLiveActivitySnapshot(
            attributes: RestrictionLiveActivityAttributes(
                activityID: occurrence.ruleID,
                restrictionStartedAt: occurrence.activatedAt
            ),
            contentState: contentState
        )
    }
}

@MainActor
private struct AppEnvironment {
    typealias RuntimeRecovery = @Sendable () async -> AppLifecycleRecoveryResult?

    let model: AppModel
    let runtimeRecovery: RuntimeRecovery?
    let currentLocationProvider: any CurrentLocationProviding & LocationAuthorizationRequesting
    let defaultCoordinate: ReferenceLocation
    let applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)?
    let familyControlsAuthorizationStatusOverride:
        (@MainActor () -> FamilyControlsAuthorizationStatus)?
    let showsRestrictionProbe: Bool
    let permissionGuideModel: PermissionGuideModel?
    let permissionGuideRetryResult: String?
    let permissionGuideActionUpdate: PermissionGuideUpdate?
    let permissionOnboardingStateStore: PermissionOnboardingStateStore

    static func live() throws -> AppEnvironment {
        let container = try DependencyContainer.live()
        let locationSession = CoreLocationCurrentLocationSession()
        let liveActivityCoordinator = LiveActivityCoordinator(
            manager: SystemLiveActivityAdapter.live()
        )
        let lifecycleCoordinator = try AppLifecycleCoordinator.live(
            container: container,
            authorizationProvider: SystemAuthorizationProvider.forApplication(),
            reconcileLiveActivity: { rules in
                let savedPlaces = try await container.savedPlaceRepository
                    .loadSavedPlaceCollection()?.places ?? []
                let activeSnapshot = try await container.sharedSnapshotRepository
                    .loadActiveRestrictionSnapshot()
                let locationConditions = try await container.locationConditionRepository
                    .loadLocationConditionCollection()?.conditions ?? []
                let desiredActivity = try AppLiveActivityRecovery.makeSnapshot(
                    rules: rules,
                    savedPlaces: savedPlaces,
                    activeSnapshot: activeSnapshot,
                    locationConditions: locationConditions,
                    now: Date()
                )
                _ = await liveActivityCoordinator.reconcile(
                    context: .foreground,
                    desiredActivity: desiredActivity
                )
            }
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
            runtimeRecovery: {
                try? await lifecycleCoordinator.restore()
            },
            currentLocationProvider: CurrentLocationProvider(session: locationSession),
            defaultCoordinate: ReferenceLocation(latitude: 37.5665, longitude: 126.9780),
            applicationSelectionOverride: nil,
            familyControlsAuthorizationStatusOverride: nil,
            showsRestrictionProbe: false,
            permissionGuideModel: nil,
            permissionGuideRetryResult: nil,
            permissionGuideActionUpdate: nil,
            permissionOnboardingStateStore: PermissionOnboardingStateStore()
        )
    }
}

private struct UITestCurrentLocationProvider: CurrentLocationProviding,
    LocationAuthorizationRequesting
{
    func currentLocation() async throws -> ReferenceLocation {
        ReferenceLocation(latitude: 37.5665, longitude: 126.9780)
    }

    func requestWhenInUseAuthorization() async -> LocationAuthorizationStatus {
        .whenInUse
    }

    func requestAlwaysAuthorization() async -> LocationAuthorizationStatus {
        .always
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
        let permissionOnboardingStateStore = PermissionOnboardingStateStore(
            key: "permissionOnboarding.hasCompleted.uiTest.\(storeID)"
        )
        let fileManager = FileManager.default
        let root = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GetUpUITests", isDirectory: true)
            .appendingPathComponent(storeID, isDirectory: true)

        if shouldReset, fileManager.fileExists(atPath: root.path) {
            try fileManager.removeItem(at: root)
        }
        if shouldReset {
            permissionOnboardingStateStore.reset()
        }
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)

        let container = DependencyContainer(containerURL: root)
        let fixtures = Fixtures()
        let initialDraft = fixtures.initialDraft(for: scenario)
        let restrictionActivationRule = fixtures.restrictionActivationRule(
            name: scenario == "appstore-active" ? nil : "출근 준비"
        )
        let bootstrap: @Sendable () async throws -> Void = {
            guard shouldReset else {
                return
            }

            try await container.savedPlaceRepository.saveSavedPlaceCollection(
                SavedPlaceCollectionSnapshot(
                    revision: 1,
                    places: fixtures.places(for: scenario)
                )
            )

            if scenario == "three-saved-rules" || scenario == "startup-slow-recovery" {
                try await container.ruleRepository.saveRuleCollection(
                    RestrictionRuleCollectionSnapshot(
                        revision: 1,
                        rules: fixtures.rules
                    )
                )
            } else if scenario == "restriction-activation"
                || scenario == "appstore-active"
                || scenario?.hasPrefix("location-unavailable-") == true {
                try await container.ruleRepository.saveRuleCollection(
                    RestrictionRuleCollectionSnapshot(
                        revision: 1,
                        rules: [restrictionActivationRule]
                    )
                )
            }
        }

        let selectionOverride: (@MainActor () -> FamilyActivitySelection?)? =
            switch applicationResult {
            case "one-category":
                { @MainActor in categorySelection() }
            case .some:
                { @MainActor in FamilyActivitySelection(includeEntireCategory: true) }
            case nil:
                nil
            }
        let authorizationStatusOverride:
            (@MainActor () -> FamilyControlsAuthorizationStatus)? =
            scenario == "empty-editor-family-controls-undetermined"
            ? { @MainActor in .notDetermined }
            : nil

        return AppEnvironment(
            model: AppModel(
                ruleRepository: container.ruleRepository,
                savedPlaceRepository: container.savedPlaceRepository,
                now: { fixtureNow },
                calendar: Fixtures.calendar,
                timeZone: Fixtures.timeZone,
                applicationTokenCounter: { selection in
                    let targetCount = selection.restrictionTargetCount
                    return targetCount > 0
                        ? targetCount
                        : (selection.includeEntireCategory ? 1 : 0)
                },
                applicationCountForRule: fixtures.applicationCount,
                ruleAccessibilityID: fixtures.accessibilityID,
                initialEditorDraft: initialDraft,
                bootstrap: bootstrap,
                loadAppliedRestrictionState: {
                    let rule = restrictionActivationRule
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
            runtimeRecovery: runtimeRecovery(for: scenario),
            currentLocationProvider: UITestCurrentLocationProvider(),
            defaultCoordinate: fixtures.home.coordinate,
            applicationSelectionOverride: selectionOverride,
            familyControlsAuthorizationStatusOverride: authorizationStatusOverride,
            showsRestrictionProbe: scenario == "restriction-activation",
            permissionGuideModel: permissionGuideModel(
                for: scenario,
                onboardingStateStore: permissionOnboardingStateStore
            ),
            permissionGuideRetryResult: permissionGuideRetryResult,
            permissionGuideActionUpdate: permissionGuideActionUpdate(for: scenario),
            permissionOnboardingStateStore: permissionOnboardingStateStore
        )
    }

    private static func categorySelection() -> FamilyActivitySelection {
        let encodedData = try! JSONEncoder().encode(["data": Data([42])])
        let token = try! JSONDecoder().decode(
            ActivityCategoryToken.self,
            from: encodedData
        )
        var selection = FamilyActivitySelection(includeEntireCategory: true)
        selection.categoryTokens = [token]
        return selection
    }

    private static func runtimeRecovery(
        for scenario: String?
    ) -> AppEnvironment.RuntimeRecovery? {
        guard scenario == "startup-slow-recovery" else {
            return nil
        }

        return {
            do {
                try await ContinuousClock().sleep(for: .seconds(5))
            } catch {
                return nil
            }
            return AppLifecycleRecoveryResult(
                recoveredRuleIDs: [],
                failures: [],
                authorization: AuthorizationSnapshot(
                    familyControls: .approved,
                    locationAuthorization: .always,
                    locationAccuracy: .full,
                    backgroundRefresh: .available
                ),
                presentationState: .inactive
            )
        }
    }

    private static func permissionGuideModel(
        for scenario: String?,
        onboardingStateStore: PermissionOnboardingStateStore
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
        case "permission-family-controls-grant-onboarding",
             "permission-family-controls-deny-onboarding":
            return PermissionGuideModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .notDetermined,
                    locationAuthorization: .notDetermined,
                    locationAccuracy: .full,
                    backgroundRefresh: .available
                ),
                presentationState: .permissionRequired(
                    missingPermissions: [.familyControls, .alwaysLocation]
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
        case "permission-location-when-in-use",
             "permission-location-always-grant-recovery",
             "permission-location-always-decline-onboarding":
            return PermissionGuideModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .approved,
                    locationAuthorization: .whenInUse,
                    locationAccuracy: .full,
                    backgroundRefresh: .available
                ),
                presentationState: .permissionRequired(
                    missingPermissions: [.alwaysLocation]
                ),
                initialScreenKind: .location,
                presentationMode: scenario == "permission-location-always-grant-recovery"
                    ? .recovery
                    : .onboarding
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
        case "permission-onboarding-persistence":
            return PermissionGuideLaunchRouter.makeInitialModel(
                authorization: AuthorizationSnapshot(
                    familyControls: .notDetermined,
                    locationAuthorization: .notDetermined,
                    locationAccuracy: .full,
                    backgroundRefresh: .available
                ),
                presentationState: .permissionRequired(
                    missingPermissions: [.familyControls, .alwaysLocation]
                ),
                onboardingStateStore: onboardingStateStore
            )
        case "permission-onboarding-completion":
            if onboardingStateStore.hasCompleted {
                return PermissionGuideLaunchRouter.makeInitialModel(
                    authorization: approved,
                    presentationState: .inactive,
                    onboardingStateStore: onboardingStateStore
                )
            }
            return PermissionGuideModel(
                authorization: approved,
                presentationState: .inactive,
                initialScreenKind: .backgroundRefresh,
                presentationMode: .onboarding
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

    private static func permissionGuideActionUpdate(
        for scenario: String?
    ) -> PermissionGuideUpdate? {
        let authorization: AuthorizationSnapshot
        switch scenario {
        case "permission-family-controls-grant-onboarding":
            authorization = AuthorizationSnapshot(
                familyControls: .approved,
                locationAuthorization: .notDetermined,
                locationAccuracy: .full,
                backgroundRefresh: .available
            )
        case "permission-family-controls-deny-onboarding":
            authorization = AuthorizationSnapshot(
                familyControls: .denied,
                locationAuthorization: .notDetermined,
                locationAccuracy: .full,
                backgroundRefresh: .available
            )
        case "permission-location-always-grant-recovery":
            authorization = AuthorizationSnapshot(
                familyControls: .approved,
                locationAuthorization: .always,
                locationAccuracy: .full,
                backgroundRefresh: .available
            )
        case "permission-location-always-decline-onboarding":
            authorization = AuthorizationSnapshot(
                familyControls: .approved,
                locationAuthorization: .whenInUse,
                locationAccuracy: .full,
                backgroundRefresh: .available
            )
        default:
            return nil
        }

        return PermissionGuideUpdate(
            authorization: authorization,
            presentationState: authorization.familyControls == .approved
                && authorization.locationAuthorization == .always
                ? .inactive
                : .permissionRequired(
                    missingPermissions: Set(
                        [
                            authorization.familyControls == .approved
                                ? nil
                                : RequiredPermission.familyControls,
                            authorization.locationAuthorization == .always
                                ? nil
                                : RequiredPermission.alwaysLocation,
                        ].compactMap { $0 }
                    )
                )
        )
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
        let library = SavedPlaceSnapshot(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000503")!,
            name: "도서관",
            coordinate: ReferenceLocation(latitude: 37.5796, longitude: 126.9770),
            createdAt: now,
            updatedAt: now
        )

        func places(for scenario: String?) -> [SavedPlaceSnapshot] {
            if scenario == "unused-custom-place-editor" {
                return [home, work, library]
            }
            return [home, work]
        }

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
                    radius: .meters250
                ),
            ]
        }

        func restrictionActivationRule(name: String?) -> RestrictionRuleSnapshot {
            makeRule(
                id: Self.rule1ID,
                name: name,
                weekdays: [.monday, .tuesday, .wednesday, .thursday, .friday],
                start: TimeOfDay(hour: 6, minute: 0),
                end: TimeOfDay(hour: 9, minute: 0),
                place: home,
                radius: .meters1000
            )
        }

        func initialDraft(for scenario: String?) -> RuleEditorDraft? {
            switch scenario {
            case "empty-editor", "empty-editor-family-controls-undetermined",
                "unused-custom-place-editor":
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
            name: String?,
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
