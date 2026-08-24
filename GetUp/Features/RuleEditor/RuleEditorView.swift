@preconcurrency import FamilyControls
import SwiftUI

@MainActor
struct RuleEditorView: View {
    typealias SaveAction = @MainActor (
        RuleEditorDraft,
        [SavedPlaceSnapshot]
    ) async throws -> Void

    @Bindable private var model: RuleEditorModel

    private let currentLocationProvider: any CurrentLocationProviding
    private let defaultCoordinate: ReferenceLocation
    private let familyActivityAdapter: FamilyActivitySelectionAdapter
    private let applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)?
    private let onOpenSettings: () -> Void
    private let onSave: SaveAction

    @State private var presentedTimeBoundary: TimeRangeBoundary?
    @State private var locationPickerModel: LocationPickerModel?
    @State private var isLocationPickerPresented = false
    @State private var isPlaceNamePromptPresented = false
    @State private var placeNameInput = ""
    @State private var isApplicationPickerPresented = false
    @State private var applicationPickerGuidance: String?
    @State private var saveState: RuleEditorSaveState = .idle

    init(
        model: RuleEditorModel,
        currentLocationProvider: any CurrentLocationProviding,
        defaultCoordinate: ReferenceLocation,
        familyActivityAdapter: FamilyActivitySelectionAdapter? = nil,
        applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)? = nil,
        onOpenSettings: @escaping () -> Void,
        onSave: @escaping SaveAction
    ) {
        self.model = model
        self.currentLocationProvider = currentLocationProvider
        self.defaultCoordinate = defaultCoordinate
        self.familyActivityAdapter = familyActivityAdapter
            ?? FamilyActivitySelectionAdapter(selection: model.activitySelection)
        self.applicationSelectionOverride = applicationSelectionOverride
        self.onOpenSettings = onOpenSettings
        self.onSave = onSave
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                editorHeader
                scheduleCard
                weekdaySection
                conditionCard

                if case .failed = saveState {
                    saveFailureCard
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .background(RuleEditorColor.background.ignoresSafeArea())
        .foregroundStyle(RuleEditorColor.textPrimary)
        .safeAreaInset(edge: .bottom) {
            saveButton
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(RuleEditorColor.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .sheet(item: $presentedTimeBoundary) { boundary in
            timePickerSheet(boundary: boundary)
        }
        .navigationDestination(isPresented: $isLocationPickerPresented) {
            locationPickerDestination
        }
        .alert("장소 이름", isPresented: $isPlaceNamePromptPresented) {
            TextField("예: 집", text: $placeNameInput)
                .accessibilityIdentifier("locationPicker.placeName")
            Button("취소", role: .cancel) {}
            Button("저장") {
                confirmPlaceName()
            }
        } message: {
            Text("다른 규칙에서도 다시 사용할 수 있도록 이름을 입력해 주세요.")
        }
        .familyActivityPicker(
            isPresented: $isApplicationPickerPresented,
            selection: applicationSelection
        )
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .preferredColorScheme(.dark)
    }

    private var editorHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("FOCUS RULE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(RuleEditorColor.accent)

            TextField(
                "",
                text: $model.ruleName,
                prompt: Text("규칙 이름 설정")
                    .foregroundStyle(RuleEditorColor.textSecondary)
            )
            .font(.largeTitle)
            .fontWeight(.bold)
            .textFieldStyle(.plain)
            .submitLabel(.done)
            .accessibilityLabel("규칙 이름")
            .accessibilityHint("선택 사항입니다.")
            .accessibilityIdentifier("ruleEditor.name")
        }
    }

    private var scheduleCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SCHEDULE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(RuleEditorColor.textTertiary)

            timeRow(boundary: .start)
            timeRow(boundary: .end)

            if hasTimeValidationError {
                validationMessage(
                    "종료 시각은 시작 시각으로부터 최소 15분 이후여야 해요.",
                    identifier: "ruleEditor.time.validation"
                )
            }
        }
        .padding(20)
        .background(RuleEditorColor.surface, in: .rect(cornerRadius: 24))
    }

    private func timeRow(boundary: TimeRangeBoundary) -> some View {
        let time = boundary == .start ? model.startTime : model.endTime
        let title = boundary == .start ? "START" : "END"
        let identifier = boundary == .start ? "ruleEditor.startTime" : "ruleEditor.endTime"

        return Button {
            presentedTimeBoundary = boundary
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(RuleEditorColor.textTertiary)

                    Text(TimePickerComponents(time: time).displayName)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(RuleEditorColor.textPrimary)
                }

                Spacer()

                Image(systemName: "chevron.forward")
                    .font(.subheadline)
                    .foregroundStyle(RuleEditorColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(RuleEditorColor.surfaceElevated.opacity(0.62), in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(boundary == .start ? "시작 시간" : "종료 시간")
        .accessibilityValue(TimePickerComponents(time: time).displayName)
        .accessibilityHint("시간 선택 화면을 엽니다.")
        .accessibilityIdentifier(identifier)
    }

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WeekdayPicker(selection: $model.weekdays)

            if model.validationErrors.contains(.weekdaysRequired) {
                validationMessage(
                    "반복할 요일을 하나 이상 선택해 주세요.",
                    identifier: "ruleEditor.weekday.validation"
                )
            }
        }
    }

    private var conditionCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                conditionRow(
                    title: "LOCATION",
                    detail: locationSummary,
                    systemImage: "location.circle",
                    identifier: "ruleEditor.locationRow",
                    summaryIdentifier: "ruleEditor.locationSummary",
                    action: presentLocationPicker
                )

                Divider()
                    .overlay(RuleEditorColor.surfaceElevated)
                    .padding(.leading, 16)

                conditionRow(
                    title: "BLOCKED",
                    detail: applicationSummary,
                    systemImage: "square.grid.3x3.fill",
                    identifier: "ruleEditor.applicationRow",
                    summaryIdentifier: "ruleEditor.applicationSummary",
                    action: requestApplicationPicker
                )
            }
            .background(RuleEditorColor.surface, in: .rect(cornerRadius: 22))

            conditionValidationMessages
        }
    }

    private func conditionRow(
        title: String,
        detail: String,
        systemImage: String,
        identifier: String,
        summaryIdentifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(RuleEditorColor.accent)
                    .frame(width: 26)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(RuleEditorColor.textTertiary)

                    Text(detail)
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundStyle(RuleEditorColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier(summaryIdentifier)
                }

                Spacer()

                Image(systemName: "chevron.forward")
                    .font(.subheadline)
                    .foregroundStyle(RuleEditorColor.textTertiary)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
            .padding(.horizontal, 16)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint("선택 화면을 엽니다.")
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var conditionValidationMessages: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasLocationValidationError {
                validationMessage(
                    "기준 위치를 선택해 주세요.",
                    identifier: "ruleEditor.location.validation"
                )
            }

            if model.validationErrors.contains(.applicationTokenRequired) {
                validationMessage(
                    "제한할 앱을 하나 이상 선택해 주세요.",
                    identifier: "ruleEditor.application.validation"
                )
            }

            if let applicationPickerGuidance {
                validationMessage(
                    applicationPickerGuidance,
                    identifier: "ruleEditor.application.guidance"
                )
            }
        }
    }

    private func validationMessage(_ message: String, identifier: String) -> some View {
        Label(message, systemImage: "exclamationmark.circle.fill")
            .font(.footnote)
            .foregroundStyle(RuleEditorColor.error)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(identifier)
    }

    private var saveFailureCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("저장 실패", systemImage: "exclamationmark")
                .font(.headline)
                .foregroundStyle(RuleEditorColor.textPrimary)

            Text("입력한 내용은 그대로 유지돼요. 잠시 후 다시 시도해 주세요.")
                .font(.footnote)
                .foregroundStyle(RuleEditorColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RuleEditorColor.error.opacity(0.14), in: .rect(cornerRadius: 24))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("ruleSaveError.card")
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Group {
                if case .saving = saveState {
                    ProgressView()
                        .tint(RuleEditorColor.background)
                } else {
                    Text("완료")
                }
            }
            .font(.body)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, minHeight: 58)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: 18))
        .tint(model.canSave ? RuleEditorColor.accent : RuleEditorColor.surfaceElevated)
        .foregroundStyle(model.canSave ? RuleEditorColor.background : RuleEditorColor.textTertiary)
        .disabled(!model.canSave || saveState == .saving)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(RuleEditorColor.background)
        .accessibilityLabel(saveState == .failed ? "다시 저장" : "완료")
        .accessibilityHint(saveAccessibilityHint)
        .accessibilityIdentifier(
            saveState == .failed ? "ruleSaveError.retry" : "ruleEditor.save"
        )
    }

    private func timePickerSheet(boundary: TimeRangeBoundary) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(boundary == .start ? "시작 시간" : "종료 시간")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    TimeRangePicker(
                        boundary: boundary,
                        startTime: $model.startTime,
                        endTime: $model.endTime
                    )
                }
                .padding()
            }
            .background(RuleEditorColor.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("완료") {
                        presentedTimeBoundary = nil
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder
    private var locationPickerDestination: some View {
        if let locationPickerModel {
            LocationPickerView(
                model: locationPickerModel,
                radius: $model.radius,
                onRequestPlaceName: requestPlaceName,
                onApply: applyLocationSelection,
                onOpenSettings: onOpenSettings
            )
        } else {
            ProgressView()
        }
    }

    private var applicationSelection: Binding<FamilyActivitySelection> {
        Binding(
            get: { model.activitySelection },
            set: { selection in
                familyActivityAdapter.replaceSelection(with: selection)
                model.replaceActivitySelection(with: selection)
                applicationPickerGuidance = nil
            }
        )
    }

    private var locationSummary: String {
        guard let place = model.selectedSavedPlace else {
            return "장소 설정"
        }

        return "\(place.name) · \(RadiusPicker.displayName(for: model.radius))"
    }

    private var applicationSummary: String {
        let count = model.applicationTokenCount
        return count == 0 ? "앱 선택" : "\(count)개 앱 선택됨"
    }

    private var hasTimeValidationError: Bool {
        let errors = model.validationErrors
        return errors.contains(.invalidTimeOfDay)
            || errors.contains(.startAndEndMustDiffer)
            || errors.contains(.timeRangeTooShort)
    }

    private var hasLocationValidationError: Bool {
        let errors = model.validationErrors
        return errors.contains(.savedPlaceRequired)
            || errors.contains(.savedPlaceNotFound)
            || errors.contains(.invalidReferenceLocation)
    }

    private var saveAccessibilityHint: String {
        if !model.canSave {
            return "필수 조건을 모두 설정하면 저장할 수 있습니다."
        }
        if saveState == .failed {
            return "보존된 입력 내용으로 저장을 다시 시도합니다."
        }
        return "이 규칙을 저장합니다."
    }

    private func presentLocationPicker() {
        locationPickerModel = LocationPickerModel(
            savedPlaces: model.savedPlaces,
            initialSavedPlaceID: model.selectedSavedPlaceID,
            initialCoordinate: model.selectedSavedPlace?.coordinate,
            defaultCoordinate: defaultCoordinate,
            currentLocationProvider: currentLocationProvider
        )
        isLocationPickerPresented = true
    }

    private func requestPlaceName() {
        placeNameInput = locationPickerModel?.placeName ?? ""
        isPlaceNamePromptPresented = true
    }

    private func confirmPlaceName() {
        locationPickerModel?.confirm(placeName: placeNameInput)
        if locationPickerModel?.completion != nil {
            applyLocationSelection()
        }
    }

    private func applyLocationSelection() {
        guard let completion = locationPickerModel?.completion else {
            return
        }

        model.applyLocationCompletion(completion)
        isLocationPickerPresented = false
        locationPickerModel = nil
    }

    private func requestApplicationPicker() {
        if let selection = applicationSelectionOverride?() {
            familyActivityAdapter.replaceSelection(with: selection)
            model.replaceActivitySelection(with: selection)
            applicationPickerGuidance = nil
            return
        }

        Task { @MainActor in
            do {
                let status = try await familyActivityAdapter
                    .requestIndividualAuthorizationIfNeeded()
                switch status {
                case .approved:
                    applicationPickerGuidance = nil
                    isApplicationPickerPresented = true
                case .denied:
                    applicationPickerGuidance = "스크린 타임 권한을 허용한 뒤 다시 시도해 주세요."
                case .notDetermined:
                    applicationPickerGuidance = "앱을 선택하려면 스크린 타임 권한이 필요해요."
                }
            } catch is CancellationError {
                return
            } catch {
                applicationPickerGuidance = "스크린 타임 권한을 확인하지 못했어요. 다시 시도해 주세요."
            }
        }
    }

    private func save() {
        guard model.canSave, saveState != .saving else {
            return
        }

        saveState = .saving
        Task { @MainActor in
            do {
                try await onSave(model.preparedDraft, model.savedPlaces)
                saveState = .idle
            } catch is CancellationError {
                saveState = .idle
            } catch {
                saveState = .failed
            }
        }
    }
}

private enum RuleEditorSaveState: Equatable {
    case idle
    case saving
    case failed
}
