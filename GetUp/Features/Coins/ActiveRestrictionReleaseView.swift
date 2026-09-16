import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class ActiveRestrictionReleaseRouter {
    typealias ConsumePendingRoute = @Sendable (
        Date,
        Set<String>
    ) async throws -> PendingAppRoute?

    enum ConsumptionState: Equatable, Sendable {
        case idle
        case consuming
        case consumed
        case failed
    }

    @ObservationIgnored private let consumePendingRoute: ConsumePendingRoute

    private(set) var destination: PendingAppRouteDestination?
    private(set) var preferredRuleID: UUID?
    private(set) var consumptionState: ConsumptionState = .idle

    init(
        consumePendingRoute: @escaping ConsumePendingRoute = { _, _ in nil }
    ) {
        self.consumePendingRoute = consumePendingRoute
    }

    func consumeIfEligible(
        now: Date,
        activeOccurrenceIDs: Set<String>
    ) async {
        guard consumptionState != .consuming else { return }
        consumptionState = .consuming

        do {
            let route = try await consumePendingRoute(now, activeOccurrenceIDs)
            guard !Task.isCancelled else {
                consumptionState = .idle
                return
            }
            destination = route?.destination
            consumptionState = .consumed
        } catch is CancellationError {
            consumptionState = .idle
        } catch {
            destination = nil
            consumptionState = .failed
        }
    }

    func present(_ destination: PendingAppRouteDestination) {
        self.destination = destination
    }

    func prefer(ruleID: UUID) {
        preferredRuleID = ruleID
    }

    func clearPreferredRule() {
        preferredRuleID = nil
    }

    func present(for availability: ActiveRestrictionReleaseAvailability) {
        switch availability {
        case .insufficientBalance:
            present(.coinStore)
        case .iCloudRecoveryRequired:
            present(.iCloudRecovery)
        case .ledgerResetRequired:
            present(.ledgerReset)
        case .reconciliationRequired:
            present(.reconciliation)
        case .ready, .noActiveRestriction, .releaseFailed:
            break
        }
    }

    func dismissDestination() {
        destination = nil
    }
}

@MainActor
@Observable
final class ActiveRestrictionReleaseInstrumentation {
    private(set) var reservationCount = 0
    private(set) var committedCount = 0
    private(set) var remainingOccurrenceCount: Int
    let holdsExecution: Bool
    let createsMonthlyAllowanceOnRequest: Bool

    private var continuation:
        CheckedContinuation<ActiveRestrictionReleaseExecutionResult, Never>?

    init(
        remainingOccurrenceCount: Int,
        holdsExecution: Bool,
        createsMonthlyAllowanceOnRequest: Bool = false
    ) {
        self.remainingOccurrenceCount = remainingOccurrenceCount
        self.holdsExecution = holdsExecution
        self.createsMonthlyAllowanceOnRequest = createsMonthlyAllowanceOnRequest
    }

    func execute(
        occurrence: RestrictionOccurrence,
        balance: CoinBalanceSnapshot,
        remainingOccurrences: [RestrictionOccurrence]
    ) async -> ActiveRestrictionReleaseExecutionResult {
        _ = occurrence
        reservationCount += 1

        if holdsExecution {
            return await withCheckedContinuation { continuation = $0 }
        }
        return commit(balance: balance, remainingOccurrences: remainingOccurrences)
    }

    func complete(
        balance: CoinBalanceSnapshot,
        remainingOccurrences: [RestrictionOccurrence]
    ) {
        guard let continuation else { return }
        self.continuation = nil
        continuation.resume(
            returning: commit(
                balance: balance,
                remainingOccurrences: remainingOccurrences
            )
        )
    }

    private func commit(
        balance: CoinBalanceSnapshot,
        remainingOccurrences: [RestrictionOccurrence]
    ) -> ActiveRestrictionReleaseExecutionResult {
        committedCount += 1
        remainingOccurrenceCount = remainingOccurrences.count
        return .released(
            fundingSource: .monthlyFree,
            balance: balance,
            remainingOccurrences: remainingOccurrences
        )
    }
}

