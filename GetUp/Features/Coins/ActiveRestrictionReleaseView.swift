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
        case .coinStore: "cart"
        case .iCloudRecovery: "icloud"
        case .ledgerReset: "exclamationmark.icloud"
        case .reconciliation: "arrow.triangle.2.circlepath"
        }
    }
}
