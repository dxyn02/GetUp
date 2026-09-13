import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class CoinStoreInstrumentation {
    private(set) var setupCount = 0
    private(set) var resetCount = 0
    private(set) var purchaseCount = 0

    func recordSetup() { setupCount += 1 }
    func recordReset() { resetCount += 1 }
    func recordPurchase() { purchaseCount += 1 }
}

@MainActor
struct CoinStoreConfiguration {
    typealias LedgerAction = @Sendable () async throws -> CoinStoreLedgerState

    let model: CoinStoreModel
    let activateLedger: LedgerAction
    let resetLedger: LedgerAction
    let retryLedgerSync: LedgerAction
    let instrumentation: CoinStoreInstrumentation?
    let purchaseGrantStatus: String

    init(
        model: CoinStoreModel,
        activateLedger: @escaping LedgerAction = { throw CoinStoreError.purchaseFailed },
        resetLedger: @escaping LedgerAction = { throw CoinStoreError.purchaseFailed },
        retryLedgerSync: @escaping LedgerAction = { throw CoinStoreError.purchaseFailed },
        instrumentation: CoinStoreInstrumentation? = nil,
        purchaseGrantStatus: String = "지급 완료"
    ) {
        self.model = model
        self.activateLedger = activateLedger
        self.resetLedger = resetLedger
        self.retryLedgerSync = retryLedgerSync
        self.instrumentation = instrumentation
        self.purchaseGrantStatus = purchaseGrantStatus
    }
}

@MainActor
struct CoinStoreView: View {
    @Bindable private var model: CoinStoreModel
    @State private var showsHistory = false
    @State private var showsResetConfirmation = false
    @State private var lifecycleError = false

    private let activateLedger: CoinStoreConfiguration.LedgerAction
    private let resetLedger: CoinStoreConfiguration.LedgerAction
    private let retryLedgerSync: CoinStoreConfiguration.LedgerAction
    private let instrumentation: CoinStoreInstrumentation?
    private let purchaseGrantStatus: String