@MainActor
struct ActiveRestrictionReleaseConfiguration {
    let model: ActiveRestrictionReleaseModel
    let router: ActiveRestrictionReleaseRouter
    let now: () -> Date
    let timeZone: TimeZone
    let refresh: () async -> Void
    let onReleaseCompleted: () async -> Void
    let instrumentation: ActiveRestrictionReleaseInstrumentation?

    init(
        model: ActiveRestrictionReleaseModel,
        router: ActiveRestrictionReleaseRouter,
        now: @escaping () -> Date = Date.init,
        timeZone: TimeZone = .autoupdatingCurrent,
        refresh: @escaping () async -> Void = {},
        onReleaseCompleted: @escaping () async -> Void = {},
        instrumentation: ActiveRestrictionReleaseInstrumentation? = nil
    ) {
        self.model = model
        self.router = router
        self.now = now
        self.timeZone = timeZone
        self.refresh = refresh
        self.onReleaseCompleted = onReleaseCompleted
        self.instrumentation = instrumentation
    }
}

@MainActor
struct ActiveRestrictionReleaseView: View {
    @Environment(\.dismiss) private var dismiss

    @Bindable var model: ActiveRestrictionReleaseModel
    @Bindable var router: ActiveRestrictionReleaseRouter

    let ruleDisplayNames: [UUID: String]
    let now: () -> Date
    let timeZone: TimeZone
    let refresh: () async -> Void
    let onReleaseCompleted: () async -> Void
    let instrumentation: ActiveRestrictionReleaseInstrumentation?

