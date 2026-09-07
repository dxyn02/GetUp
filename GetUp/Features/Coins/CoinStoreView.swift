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
                balanceSection
                availabilitySection
                purchaseStatus
                catalogSection
                Button("코인 내역 보기") { showsHistory = true }
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
        .navigationTitle("코인")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.loadProducts() }
        .navigationDestination(isPresented: $showsHistory) {
            CoinLedgerHistoryView(
                events: model.events,
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

    private var balanceSection: some View {
        HStack(spacing: 12) {
            balanceCard(title: "이번 달 무료", value: model.balance.freeAvailable, id: "free")
            balanceCard(title: "구매 잔액", value: model.balance.purchasedAvailable, id: "purchased")
        }
    }

    private func balanceCard(title: String, value: Int, id: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption).foregroundStyle(HomeColor.textSecondary)
            Text(String(value))
                .font(.title.bold().monospacedDigit())
                .accessibilityIdentifier("coinStore.balance.\(id)")
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
                            Text("\(item.quantity)개")
                                .font(.headline)
                                .accessibilityIdentifier("coinStore.product.\(item.quantity).quantity")
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
        Text("코인은 iCloud 장부에 기록됩니다. 장부를 삭제하면 구매 잔액과 무료 코인은 복원할 수 없으며, App Store 구매 복원으로 되돌아오지 않습니다.")
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
            let message = "코인은 iCloud 장부에 기록됩니다. 장부를 삭제하면 구매 잔액과 무료 코인은 복원할 수 없으며, App Store 구매 복원으로 되돌아오지 않습니다."
            let alert = UIAlertController(
                title: "코인을 구매할까요?",
                message: message,
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "취소", style: .cancel) { _ in
                context.coordinator.alert = nil
                Task { @MainActor in onCancel() }
            })
            alert.addAction(UIAlertAction(title: "구매", style: .default) { _ in
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

private extension View {
    func disclosureCard(id: String) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(HomeColor.surfaceElevated, in: .rect(cornerRadius: 18))
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(id)
    }
}