    init(configuration: CoinStoreConfiguration) {
        model = configuration.model
        activateLedger = configuration.activateLedger
        resetLedger = configuration.resetLedger
        retryLedgerSync = configuration.retryLedgerSync
        instrumentation = configuration.instrumentation
        purchaseGrantStatus = configuration.purchaseGrantStatus
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                t089TestBanner
                balanceSection
                availabilitySection
                purchaseStatus
                catalogSection
                Button(AppLocalizedCopy.string("coinStore.history.open")) {
                    showsHistory = true
                }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("coinStore.history.open")
                instrumentationSection
            }
            .padding(20)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coinStore.screen")
        }
        .background(HomeColor.background.ignoresSafeArea())
        .foregroundStyle(HomeColor.textPrimary)
        .navigationTitle(AppLocalizedCopy.string("coinStore.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadProducts() }
        .navigationDestination(isPresented: $showsHistory) {
            CoinLedgerHistoryView(
                events: model.events,
                syncState: model.balance.syncState,
                purchaseGrantStatus: purchaseGrantStatus
            )
        }
        .background {
            CoinPurchaseAlertPresenter(
                isPresented: purchaseConfirmationBinding.wrappedValue,
                onCancel: { model.cancelPurchaseConfirmation() },
                onPurchase: { Task { await model.confirmPurchase() } }
            )
        }
        .alert("새 장부를 시작할까요?", isPresented: $showsResetConfirmation) {
            Button("취소", role: .cancel) {}
            Button("새 장부 시작", role: .destructive) {
                Task { await performLedgerAction(resetLedger) }
            }
        } message: {
            Text("삭제된 iCloud 장부의 구매 잔액과 이번 달 무료 코인은 복원되지 않습니다.")
        }
    }

    @ViewBuilder
    private var t089TestBanner: some View {
#if DEBUG
        if let configuration = SharedIdentifiers.t089LedgerTestConfiguration() {
            Text(
                "T089 TEST · \(configuration.ledgerNamespace) · "
                    + "서울 매월 \(configuration.monthlyBoundaryDay)일 00:00"
            )
            .font(.caption.monospaced().weight(.semibold))
            .foregroundStyle(.black)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.yellow, in: .rect(cornerRadius: 8))
            .accessibilityIdentifier("coinStore.t089TestBanner")
        }
#endif
    }

    private var balanceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(balanceContentState.message)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(balanceContentState.foregroundStyle)
                .accessibilityIdentifier("coinStore.balance.state")
                .accessibilitySortPriority(100)

            HStack(alignment: .firstTextBaseline) {
                Text(AppLocalizedCopy.string("coinStore.monthly.title"))
                    .font(.title2.bold())
                    .accessibilityIdentifier("coinStore.monthly.title")
                Spacer()
                Text(monthlyAllowance.monthLabel)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HomeColor.textSecondary)
                    .accessibilityIdentifier("coinStore.monthly.month")
            }

            HStack(spacing: 12) {
                balanceCard(
                    title: AppLocalizedCopy.string("coinStore.balance.free.label"),
                    displayValue: balanceContentState.freeDisplayValue(
                        monthlyAllowance.available
                    ),
                    accessibilityValue: balanceContentState.freeAccessibilityValue(
                        monthlyAllowance.available
                    ),
                    id: "free",
                    sortPriority: 80
                )
                balanceCard(
                    title: AppLocalizedCopy.string("coinStore.balance.purchased.label"),
                    displayValue: balanceContentState.purchasedDisplayValue(
                        model.balance.purchasedAvailable
                    ),
                    accessibilityValue: balanceContentState.purchasedAccessibilityValue(
                        model.balance.purchasedAvailable
                    ),
                    id: "purchased",
                    sortPriority: 70
                )
            }

            Text(AppLocalizedCopy.string("coinStore.monthly.nonRollover"))
                .font(.footnote)
                .foregroundStyle(HomeColor.textSecondary)
                .accessibilityIdentifier("coinStore.monthly.nonRollover")
            Text(monthlyAllowance.nextRefreshLabel)
                .font(.footnote)
                .foregroundStyle(HomeColor.textSecondary)
                .accessibilityIdentifier("coinStore.monthly.nextRefresh")
        }
    }

    private var balanceContentState: CoinStoreBalanceContentState {
        CoinStoreBalanceContentState(
            balance: model.balance,
            displayedFreeAvailable: monthlyAllowance.available
        )
    }

    private var monthlyAllowance: MonthlyAllowancePresentation {
        let monthID: String
        let available: Int
        switch model.monthlyAllowanceDisplay {
        case .setupRequired(let value, let availableAfterSetup):
            monthID = value
            available = availableAfterSetup
        case .current(let value, let currentAvailable):
            monthID = value
            available = currentAvailable
        case .resetRequired(let value, let resetAvailable):
            monthID = value
            available = resetAvailable
        case .unavailable(let value, let lastKnownAvailable):
            monthID = value
            available = lastKnownAvailable
        }
        return MonthlyAllowancePresentation(monthID: monthID, available: available)
    }

    private func balanceCard(
        title: String,
        displayValue: String,
        accessibilityValue: String,
        id: String,
        sortPriority: Double
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(HomeColor.textSecondary)
                .accessibilityHidden(true)
            Text(displayValue)
                .font(.title.bold().monospacedDigit())
                .accessibilityLabel(title)
                .accessibilityValue(accessibilityValue)
                .accessibilityIdentifier("coinStore.balance.\(id)")
                .accessibilitySortPriority(sortPriority)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HomeColor.surface, in: .rect(cornerRadius: 18))
    }

    @ViewBuilder
    private var availabilitySection: some View {
        switch model.availability {
        case .setupRequired:
            VStack(alignment: .leading, spacing: 12) {
                Text("코인 기능 활성화").font(.headline)
                recoveryLimitDisclosure
                Button("내용을 이해했고 활성화하기") {
                    Task { await performLedgerAction(activateLedger) }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("coinStore.setup.confirm")
            }
            .disclosureCard(id: "coinStore.setup.disclosure")
        case .ledgerResetRequired:
            VStack(alignment: .leading, spacing: 12) {
                Text("iCloud 장부가 삭제되었어요").font(.headline)
                Text("기존 구매 잔액과 이번 달 무료 코인은 복원할 수 없습니다.")
                    .accessibilityIdentifier("coinStore.reset.loss")
                Button("새 장부 시작") { showsResetConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("coinStore.reset.requestConfirmation")
            }
            .disclosureCard(id: "coinStore.reset.disclosure")
        case .syncing:
            Label("iCloud 장부를 동기화하는 중이에요", systemImage: "icloud.and.arrow.down")
        case .iCloudRecoveryRequired:
            VStack(alignment: .leading, spacing: 12) {
                Text("iCloud 장부를 불러올 수 없어요. 연결을 확인하고 다시 시도해 주세요.")
                    .accessibilityIdentifier("coinStore.ledger.unavailable")
                Button("iCloud 장부 다시 불러오기") {
                    Task { await performLedgerAction(retryLedgerSync) }
                }
                .accessibilityIdentifier("coinStore.ledger.retry")
            }
            .disclosureCard(id: "coinStore.ledger.recovery")
        case .reconciliationRequired:
            Text("코인 사용 내역을 확인하는 중이에요. 완료되면 구매할 수 있습니다.")
        case .ready:
            EmptyView()
        }

        if lifecycleError {
            Text("iCloud 장부 작업을 완료하지 못했어요. 다시 시도해 주세요.")
                .foregroundStyle(HomeColor.error)
        }
    }

    @ViewBuilder
    private var purchaseStatus: some View {
        switch model.purchaseState {
        case .pending:
            Text("구매 승인을 기다리고 있어요")
                .accessibilityIdentifier("coinStore.purchase.pending")
        case .cancelled:
            Text("구매를 취소했어요")
                .accessibilityIdentifier("coinStore.purchase.cancelled")
        case .failed:
            Text("구매를 완료하지 못했어요")
                .foregroundStyle(HomeColor.error)
                .accessibilityIdentifier("coinStore.purchase.error")
        case .purchasing:
            ProgressView("구매 처리 중")
        case .idle, .confirmationRequested, .purchased:
            EmptyView()
        }
    }

    private var catalogSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("코인 구매").font(.title2.bold())
            VStack(spacing: 10) {
                ForEach(model.products, id: \.product.id) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.product.displayName)
                                .font(.headline)
                                .accessibilityIdentifier("coinStore.product.\(item.quantity).name")
                            Text(item.product.displayDescription)
                                .font(.caption)
                                .foregroundStyle(HomeColor.textSecondary)
                                .accessibilityIdentifier(
                                    "coinStore.product.\(item.quantity).description"
                                )
                            Text(item.product.displayPrice)
                                .foregroundStyle(HomeColor.textSecondary)
                                .accessibilityIdentifier("coinStore.product.\(item.quantity).price")
                        }
                        Spacer()
                        Button("구매") {
                            _ = model.requestPurchaseConfirmation(productID: item.product.id)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.isPurchaseEnabled(productID: item.product.id))
                        .accessibilityIdentifier("coinStore.product.\(item.quantity).purchase")
                    }
                    .padding(16)
                    .background(HomeColor.surface, in: .rect(cornerRadius: 18))
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coinStore.catalog")
        }
    }

    @ViewBuilder
    private var instrumentationSection: some View {
        if let instrumentation {
            Group {
                Text(String(instrumentation.setupCount))
                    .accessibilityIdentifier("coinStore.test.setupCount")
                Text(String(instrumentation.resetCount))
                    .accessibilityIdentifier("coinStore.test.resetCount")
                Text(String(instrumentation.purchaseCount))
                    .accessibilityIdentifier("coinStore.test.purchaseCount")
            }
            .font(.caption2)
            .foregroundStyle(.clear)
            .accessibilityHidden(false)
        }
    }

    private var purchaseConfirmationBinding: Binding<Bool> {
        Binding(
            get: {
                if case .confirmationRequested = model.purchaseState { true } else { false }
            },
            set: { presented in
                if !presented { model.cancelPurchaseConfirmation() }
            }
        )
    }

    private var recoveryLimitDisclosure: some View {
        Text(CoinStoreLocalizedCopy.limitDisclosure)
            .foregroundStyle(HomeColor.textSecondary)
            .accessibilityIdentifier("coinStore.disclosure.recoveryLimit")
    }

    private func performLedgerAction(
        _ action: @escaping CoinStoreConfiguration.LedgerAction
    ) async {
        do {
            let ledger = try await action()
            guard !Task.isCancelled else { return }
            model.refreshLedger(ledger)
            lifecycleError = false
        } catch {
            lifecycleError = true
        }
    }
}