    init(
        configuration: ActiveRestrictionReleaseConfiguration,
        ruleDisplayNames: [UUID: String]
    ) {
        model = configuration.model
        router = configuration.router
        now = configuration.now
        timeZone = configuration.timeZone
        refresh = configuration.refresh
        onReleaseCompleted = configuration.onReleaseCompleted
        instrumentation = configuration.instrumentation
        self.ruleDisplayNames = ruleDisplayNames
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                details
                balanceSection
                statusSection
                primaryAction
                instrumentationSection
            }
            .padding(20)
        }
        .background(HomeColor.background.ignoresSafeArea())
        .foregroundStyle(HomeColor.textPrimary)
        .navigationTitle(AppLocalizedCopy.string("coinRelease.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppLocalizedCopy.string("coinRelease.action.close")) {
                    router.clearPreferredRule()
                    dismiss()
                }
                    .disabled(model.phase == .processing)
            }
        }
        .interactiveDismissDisabled(model.phase == .processing)
        .alert(
            AppLocalizedCopy.string("coinRelease.confirmation.title"),
            isPresented: confirmationBinding
        ) {
            Button(AppLocalizedCopy.string("coinRelease.action.cancel"), role: .cancel) {
                model.cancelConfirmation()
            }
            Button(AppLocalizedCopy.string("coinRelease.action.release")) {
                Task { await model.confirmRelease() }
            }
        } message: {
            Text(confirmationMessage)
        }
        .navigationDestination(item: destinationBinding) { destination in
            ActiveRestrictionReleaseDestinationView(destination: destination)
        }
        .task {
            await refresh()
            guard !Task.isCancelled else { return }
            if let preferredRuleID = router.preferredRuleID,
               let occurrence = model.activeOccurrences.first(where: {
                   $0.ruleID == preferredRuleID
               }) {
                _ = model.selectOccurrence(id: occurrence.id)
            }
            await router.consumeIfEligible(
                now: now(),
                activeOccurrenceIDs: Set(model.activeOccurrences.map(\.id))
            )
        }
        .onChange(of: model.phase) { _, phase in
            switch phase {
            case .released:
                Task { await onReleaseCompleted() }
            case .blocked(let availability):
                router.present(for: availability)
            case .idle, .confirmationRequested, .processing:
                break
            }
        }
        .onDisappear {
            router.clearPreferredRule()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AppLocalizedCopy.string("coinRelease.eyebrow"))
                .font(.caption)
                .fontWeight(.bold)
                .foregroundStyle(HomeColor.accent)
            Text(selectedRuleName)
                .font(.largeTitle)
                .fontWeight(.bold)
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(selectedRuleName)
                .font(.headline)
                .accessibilityIdentifier("coinRelease.target")
            if model.activeOccurrences.count > 1 {
                occurrencePicker
            }
            detailRow(
                icon: "ticket",
                title: AppLocalizedCopy.string("coinRelease.cost.title"),
                value: AppLocalizedCopy.string("coinRelease.cost.value"),
                identifier: "coinRelease.cost"
            )
            detailRow(
                icon: "clock",
                title: AppLocalizedCopy.string("coinRelease.endsAt.title"),
                value: endsAtText,
                identifier: "coinRelease.endsAt"
            )
            detailRow(
                icon: "square.stack.3d.up",
                title: AppLocalizedCopy.string("coinRelease.remaining.title"),
                value: remainingRestrictionText,
                identifier: "coinRelease.remainingRestrictions"
            )
        }
        .padding(18)
        .background(HomeColor.surface, in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coinRelease.details")
    }

    private var occurrencePicker: some View {
        Picker(
            AppLocalizedCopy.string("coinRelease.target.picker"),
            selection: selectedOccurrenceBinding
        ) {
            ForEach(model.activeOccurrences, id: \.id) { occurrence in
                Text(displayName(for: occurrence)).tag(occurrence.id)
            }
        }
        .pickerStyle(.menu)
        .disabled(model.phase != .idle)
    }

    private var balanceSection: some View {
        HStack(spacing: 12) {
            balanceCard(
                title: AppLocalizedCopy.string("coinRelease.balance.free"),
                value: model.balance.freeAvailable,
                identifier: "coinRelease.balance.free"
            )
            balanceCard(
                title: AppLocalizedCopy.string("coinRelease.balance.purchased"),
                value: model.balance.purchasedAvailable,
                identifier: "coinRelease.balance.purchased"
            )
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.phase {
        case .processing:
            Label(
                AppLocalizedCopy.string("coinRelease.processing"),
                systemImage: "arrow.triangle.2.circlepath"
            )
                .foregroundStyle(HomeColor.textSecondary)
                .accessibilityIdentifier("coinRelease.processing")
        case .released(let fundingSource):
            Label(releasedText(for: fundingSource), systemImage: "checkmark.circle.fill")
                .foregroundStyle(HomeColor.accent)
        case .blocked(.releaseFailed):
            Label(
                AppLocalizedCopy.string("coinRelease.failed"),
                systemImage: "exclamationmark.circle"
            )
                .foregroundStyle(HomeColor.error)
        case .idle, .confirmationRequested, .blocked:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.availability {
        case .ready:
            Button(AppLocalizedCopy.string("coinRelease.action.release")) {
                _ = model.requestConfirmation()
            }
            .buttonStyle(ReleasePrimaryButtonStyle())
            .disabled(!model.canRequestConfirmation)
            .accessibilityHint(AppLocalizedCopy.string("coinRelease.action.release.hint"))
            .accessibilityIdentifier("coinRelease.requestConfirmation")
        case .insufficientBalance:
            routeButton(
                AppLocalizedCopy.string("coinRelease.action.coinStore"),
                destination: .coinStore
            )
        case .iCloudRecoveryRequired:
            routeButton(
                AppLocalizedCopy.string("coinRelease.action.iCloudRecovery"),
                destination: .iCloudRecovery
            )
        case .ledgerResetRequired:
            routeButton(
                AppLocalizedCopy.string("coinRelease.action.ledgerReset"),
                destination: .ledgerReset
            )
        case .reconciliationRequired:
            routeButton(
                AppLocalizedCopy.string("coinRelease.action.reconciliation"),
                destination: .reconciliation
            )
        case .releaseFailed:
            Button(AppLocalizedCopy.string("coinRelease.action.retry")) {
                Task { await refresh() }
            }
            .buttonStyle(ReleasePrimaryButtonStyle())
        case .noActiveRestriction:
            Text(AppLocalizedCopy.string("coinRelease.noActiveRestriction"))
                .foregroundStyle(HomeColor.textSecondary)
        }
    }

    @ViewBuilder
    private var instrumentationSection: some View {
        if let instrumentation {
            VStack(spacing: 8) {
                Text(String(instrumentation.reservationCount))
                    .accessibilityIdentifier("coinRelease.test.reservationCount")
                Text(String(instrumentation.committedCount))
                    .accessibilityIdentifier("coinRelease.test.committedCount")
                Text(String(instrumentation.remainingOccurrenceCount))
                    .accessibilityIdentifier("coinRelease.test.remainingOccurrenceCount")
                Text(String(instrumentation.createsMonthlyAllowanceOnRequest))
                    .accessibilityIdentifier("coinRelease.test.createsMonthlyAllowanceOnRequest")
                if instrumentation.holdsExecution, model.phase == .processing {
                    Button(AppLocalizedCopy.string("coinRelease.test.complete")) {
                        guard let balance = decrementedFixtureBalance else { return }
                        instrumentation.complete(
                            balance: balance,
                            remainingOccurrences: Array(model.activeOccurrences.dropFirst())
                        )
                    }
                    .accessibilityIdentifier("coinRelease.test.complete")
                }
            }
            .font(.caption2)
            .foregroundStyle(HomeColor.textTertiary)
        }
    }

    private func detailRow(
        icon: String,
        title: String,
        value: String,
        identifier: String
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(HomeColor.accent)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(HomeColor.textTertiary)
                Text(value)
                    .font(.body)
                    .fontWeight(.semibold)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(identifier)
            }
            Spacer(minLength: 0)
        }
    }

    private func balanceCard(
        title: String,
        value: Int,
        identifier: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(HomeColor.textSecondary)
            Text(String(value))
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityIdentifier(identifier)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 18))
    }

    private func routeButton(
        _ title: String,
        destination: PendingAppRouteDestination
    ) -> some View {
        Button(title) { router.present(destination) }
            .buttonStyle(ReleasePrimaryButtonStyle())
    }

    private var selectedOccurrenceBinding: Binding<String> {
        Binding(
            get: { model.selectedOccurrence?.id ?? "" },
            set: { _ = model.selectOccurrence(id: $0) }
        )
    }

    private var confirmationBinding: Binding<Bool> {
        Binding(
            get: { model.phase == .confirmationRequested },
            set: { _ in }
        )
    }

    private var destinationBinding: Binding<PendingAppRouteDestination?> {
        Binding(
            get: { router.destination },
            set: { if $0 == nil { router.dismissDestination() } }
        )
    }

    private var selectedRuleName: String {
        model.selectedOccurrence.map(displayName(for:))
            ?? AppLocalizedCopy.string("coinRelease.target.fallback")
    }

    private func displayName(for occurrence: RestrictionOccurrence) -> String {
        ruleDisplayNames[occurrence.ruleID]
            ?? AppLocalizedCopy.string("coinRelease.target.fallback")
    }

    private var endsAtText: String {
        guard let occurrence = model.selectedOccurrence else {
            return AppLocalizedCopy.string("coinRelease.endsAt.unavailable")
        }
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.timeZone = timeZone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: occurrence.endAt)
    }

    private var remainingRestrictionText: String {
        let remaining = max(0, model.activeOccurrences.count - 1)
        return remaining == 0
            ? AppLocalizedCopy.string("coinRelease.remaining.single")
            : AppLocalizedCopy.format("coinRelease.remaining.multiple", remaining)
    }

    private var confirmationMessage: String {
        AppLocalizedCopy.format(
            "coinRelease.confirmation.message",
            selectedRuleName,
            remainingRestrictionText
        )
    }

    private func releasedText(for fundingSource: ReleaseFundingSource) -> String {
        fundingSource == .monthlyFree
            ? AppLocalizedCopy.string("coinRelease.released.free")
            : AppLocalizedCopy.string("coinRelease.released.purchased")
    }

    private var decrementedFixtureBalance: CoinBalanceSnapshot? {
        try? CoinBalanceSnapshot(
            purchasedAvailable: model.balance.purchasedAvailable,
            currentMonthID: model.balance.currentMonthID,
            freeAvailable: max(0, model.balance.freeAvailable - 1),
            syncState: model.balance.syncState,
            syncedAt: model.balance.syncedAt,
            ledgerEpochID: model.balance.ledgerEpochID,
            hadConfirmedLedger: model.balance.hadConfirmedLedger
        )
    }
}

