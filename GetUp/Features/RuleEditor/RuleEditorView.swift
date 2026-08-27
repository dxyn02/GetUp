@preconcurrency import FamilyControls
import SwiftUI

@MainActor
struct RuleEditorView: View {
    typealias SaveAction = @MainActor (
        RuleEditorDraft,
        [SavedPlaceSnapshot]
    ) async throws -> Void
    typealias DeleteAction = @MainActor () async throws -> Void
    typealias DeleteSavedPlaceAction = @MainActor (UUID) async throws -> Void

    @Bindable private var model: RuleEditorModel

    private let currentLocationProvider: any CurrentLocationProviding
    private let defaultCoordinate: ReferenceLocation
    private let familyActivityAdapter: FamilyActivitySelectionAdapter
    private let applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)?
    private let familyControlsAuthorizationStatusOverride:
        (@MainActor () -> FamilyControlsAuthorizationStatus)?
    private let onPresentFamilyControlsPermissionGuide:
        @MainActor (FamilyControlsAuthorizationStatus) -> Void
    private let onOpenSettings: () -> Void
    private let onSave: SaveAction
    private let onDelete: DeleteAction?
    private let onDeleteSavedPlace: DeleteSavedPlaceAction

    @State private var presentedTimeBoundary: TimeRangeBoundary?
    @State private var locationPickerModel: LocationPickerModel?
    @State private var isLocationPickerPresented = false
    @State private var isApplicationPickerPresented = false
    @State private var applicationPickerGuidance: String?
    @State private var saveState: RuleEditorSaveState = .idle
    @State private var deleteState: RuleEditorDeleteState = .idle
    @State private var isDeleteConfirmationPresented = false
    @State private var isRestrictionGuardPresented = false

    init(
        model: RuleEditorModel,
        currentLocationProvider: any CurrentLocationProviding,
        defaultCoordinate: ReferenceLocation,
        familyActivityAdapter: FamilyActivitySelectionAdapter? = nil,
        applicationSelectionOverride: (@MainActor () -> FamilyActivitySelection?)? = nil,
        familyControlsAuthorizationStatusOverride:
            (@MainActor () -> FamilyControlsAuthorizationStatus)? = nil,
        onPresentFamilyControlsPermissionGuide:
            @escaping @MainActor (FamilyControlsAuthorizationStatus) -> Void = { _ in },
        onOpenSettings: @escaping () -> Void,
        onSave: @escaping SaveAction,
        onDelete: DeleteAction? = nil,
        onDeleteSavedPlace: @escaping DeleteSavedPlaceAction
    ) {
        self.model = model
        self.currentLocationProvider = currentLocationProvider
        self.defaultCoordinate = defaultCoordinate
        self.familyActivityAdapter = familyActivityAdapter
            ?? FamilyActivitySelectionAdapter(selection: model.activitySelection)
        self.applicationSelectionOverride = applicationSelectionOverride
        self.familyControlsAuthorizationStatusOverride =
            familyControlsAuthorizationStatusOverride
        self.onPresentFamilyControlsPermissionGuide =
            onPresentFamilyControlsPermissionGuide
        self.onOpenSettings = onOpenSettings
        self.onSave = onSave
        self.onDelete = onDelete
        self.onDeleteSavedPlace = onDeleteSavedPlace
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                editorHeader
                scheduleCard
                weekdaySection
                conditionCard

                if model.mode == .editing {
                    enabledSection
                }

                if onDelete != nil {
                    deleteSection
                }

                if case .failed = saveState {
                    saveFailureCard
                }

                if case .failed = deleteState {
                    deleteFailureCard
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
        .navigationDestination(item: $presentedTimeBoundary) { boundary in
            timePickerDestination(boundary: boundary)
        }
        .navigationDestination(isPresented: $isLocationPickerPresented) {
            locationPickerDestination
        }
        .alert("규칙을 삭제할까요?", isPresented: $isDeleteConfirmationPresented) {
            Button("취소", role: .cancel) {}
            Button("삭제", role: .destructive) {
                deleteRule()
            }
        } message: {
            Text("규칙만 삭제되며 저장한 장소는 다른 규칙에서 계속 사용할 수 있어요.")
        }
        .alert(
            Text(RestrictionCopy.guardTitle),
            isPresented: $isRestrictionGuardPresented
        ) {
            Button(RestrictionCopy.guardConfirm, role: .cancel) {}
        } message: {
            Text(
                model.modificationGuard?.message
                    ?? AppLocalizedCopy.string("조건이 종료되면 규칙을 변경할 수 있어요.")
            )
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
                    AppLocalizedCopy.string("종료 시각은 시작 시각으로부터 15분 이상, 12시간 이내여야 해요."),
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
        .accessibilityLabel(
            boundary == .start
                ? AppLocalizedCopy.string("시작 시간")
                : AppLocalizedCopy.string("종료 시간")
        )
        .accessibilityValue(TimePickerComponents(time: time).displayName)
        .accessibilityHint(AppLocalizedCopy.string("시간 선택 화면을 엽니다."))
        .accessibilityIdentifier(identifier)
    }

    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            WeekdayPicker(selection: $model.weekdays)

            if model.validationErrors.contains(.weekdaysRequired) {
                validationMessage(
                    AppLocalizedCopy.string("반복할 요일을 하나 이상 선택해 주세요."),
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
        .accessibilityHint(AppLocalizedCopy.string("선택 화면을 엽니다."))
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder
    private var conditionValidationMessages: some View {
        VStack(alignment: .leading, spacing: 6) {
            if hasLocationValidationError {
                validationMessage(
                    AppLocalizedCopy.string("기준 위치를 선택해 주세요."),
                    identifier: "ruleEditor.location.validation"
                )
            }

            if model.validationErrors.contains(.applicationTokenRequired) {
                validationMessage(
                    AppLocalizedCopy.string("제한할 앱을 하나 이상 선택해 주세요."),
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

    private var enabledSection: some View {
        Toggle(isOn: enabledBinding) {
            VStack(alignment: .leading, spacing: 4) {
                Text("규칙 활성화")
                    .font(.headline)
                Text("끄면 예약된 시간에도 앱을 제한하지 않아요.")
                    .font(.footnote)
                    .foregroundStyle(RuleEditorColor.textSecondary)
            }
        }
        .tint(RuleEditorColor.accent)
        .padding(18)
        .background(RuleEditorColor.surface, in: .rect(cornerRadius: 22))
        .accessibilityHint("이 규칙의 자동 제한을 켜거나 끕니다.")
        .accessibilityIdentifier("ruleEditor.enabled")
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { model.isEnabled },
            set: { isEnabled in
                if !model.setEnabled(isEnabled) {
                    isRestrictionGuardPresented = true
                }
            }
        )
    }

    private var deleteSection: some View {
        Button(role: .destructive) {
            if model.canModify {
                isDeleteConfirmationPresented = true
            } else {
                isRestrictionGuardPresented = true
            }
        } label: {
            Group {
                if deleteState == .deleting {
                    ProgressView()
                        .tint(RuleEditorColor.error)
                } else {
                    Label("규칙 삭제", systemImage: "trash")
                }
            }
            .font(.body)
            .fontWeight(.semibold)
            .frame(maxWidth: .infinity, minHeight: 52)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.roundedRectangle(radius: 16))
        .tint(RuleEditorColor.error)
        .disabled(deleteState == .deleting || saveState == .saving)
        .accessibilityHint("확인 후 이 규칙을 삭제합니다.")
        .accessibilityIdentifier("ruleEditor.delete")
    }

    private var deleteFailureCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("삭제하지 못했어요", systemImage: "exclamationmark")
                .font(.headline)
            Text("규칙이 다른 곳에서 변경되었거나 현재 삭제할 수 없는 상태예요. 다시 불러온 뒤 시도해 주세요.")
                .font(.footnote)
                .foregroundStyle(RuleEditorColor.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(RuleEditorColor.error.opacity(0.14), in: .rect(cornerRadius: 24))
        .accessibilityIdentifier("ruleEditor.deleteError")
    }

    private var saveButton: some View {
        VStack(spacing: 0) {
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
                .frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(
                    model.canSave ? RuleEditorColor.background : RuleEditorColor.textTertiary
                )
                .background(
                    model.canSave ? RuleEditorColor.accent : RuleEditorColor.surfaceElevated,
                    in: .rect(cornerRadius: 18)
                )
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!model.canSave || saveState == .saving)
        .accessibilityLabel(
            saveState == .failed
                ? AppLocalizedCopy.string("다시 저장")
                : AppLocalizedCopy.string("완료")
        )
            .accessibilityHint(saveAccessibilityHint)
            .accessibilityIdentifier(
                saveState == .failed ? "ruleSaveError.retry" : "ruleEditor.save"
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(RuleEditorColor.background)
    }

    private func timePickerDestination(boundary: TimeRangeBoundary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SCHEDULE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(RuleEditorColor.accent)

            Text(
                boundary == .start
                    ? AppLocalizedCopy.string("시작 시각")
                    : AppLocalizedCopy.string("종료 시각")
            )
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top, 6)
                .accessibilityIdentifier("ruleEditor.\(boundary.identifier).pickerTitle")

            Text("시·분·AM/PM을 위아래로 밀어 선택해요")
                .font(.subheadline)
                .foregroundStyle(RuleEditorColor.textSecondary)
                .padding(.top, 4)
                .accessibilityIdentifier("ruleEditor.timePicker.instructions")

            TimeRangePicker(
                boundary: boundary,
                startTime: $model.startTime,
                endTime: $model.endTime
            )
            .id(boundary)
            .padding(.top, 24)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .background(RuleEditorColor.background.ignoresSafeArea())
        .foregroundStyle(RuleEditorColor.textPrimary)
        .safeAreaInset(edge: .bottom) {
            Button {
                completeTimeSelection(boundary)
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            canCompleteTimeSelection(boundary)
                                ? RuleEditorColor.accent
                                : RuleEditorColor.surfaceElevated
                        )

                    Text("완료")
                        .font(.body)
                        .fontWeight(.bold)
                        .foregroundStyle(
                            canCompleteTimeSelection(boundary)
                                ? RuleEditorColor.background
                                : RuleEditorColor.textTertiary
                        )
                }
                .frame(maxWidth: .infinity, minHeight: 64, maxHeight: 64)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!canCompleteTimeSelection(boundary))
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            .accessibilityHint(
                canCompleteTimeSelection(boundary)
                    ? AppLocalizedCopy.string("선택한 시각을 적용합니다.")
                    : AppLocalizedCopy.string("종료 시각을 시작 시각부터 15분 이상, 12시간 이내로 설정해 주세요.")
            )
            .accessibilityIdentifier("ruleEditor.timePicker.done")
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 40)
            .background(RuleEditorColor.background)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(RuleEditorColor.background, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .tint(RuleEditorColor.accent)
    }

    private func completeTimeSelection(_ boundary: TimeRangeBoundary) {
        switch boundary {
        case .start:
            presentedTimeBoundary = .end
        case .end:
            presentedTimeBoundary = nil
        }
    }

    private func canCompleteTimeSelection(_ boundary: TimeRangeBoundary) -> Bool {
        boundary == .start || !hasTimeValidationError
    }

    @ViewBuilder
    private var locationPickerDestination: some View {
        if let locationPickerModel {
            LocationPickerView(
                model: locationPickerModel,
                radius: $model.radius,
                onApply: applyLocationSelection,
                onOpenSettings: onOpenSettings,
                onDeleteSavedPlace: { id in
                    try await onDeleteSavedPlace(id)
                    locationPickerModel.removeSavedPlace(id: id)
                }
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
            return AppLocalizedCopy.string("장소 설정")
        }

        return "\(AppLocalizedCopy.savedPlaceName(place.name)) · \(RadiusPicker.displayName(for: model.radius))"
    }

    private var applicationSummary: String {
        switch model.activitySelection.restrictionSelectionSummary(
            countedTargets: model.applicationTokenCount
        ) {
        case .none:
            return AppLocalizedCopy.string("앱 선택")
        case .exact(let count):
            return AppLocalizedCopy.format("%@개 앱 선택됨", String(count))
        case .multiple:
            return AppLocalizedCopy.string("여러 앱 선택됨")
        }
    }

    private var hasTimeValidationError: Bool {
        let errors = model.validationErrors
        return errors.contains(.invalidTimeOfDay)
            || errors.contains(.startAndEndMustDiffer)
            || errors.contains(.timeRangeTooShort)
            || errors.contains(.timeRangeTooLong)
    }

    private var hasLocationValidationError: Bool {
        let errors = model.validationErrors
        return errors.contains(.savedPlaceRequired)
            || errors.contains(.savedPlaceNotFound)
            || errors.contains(.invalidReferenceLocation)
    }

    private var saveAccessibilityHint: String {
        if !model.canSave {
            return AppLocalizedCopy.string("필수 조건을 모두 설정하면 저장할 수 있습니다.")
        }
        if saveState == .failed {
            return AppLocalizedCopy.string("보존된 입력 내용으로 저장을 다시 시도합니다.")
        }
        return AppLocalizedCopy.string("이 규칙을 저장합니다.")
    }

    private func presentLocationPicker() {
        if locationPickerModel == nil {
            locationPickerModel = LocationPickerModel(
                savedPlaces: model.savedPlaces,
                initialSavedPlaceID: model.selectedSavedPlaceID,
                initialCoordinate: model.selectedSavedPlace?.coordinate,
                defaultCoordinate: defaultCoordinate,
                currentLocationProvider: currentLocationProvider
            )
        }
        isLocationPickerPresented = true
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

        let status = familyControlsAuthorizationStatusOverride?()
            ?? familyActivityAdapter.authorizationStatus()
        switch status {
        case .approved:
            applicationPickerGuidance = nil
            isApplicationPickerPresented = true
        case .denied, .notDetermined:
            applicationPickerGuidance = nil
            onPresentFamilyControlsPermissionGuide(status)
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

    private func deleteRule() {
        guard let onDelete, deleteState != .deleting else {
            return
        }

        deleteState = .deleting
        Task { @MainActor in
            do {
                try await onDelete()
                deleteState = .idle
            } catch is CancellationError {
                deleteState = .idle
            } catch {
                deleteState = .failed
            }
        }
    }
}

private enum RuleEditorSaveState: Equatable {
    case idle
    case saving
    case failed
}

private enum RuleEditorDeleteState: Equatable {
    case idle
    case deleting
    case failed
}