enum CoinStoreBalanceContentState: Equatable {
    case loading
    case empty
    case stale
    case current
    case setup
    case reset

    init(balance: CoinBalanceSnapshot, displayedFreeAvailable: Int) {
        switch balance.syncState {
        case .syncing:
            self = .loading
        case .stale, .unavailable:
            self = .stale
        case .current:
            self = displayedFreeAvailable == 0 && balance.purchasedAvailable == 0
                ? .empty
                : .current
        case .setupRequired:
            self = .setup
        case .deletionConfirmed, .resetRequired:
            self = .reset
        }
    }

    var message: String {
        switch self {
        case .loading: AppLocalizedCopy.string("coinStore.balance.state.loading")
        case .empty: AppLocalizedCopy.string("coinStore.balance.state.empty")
        case .stale: AppLocalizedCopy.string("coinStore.balance.state.stale")
        case .current: AppLocalizedCopy.string("coinStore.balance.state.current")
        case .setup: AppLocalizedCopy.string("coinStore.balance.state.setup")
        case .reset: AppLocalizedCopy.string("coinStore.balance.state.reset")
        }
    }

    var foregroundStyle: Color {
        switch self {
        case .stale: HomeColor.error
        case .loading, .empty, .current, .setup, .reset: HomeColor.textSecondary
        }
    }

