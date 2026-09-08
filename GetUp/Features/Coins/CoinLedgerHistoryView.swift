import SwiftUI

struct CoinLedgerHistoryView: View {
    let events: [CoinLedgerEvent]
    let syncState: CoinBalanceSyncState
    let purchaseGrantStatus: String

    var body: some View {
        Group {
            switch contentState {
            case .loading:
                ProgressView(AppLocalizedCopy.string("coinStore.history.loading"))
                    .accessibilityIdentifier("coinStore.history.loading")
            case .empty:
                ContentUnavailableView(
                    AppLocalizedCopy.string("coinStore.history.empty"),
                    systemImage: "clock"
                )
                    .accessibilityIdentifier("coinStore.history.empty")
            case .stale:
                historyList(showsStaleWarning: true)
            case .current:
                historyList(showsStaleWarning: false)
            }
        }
        .navigationTitle(AppLocalizedCopy.string("coinStore.history.title"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyList(showsStaleWarning: Bool) -> some View {
        List {
            if showsStaleWarning {
                Label(
                    AppLocalizedCopy.string("coinStore.history.stale"),
                    systemImage: "icloud.slash"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("coinStore.history.stale")
                .accessibilitySortPriority(100)
            } else {
                Label(
                    AppLocalizedCopy.string("coinStore.history.current"),
                    systemImage: "checkmark.icloud"
                )
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("coinStore.history.current")
                    .accessibilitySortPriority(100)
            }

            ForEach(events, id: \.eventID) { event in
                historyRow(event)
            }
        }
    }

    private func historyRow(_ event: CoinLedgerEvent) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(status(for: event))
                    .font(.headline)
                    .accessibilityIdentifier("coinStore.history.status")
                    .accessibilitySortPriority(40)
                if event.kind == .freeGrant, event.source == .monthlyFree {
                    Text(AppLocalizedCopy.string("coinStore.history.monthEnd"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("coinStore.history.monthEnd")
                        .accessibilitySortPriority(30)
                }
                Text(event.createdAt, format: .dateTime.year().month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("coinStore.history.timestamp")
                    .accessibilitySortPriority(20)
            }
            Spacer()
            Text(signedQuantity(for: event))
                .font(.headline.monospacedDigit())
                .accessibilityIdentifier("coinStore.history.quantity")
                .accessibilitySortPriority(10)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coinStore.history.\(event.kind.rawValue)")
    }

    private var contentState: CoinLedgerHistoryContentState {
        switch syncState {
        case .syncing:
            .loading
        case .stale, .unavailable:
            .stale
        case .current, .setupRequired, .deletionConfirmed, .resetRequired:
            events.isEmpty ? .empty : .current
        }
    }

    private func signedQuantity(for event: CoinLedgerEvent) -> String {
        let sign = switch event.kind {
        case .reservation, .spend, .refundAdjustment: "-"
        case .purchaseGrant, .freeGrant, .release, .reversal: "+"
        }
        return "\(sign)\(event.quantity)"
    }

    private func status(for event: CoinLedgerEvent) -> String {
        switch event.kind {
        case .purchaseGrant:
            purchaseGrantStatus == "구매 지급"
                ? AppLocalizedCopy.string("coinStore.history.status.purchaseGrant")
                : AppLocalizedCopy.format(
                    "coinStore.history.status.purchaseGrant.custom",
                    purchaseGrantStatus
                )
        case .freeGrant:
            AppLocalizedCopy.string("coinStore.history.status.freeGrant")
        case .reservation:
            localizedUsageStatus(for: event, operation: .reservation)
        case .spend:
            localizedUsageStatus(for: event, operation: .spend)
        case .release:
            localizedUsageStatus(for: event, operation: .release)
        case .refundAdjustment:
            AppLocalizedCopy.string("coinStore.history.status.refundAdjustment")
        case .reversal:
            AppLocalizedCopy.string("coinStore.history.status.reversal")
        }
    }

    private func localizedUsageStatus(
        for event: CoinLedgerEvent,
        operation: CoinLedgerHistoryOperation
    ) -> String {
        switch (event.source, operation) {
        case (.monthlyFree, .reservation):
            AppLocalizedCopy.string("coinStore.history.status.monthlyFree.reservation")
        case (.monthlyFree, .spend):
            AppLocalizedCopy.string("coinStore.history.status.monthlyFree.spend")
        case (.monthlyFree, .release):
            AppLocalizedCopy.string("coinStore.history.status.monthlyFree.release")
        case (.purchased, .reservation):
            AppLocalizedCopy.string("coinStore.history.status.purchased.reservation")
        case (.purchased, .spend):
            AppLocalizedCopy.string("coinStore.history.status.purchased.spend")
        case (.purchased, .release):
            AppLocalizedCopy.string("coinStore.history.status.purchased.release")
        case (.none, .reservation):
            AppLocalizedCopy.string("coinStore.history.status.coin.reservation")
        case (.none, .spend):
            AppLocalizedCopy.string("coinStore.history.status.coin.spend")
        case (.none, .release):
            AppLocalizedCopy.string("coinStore.history.status.coin.release")
        }
    }
}

private enum CoinLedgerHistoryOperation {
    case reservation
    case spend
    case release
}

private enum CoinLedgerHistoryContentState {
    case loading
    case empty
    case stale
    case current
}