private struct ReleasePrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.bold)
            .foregroundStyle(HomeColor.background)
            .frame(maxWidth: .infinity, minHeight: 54)
            .background(
                HomeColor.accent.opacity(configuration.isPressed ? 0.75 : 1),
                in: .rect(cornerRadius: 18)
            )
            .contentShape(.rect)
    }
}

struct ReleaseHandoffDisplayDetails: Equatable, Sendable {
    let ruleName: String?
    let endsAt: Date?
    let fundingSource: ReleaseFundingSource?
    let remainingRestrictionCount: Int?
    let freeAvailable: Int?
    let purchasedAvailable: Int?
}

enum ReleaseHandoffAction: Equatable, Sendable {
    case acknowledge
    case retry
    case close
    case openCoinStore
    case openRecovery
}

@MainActor
struct ActiveRestrictionReleaseHandoffView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let route: PendingAppRoute
    let details: ReleaseHandoffDisplayDetails?
    let isActionRunning: Bool
    let retryWaitSecondsOverride: Int?
    let onAction: (ReleaseHandoffAction) -> Void

    private var outcome: PendingAppRouteTerminalOutcome? {
        route.state == .terminal ? route.terminalOutcome : nil
    }

    private var stateName: String {
        switch outcome {
        case .completed: "completed"
        case .retryable: "retryable"
        case .insufficient: "insufficient"
        case .recoveryRequired: "recoveryRequired"
        case nil: "processing"
        }
    }

    var body: some View {
        if outcome == .recoveryRequired {
            ActiveRestrictionReleaseDestinationView(destination: .iCloudRecovery)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("coinRelease.destination.iCloudRecovery")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("닫기") { onAction(.close) }
                    }
                }
        } else {
            VStack(spacing: 0) {
                ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statusIcon
                    Text(eyebrow)
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(HomeColor.accent)
                    Text(title)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(HomeColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("releaseHandoff.statusTitle")
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(HomeColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    statusCard
                    statusFootnote
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                actionBar
            }
            .background(HomeColor.background.ignoresSafeArea())
            .navigationBarBackButtonHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("releaseHandoff.\(stateName).screen")
        }
    }

    @ViewBuilder
    private var statusIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(HomeColor.surface)
            if outcome == nil {
                if reduceMotion {
                    Image(systemName: "hourglass")
                        .foregroundStyle(HomeColor.accent)
                } else {
                    ProgressView()
                        .tint(HomeColor.accent)
                }
            } else {
                Image(systemName: iconName)
                    .font(.system(size: 31, weight: .bold))
                    .foregroundStyle(iconColor)
                    .accessibilityLabel(iconAccessibilityLabel)
                    .accessibilityIdentifier("releaseHandoff.\(stateName).icon")
            }
        }
        .frame(width: 64, height: 64)
        .accessibilityIdentifier(outcome == nil
            ? "releaseHandoff.processing.progress"
            : "releaseHandoff.\(stateName).icon")
    }

    private var eyebrow: String {
        switch outcome {
        case .completed: "RELEASE COMPLETE"
        case .retryable: "ACTION NEEDED"
        case .insufficient: "NO RELEASE AVAILABLE"
        case .recoveryRequired: ""
        case nil: "RELEASE IN PROGRESS"
        }
    }

    private var title: String {
        switch outcome {
        case .completed: "해제가 완료됐어요"
        case .retryable: "해제를 완료하지 못했어요"
        case .insufficient: "사용할 수 있는 해제권이 없어요"
        case .recoveryRequired: ""
        case nil: "해제 상태를 확인하고 있어요"
        }
    }

    private var message: String {
        switch outcome {
        case .completed: "이번 적용 구간의 제한을 안전하게 해제했어요."
        case .retryable: "요청 결과를 확정하지 못했어요. 잠시 후 같은 요청으로 다시 시도할 수 있어요."
        case .insufficient: "무료 해제권과 구매 코인 잔액을 최신 장부에서 확인했어요."
        case .recoveryRequired: ""
        case nil: "잠시만 기다려 주세요. 같은 요청을 안전하게 확인하고 있어요."
        }
    }

    private var iconName: String {
        switch outcome {
        case .completed: "checkmark"
        case .retryable: "exclamationmark"
        case .insufficient: "xmark"
        case .recoveryRequired, nil: "hourglass"
        }
    }

    private var iconColor: Color {
        outcome == .retryable || outcome == .insufficient
            ? HomeColor.error : HomeColor.accent
    }

    private var iconAccessibilityLabel: String {
        outcome == .insufficient ? "사용할 수 없음" : title
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(cardEyebrow)
                .font(.caption2.weight(.bold))
                .foregroundStyle(HomeColor.accent)
            Text(cardTitle)
                .font(.body.weight(.semibold))
                .foregroundStyle(HomeColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(outcome == .retryable
                    ? "releaseHandoff.fundingResult" : "releaseHandoff.cardTitle")
            if outcome == .insufficient {
                HStack(spacing: 6) {
                    Text("무료")
                    Text(details?.freeAvailable.map { "\($0)회" } ?? "—")
                        .accessibilityIdentifier("releaseHandoff.balance.free")
                    Text("· 구매")
                    Text(details?.purchasedAvailable.map { "\($0)개" } ?? "—")
                        .accessibilityIdentifier("releaseHandoff.balance.purchased")
                }
                .font(.subheadline)
                .foregroundStyle(HomeColor.textSecondary)
            }
            Text(cardDetail)
                .font(.subheadline)
                .foregroundStyle(HomeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(outcome == .completed
                    ? "releaseHandoff.fundingResult" : "releaseHandoff.cardDetail")
            if outcome == .completed, let remaining = details?.remainingRestrictionCount {
                Text(remaining == 0 ? "남은 제한 없음" : "다른 규칙 \(remaining)개 유지")
                    .font(.subheadline)
                    .foregroundStyle(HomeColor.textSecondary)
                    .accessibilityIdentifier("releaseHandoff.remainingRestrictions")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 22))
        .overlay {
            if outcome == .completed || outcome == .retryable {
                RoundedRectangle(cornerRadius: 22)
                    .strokeBorder(outcome == .completed ? HomeColor.accent : HomeColor.error)
            }
        }
    }

    private var cardEyebrow: String {
        switch outcome {
        case .completed: "CONFIRMED RESULT"
        case .retryable: "BALANCE PROTECTED"
        case .insufficient: "CURRENT BALANCE"
        case .recoveryRequired: ""
        case nil: "CURRENT REQUEST"
        }
    }

    private var cardTitle: String {
        switch outcome {
        case .retryable: "코인은 차감되지 않았어요"
        case .insufficient: "현재 잔액"
        case .completed, .recoveryRequired, nil:
            details?.ruleName ?? "이번 적용 구간"
        }
    }

    private var cardDetail: String {
        switch outcome {
        case .completed:
            switch details?.fundingSource {
            case .monthlyFree: return "무료 해제권 1회 사용"
            case .purchased: return "구매 코인 1개 사용"
            case nil: return "해제 결과를 확인했어요"
            }
        case .retryable: return "제한 유지 · 잔액 보존"
        case .insufficient: return "제한은 계속돼요"
        case .recoveryRequired: return ""
        case nil:
            let end = details?.endsAt.map {
                $0.formatted(date: .omitted, time: .shortened) + "까지 · "
            } ?? ""
            return end + "무료 해제권 우선 · 없으면 구매 코인 1개"
        }
    }

    @ViewBuilder
    private var statusFootnote: some View {
        switch outcome {
        case .completed:
            Text("다른 규칙의 제한은 계속돼요.")
                .foregroundStyle(HomeColor.textSecondary)
        case .retryable:
            Text("제한은 유지되고 잔액도 그대로예요.")
                .foregroundStyle(HomeColor.error)
                .accessibilityIdentifier("releaseHandoff.restrictionMaintained")
        case .insufficient:
            Text("코인을 구매한 뒤 새 해제를 요청할 수 있어요.")
                .foregroundStyle(HomeColor.textSecondary)
        case .recoveryRequired:
            EmptyView()
        case nil:
            VStack(alignment: .leading, spacing: 2) {
                Text("확인되는 동안 제한은 유지돼요.")
                    .accessibilityIdentifier("releaseHandoff.restrictionMaintained")
                Text("앱을 닫아도 다음 실행에서 이어서 확인해요.")
                    .accessibilityIdentifier("releaseHandoff.resumeMessage")
            }
            .foregroundStyle(HomeColor.textSecondary)
        }
    }

    @ViewBuilder
    private var actionBar: some View {
        if outcome == .completed || outcome == .retryable || outcome == .insufficient {
            VStack(spacing: 8) {
                if outcome == .retryable {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let seconds = retryWaitSecondsOverride ?? max(0, Int(ceil(
                            (route.retryAfter ?? .distantPast)
                                .timeIntervalSince(context.date)
                        )))
                        Button(seconds == 0 ? "다시 시도" : "\(seconds)초 뒤 다시 시도") {
                            onAction(.retry)
                        }
                        .disabled(seconds > 0)
                        .disabled(isActionRunning)
                        .buttonStyle(ReleaseHandoffPrimaryButtonStyle())
                        .accessibilityIdentifier("releaseHandoff.primaryAction")
                    }
                } else {
                    Button(outcome == .completed ? "확인" : "코인 구매") {
                        onAction(outcome == .completed ? .acknowledge : .openCoinStore)
                    }
                    .buttonStyle(ReleaseHandoffPrimaryButtonStyle())
                    .disabled(isActionRunning)
                    .accessibilityIdentifier("releaseHandoff.primaryAction")
                }
                if outcome == .retryable || outcome == .insufficient {
                    Button("닫기") { onAction(.close) }
                        .disabled(isActionRunning)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(HomeColor.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("releaseHandoff.secondaryAction")
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(HomeColor.background)
        }
    }
}

private struct ReleaseHandoffPrimaryButtonStyle: ButtonStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.bold))
            .foregroundStyle(configuration.isPressed ? HomeColor.background.opacity(0.8) : HomeColor.background)
            .frame(maxWidth: .infinity, minHeight: dynamicTypeSize.isAccessibilitySize ? 64 : 52)
            .background(
                HomeColor.accent.opacity(configuration.isPressed ? 0.75 : 1),
                in: .capsule
            )
    }
}