    func freeDisplayValue(_ value: Int) -> String {
        self == .loading ? "—" : String(value)
    }

    func purchasedDisplayValue(_ value: Int) -> String {
        self == .loading ? "—" : String(value)
    }

    func freeAccessibilityValue(_ value: Int) -> String {
        guard self != .loading else {
            return AppLocalizedCopy.string("coinStore.balance.value.loading")
        }
        return value == 1
            ? AppLocalizedCopy.string("coinStore.balance.free.accessibilityValue.one")
            : AppLocalizedCopy.format(
                "coinStore.balance.free.accessibilityValue.other",
                value
            )
    }

    func purchasedAccessibilityValue(_ value: Int) -> String {
        guard self != .loading else {
            return AppLocalizedCopy.string("coinStore.balance.value.loading")
        }
        return value == 1
            ? AppLocalizedCopy.string("coinStore.balance.purchased.accessibilityValue.one")
            : AppLocalizedCopy.format(
                "coinStore.balance.purchased.accessibilityValue.other",
                value
            )
    }
}

private struct MonthlyAllowancePresentation {
    let available: Int
    let monthLabel: String
    let nextRefreshLabel: String

    init(monthID: String, available: Int) {
        self.available = available

        guard let monthStart = Self.monthStart(for: monthID),
              let nextMonth = MonthlyAllowancePolicy.nextPeriodStart(afterMonthID: monthID)
        else {
            monthLabel = monthID
            nextRefreshLabel = AppLocalizedCopy.string(
                "coinStore.monthly.nextRefresh.fallback"
            )
            return
        }

        monthLabel = Self.formatted(monthStart, template: "yyyyMMMM")
        nextRefreshLabel = AppLocalizedCopy.format(
            "coinStore.monthly.nextRefresh",
            Self.formatted(nextMonth, template: "yyyyMMMMdHHmm")
        )
    }

    private static let seoulTimeZone = TimeZone(identifier: "Asia/Seoul")!

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = seoulTimeZone
        return calendar
    }

    private static func monthStart(for monthID: String) -> Date? {
        let components = monthID.split(separator: "-", omittingEmptySubsequences: false)
        guard components.count == 2,
              let year = Int(components[0]),
              let month = Int(components[1]),
              (1...12).contains(month)
        else {
            return nil
        }
        return calendar.date(from: DateComponents(year: year, month: month, day: 1))
    }

    private static func formatted(_ date: Date, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.calendar = calendar
        formatter.timeZone = seoulTimeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }
}

private struct CoinPurchaseAlertPresenter: UIViewControllerRepresentable {
    let isPresented: Bool
    let onCancel: @MainActor () -> Void
    let onPurchase: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(
        _ viewController: UIViewController,
        context: Context
    ) {
        if isPresented, context.coordinator.alert == nil {
            let message = CoinStoreLocalizedCopy.limitDisclosure
            let alert = UIAlertController(
                title: AppLocalizedCopy.string("coinStore.purchase.confirmation.title"),
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(
                title: AppLocalizedCopy.string("coinStore.action.cancel"),
                style: .cancel
            ) { _ in
                context.coordinator.alert = nil
                Task { @MainActor in onCancel() }
            })
            alert.addAction(UIAlertAction(
                title: AppLocalizedCopy.string("coinStore.action.purchase"),
                style: .default
            ) { _ in
                context.coordinator.alert = nil
                Task { @MainActor in onPurchase() }
            })
            context.coordinator.alert = alert
            viewController.present(alert, animated: true) {
                Self.messageLabel(in: alert.view, matching: message)?
                    .accessibilityIdentifier = "coinStore.disclosure.recoveryLimit"
            }
        } else if !isPresented, let alert = context.coordinator.alert {
            alert.dismiss(animated: true)
            context.coordinator.alert = nil
        }
    }

    static func dismantleUIViewController(
        _ uiViewController: UIViewController,
        coordinator: Coordinator
    ) {
        coordinator.alert?.dismiss(animated: false)
        coordinator.alert = nil
    }

    private static func messageLabel(in view: UIView, matching message: String) -> UILabel? {
        if let label = view as? UILabel, label.text == message {
            return label
        }
        for subview in view.subviews {
            if let label = messageLabel(in: subview, matching: message) {
                return label
            }
        }
        return nil
    }

    final class Coordinator {
        var alert: UIAlertController?
    }
}

private enum CoinStoreLocalizedCopy {
    static var limitDisclosure: String {
        AppLocalizedCopy.string("coinStore.disclosure.limitations")
    }
}

private extension View {
    func disclosureCard(id: String) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
    }
}
