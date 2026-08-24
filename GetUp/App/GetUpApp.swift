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
    @State private var model: AppModel
    private let currentLocationProvider: any CurrentLocationProviding
    private let defaultCoordinate: ReferenceLocation
    private let applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)?

    init(environment: AppEnvironment) {
        _model = State(initialValue: environment.model)
        currentLocationProvider = environment.currentLocationProvider
        defaultCoordinate = environment.defaultCoordinate
        applicationSelectionOverride = environment.applicationSelectionOverride
    }

    var body: some View {
        NavigationStack {
            content
                .navigationDestination(isPresented: editorIsPresented) {
                    editorDestination
                }
        }
        .preferredColorScheme(.dark)
        .task {
            guard model.loadingState == .idle else {
                return
            }
            await model.load()
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
            HomeView(model: model)
        case .failed:
            LoadFailureView {
                Task { await model.load() }
            }
        }
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
    @Bindable var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if model.homeRules.isEmpty {
                    emptyState
                } else {
                    rulePager
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
        }
        .background(HomeColor.background.ignoresSafeArea())
        .foregroundStyle(HomeColor.textPrimary)
        .toolbarBackground(HomeColor.background, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !model.homeRules.isEmpty {
                newRuleButton
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GETUP")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(HomeColor.accent)

            Text(model.homeRules.isEmpty ? "집중을 시작해 볼까요?" : "준비된 규칙")
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 22) {
            Image(systemName: "door.left.hand.open")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(HomeColor.accent)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("시간과 장소를 정하면")
                    .font(.title2)
                    .fontWeight(.bold)
                Text("그곳을 벗어나거나 시간이 끝날 때까지\n선택한 앱에서 잠시 멀어질 수 있어요.")
                    .font(.body)
                    .foregroundStyle(HomeColor.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button("첫 규칙 만들기") {
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
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(HomeColor.surface, in: .rect(cornerRadius: 28))
    }

    private var rulePager: some View {
        VStack(spacing: 14) {
            VStack(spacing: 0) {
                TabView(selection: selectedRuleBinding) {
                    ForEach(model.homeRules) { item in
                        HomeRuleCard(item: item) {
                            model.beginEditingRule(id: item.id)
                        }
                        .padding(.horizontal, 2)
                        .tag(item.id)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .frame(height: 440)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("home.rulePager")

            Text(pageIndicatorLabel)
                .font(.footnote)
                .fontWeight(.bold)
                .foregroundStyle(HomeColor.textSecondary)
                .accessibilityIdentifier("home.rulePageIndicator")

            Text("좌우로 밀어 모든 규칙 보기")
                .font(.caption)
                .foregroundStyle(HomeColor.textTertiary)
        }
    }

    private var newRuleButton: some View {
        Button("새 규칙") {
            model.beginCreatingRule()
        }
        .fontWeight(.bold)
        .frame(maxWidth: .infinity, minHeight: 56)
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .tint(HomeColor.accent)
        .foregroundStyle(HomeColor.background)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(HomeColor.background)
        .accessibilityIdentifier("home.createRule")
    }

    private var selectedRuleBinding: Binding<UUID> {
        Binding(
            get: { model.selectedRuleID ?? model.homeRules[0].id },
            set: { model.selectedRuleID = $0 }
        )
    }

    private var pageIndicatorLabel: String {
        let selectedIndex = model.homeRules.firstIndex {
            $0.id == model.selectedRuleID
        } ?? 0
        return "\(selectedIndex + 1) / \(model.homeRules.count)"
    }
}

private struct HomeRuleCard: View {
    let item: HomeRuleItem
    let onEdit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.isScheduledToday ? "TODAY" : "NEXT")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(HomeColor.accent)
                    Text(item.rule.name ?? item.savedPlace.name)
                        .font(.title)
                        .fontWeight(.bold)
                }

                Spacer()

                Button("수정") {
                    onEdit()
                }
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID).edit")
            }

            Divider().overlay(HomeColor.surfaceElevated)

            VStack(alignment: .leading, spacing: 8) {
                Text(timeLabel)
                    .font(.title2)
                    .fontWeight(.bold)
                    .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID).time")

                Text(weekdayLabel)
                    .font(.subheadline)
                    .foregroundStyle(HomeColor.textSecondary)
                    .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID).schedule")
            }

            VStack(spacing: 0) {
                conditionRow(
                    icon: "location.fill",
                    text: "\(item.savedPlace.name) · \(RadiusPicker.displayName(for: item.rule.radius))",
                    identifier: "home.ruleCard.\(item.accessibilityID).location"
                )
                Divider().overlay(HomeColor.surfaceElevated)
                conditionRow(
                    icon: "square.grid.3x3.fill",
                    text: "\(item.applicationCount)개 앱",
                    identifier: "home.ruleCard.\(item.accessibilityID).applications"
                )
            }
            .background(HomeColor.surfaceElevated.opacity(0.52), in: .rect(cornerRadius: 18))

            Text(nextOccurrenceLabel)
                .font(.footnote)
                .foregroundStyle(HomeColor.textTertiary)
        }
        .padding(22)
        .frame(maxWidth: .infinity, minHeight: 410, alignment: .topLeading)
        .background(HomeColor.surface, in: .rect(cornerRadius: 28))
        .overlay {
            RoundedRectangle(cornerRadius: 28)
                .stroke(HomeColor.surfaceElevated, lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("home.ruleCard.\(item.accessibilityID)")
    }

    private func conditionRow(
        icon: String,
        text: String,
        identifier: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(HomeColor.accent)
                .frame(width: 24)
                .accessibilityHidden(true)
            Text(text)
                .font(.body)
                .fontWeight(.semibold)
                .accessibilityIdentifier(identifier)
            Spacer()
        }
        .frame(minHeight: 54)
        .padding(.horizontal, 14)
    }

    private var timeLabel: String {
        "\(Self.time(item.rule.startTime))–\(Self.time(item.rule.endTime))"
    }

    private var weekdayLabel: String {
        Weekday.allCases
            .filter(item.rule.weekdays.contains)
            .map(\.shortKoreanName)
            .joined(separator: " · ")
    }

    private var nextOccurrenceLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "M월 d일 EEEE"
        return item.isScheduledToday
            ? "오늘 적용되는 규칙"
            : "다음 적용 · \(formatter.string(from: item.nextStart))"
    }

    private static func time(_ time: TimeOfDay) -> String {
        let period = time.hour < 12 ? "AM" : "PM"
        let hour = time.hour % 12 == 0 ? 12 : time.hour % 12
        return String(format: "%02d:%02d %@", hour, time.minute, period)
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

private enum HomeColor {
    static let background = Color(red: 8 / 255, green: 9 / 255, blue: 11 / 255)
    static let surface = Color(red: 21 / 255, green: 23 / 255, blue: 27 / 255)
    static let surfaceElevated = Color(red: 32 / 255, green: 35 / 255, blue: 41 / 255)
    static let accent = Color(red: 244 / 255, green: 214 / 255, blue: 0)
    static let textPrimary = Color.white
    static let textSecondary = Color(red: 166 / 255, green: 168 / 255, blue: 173 / 255)
    static let textTertiary = Color(red: 125 / 255, green: 128 / 255, blue: 135 / 255)
    static let error = Color(red: 255 / 255, green: 105 / 255, blue: 97 / 255)
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
    let currentLocationProvider: any CurrentLocationProviding
    let defaultCoordinate: ReferenceLocation
    let applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)?

    static func live() throws -> AppEnvironment {
        let container = try DependencyContainer.live()
        let locationSession = CoreLocationCurrentLocationSession()
        return AppEnvironment(
            model: AppModel(
                ruleRepository: container.ruleRepository,
                savedPlaceRepository: container.savedPlaceRepository
            ),
            currentLocationProvider: CurrentLocationProvider(session: locationSession),
            defaultCoordinate: ReferenceLocation(latitude: 37.5665, longitude: 126.9780),
            applicationSelectionOverride: nil
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
                now: { Fixtures.now },
                calendar: Fixtures.calendar,
                timeZone: Fixtures.timeZone,
                applicationTokenCounter: { selection in
                    selection.includeEntireCategory ? 1 : 0
                },
                applicationCountForRule: fixtures.applicationCount,
                ruleAccessibilityID: fixtures.accessibilityID,
                initialEditorDraft: initialDraft,
                bootstrap: bootstrap
            ),
            currentLocationProvider: UITestCurrentLocationProvider(),
            defaultCoordinate: fixtures.home.coordinate,
            applicationSelectionOverride: selectionOverride
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