struct ActiveRestrictionReleaseDestinationView: View {
    let destination: PendingAppRouteDestination

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(HomeColor.accent)
            Text(title)
                .font(.title)
                .fontWeight(.bold)
            Text(message)
                .foregroundStyle(HomeColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
#if DEBUG
            if destination == .iCloudRecovery, let diagnosticText {
                Text("DEBUG: \(diagnosticText)")
                    .font(.caption.monospaced())
                    .foregroundStyle(HomeColor.textSecondary)
                    .textSelection(.enabled)
            }
#endif
            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HomeColor.background.ignoresSafeArea())
        .foregroundStyle(HomeColor.textPrimary)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("coinRelease.destination.\(destination.rawValue)")
    }

    private var title: String {
        switch destination {
        case .releaseProcessing:
            AppLocalizedCopy.string("coinRelease.destination.reconciliation.title")
        case .coinStore: AppLocalizedCopy.string("coinRelease.destination.coinStore.title")
        case .iCloudRecovery:
            AppLocalizedCopy.string("coinRelease.destination.iCloudRecovery.title")
        case .ledgerReset:
            AppLocalizedCopy.string("coinRelease.destination.ledgerReset.title")
        case .reconciliation:
            AppLocalizedCopy.string("coinRelease.destination.reconciliation.title")
        }
    }

    private var message: String {
        switch destination {
        case .releaseProcessing:
            AppLocalizedCopy.string("coinRelease.destination.reconciliation.message")
        case .coinStore:
            AppLocalizedCopy.string("coinRelease.destination.coinStore.message")
        case .iCloudRecovery:
            AppLocalizedCopy.string("coinRelease.destination.iCloudRecovery.message")
        case .ledgerReset:
            AppLocalizedCopy.string("coinRelease.destination.ledgerReset.message")
        case .reconciliation:
            AppLocalizedCopy.string("coinRelease.destination.reconciliation.message")
        }
    }

    private var icon: String {
        switch destination {
        case .releaseProcessing: "hourglass"
        case .coinStore: "cart"
        case .iCloudRecovery: "icloud"
        case .ledgerReset: "exclamationmark.icloud"
        case .reconciliation: "arrow.triangle.2.circlepath"
        }
    }

#if DEBUG
    private var diagnosticText: String? {
        guard
            let identifier = SharedIdentifiers.appGroupIdentifier(),
            let value = UserDefaults(suiteName: identifier)?.dictionary(
                forKey: SharedIdentifiers.shieldActionDiagnosticDefaultsKey
            ),
            let stage = value["stage"] as? String
        else {
            return nil
        }
        if let detail = value["detail"] as? String {
            return "\(stage), \(detail)"
        }
        return stage
    }
#endif
}
