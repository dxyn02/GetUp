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

    private var continuation:
        CheckedContinuation<ActiveRestrictionReleaseExecutionResult, Never>?

    init(remainingOccurrenceCount: Int, holdsExecution: Bool) {
        self.remainingOccurrenceCount = remainingOccurrenceCount
        self.holdsExecution = holdsExecution
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
        .navigationTitle("현재 제한 해제")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("닫기") {
                    router.clearPreferredRule()
                    dismiss()
                }
                    .disabled(model.phase == .processing)
            }
        }
        .interactiveDismissDisabled(model.phase == .processing)
        .alert(
            instrumentation == nil ? "해제권을 사용할까요?" : "coinRelease.confirmation",
            isPresented: confirmationBinding
        ) {
            Button("취소", role: .cancel) {
                model.cancelConfirmation()
            }
            Button("해제권 1회 사용") {
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
            Text("이번 구간만 해제해요")
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
                title: "사용 비용",
                value: "이번 달 무료 해제권 우선 · 없으면 코인 1개",
                identifier: "coinRelease.cost"
            )
            detailRow(
                icon: "clock",
                title: "해제 종료",
                value: endsAtText,
                identifier: "coinRelease.endsAt"
            )
            detailRow(
                icon: "square.stack.3d.up",
                title: "남는 제한",
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
        Picker("해제할 규칙", selection: selectedOccurrenceBinding) {
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
                title: "이번 달 무료",
                value: model.balance.freeAvailable,
                identifier: "coinRelease.balance.free"
            )
            balanceCard(
                title: "구매 코인",
                value: model.balance.purchasedAvailable,
                identifier: "coinRelease.balance.purchased"
            )
        }
    }

    @ViewBuilder
    private var statusSection: some View {
        switch model.phase {
        case .processing:
            Label("해제 상태를 확인하고 있어요", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(HomeColor.textSecondary)
                .accessibilityIdentifier("coinRelease.processing")
        case .released(let fundingSource):
            Label(releasedText(for: fundingSource), systemImage: "checkmark.circle.fill")
                .foregroundStyle(HomeColor.accent)
        case .blocked(.releaseFailed):
            Label("해제하지 못했어요. 잔액은 사용되지 않았어요.", systemImage: "exclamationmark.circle")
                .foregroundStyle(HomeColor.error)
        case .idle, .confirmationRequested, .blocked:
            EmptyView()
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch model.availability {
        case .ready:
            Button("해제권 1회 사용") {
                _ = model.requestConfirmation()
            }
            .buttonStyle(ReleasePrimaryButtonStyle())
            .disabled(!model.canRequestConfirmation)
            .accessibilityHint("대상과 비용을 다시 확인하는 창을 엽니다.")
            .accessibilityIdentifier("coinRelease.requestConfirmation")
        case .insufficientBalance:
            routeButton("코인 상점으로 이동", destination: .coinStore)
        case .iCloudRecoveryRequired:
            routeButton("iCloud 잔액 복구", destination: .iCloudRecovery)
        case .ledgerResetRequired:
            routeButton("장부 복구 옵션 확인", destination: .ledgerReset)
        case .reconciliationRequired:
            routeButton("해제 상태 다시 확인", destination: .reconciliation)
        case .releaseFailed:
            Button("다시 확인") {
                Task { await refresh() }
            }
            .buttonStyle(ReleasePrimaryButtonStyle())
        case .noActiveRestriction:
            Text("현재 해제할 제한이 없어요")
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
                if instrumentation.holdsExecution, model.phase == .processing {
                    Button("테스트 해제 완료") {
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
        model.selectedOccurrence.map(displayName(for:)) ?? "현재 제한"
    }

    private func displayName(for occurrence: RestrictionOccurrence) -> String {
        ruleDisplayNames[occurrence.ruleID] ?? "현재 제한"
    }

    private var endsAtText: String {
        guard let occurrence = model.selectedOccurrence else { return "확인 불가" }
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
            ? "이 규칙을 해제하면 다른 규칙 제한은 없어요"
            : "다른 규칙 \(remaining)개의 제한은 계속 유지돼요"
    }

    private var confirmationMessage: String {
        "‘\(selectedRuleName)’의 이번 구간을 해제합니다. \(remainingRestrictionText)"
    }

    private func releasedText(for fundingSource: ReleaseFundingSource) -> String {
        fundingSource == .monthlyFree
            ? "무료 해제권으로 이번 구간을 해제했어요"
            : "구매 코인 1개로 이번 구간을 해제했어요"
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

private struct ActiveRestrictionReleaseDestinationView: View {
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
        case .coinStore: "코인 상점"
        case .iCloudRecovery: "iCloud 잔액 복구"
        case .ledgerReset: "장부 복구 옵션"
        case .reconciliation: "해제 상태 확인"
        }
    }

    private var message: String {
        switch destination {
        case .coinStore:
            "사용 가능한 해제권이 없어요. 구매할 코인 상품과 가격을 확인해 주세요."
        case .iCloudRecovery:
            "iCloud 연결과 최신 장부 상태를 확인한 뒤 다시 시도해 주세요."
        case .ledgerReset:
            "장부 삭제 여부를 확인해야 해요. 구매 잔액을 임의로 복원하거나 초기화하지 않습니다."
        case .reconciliation:
            "이전 해제 요청의 결과를 확인하고 있어요. 확인이 끝나기 전에는 새 해제권을 사용하지 않습니다."
        }
    }

    private var icon: String {
        switch destination {
        case .coinStore: "cart"
        case .iCloudRecovery: "icloud"
        case .ledgerReset: "exclamationmark.icloud"
        case .reconciliation: "arrow.triangle.2.circlepath"
        }
    }
}
