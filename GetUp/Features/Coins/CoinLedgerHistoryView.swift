import SwiftUI

struct CoinLedgerHistoryView: View {
    let events: [CoinLedgerEvent]
    let syncState: CoinBalanceSyncState
    let purchaseGrantStatus: String

    var body: some View {
        Group {
            switch contentState {
            case .loading:
                ProgressView("코인 내역을 불러오는 중이에요")
                    .accessibilityIdentifier("coinStore.history.loading")
            case .empty:
                ContentUnavailableView("아직 코인 내역이 없어요", systemImage: "clock")
                    .accessibilityIdentifier("coinStore.history.empty")
            case .stale:
                historyList(showsStaleWarning: true)
            case .current:
                historyList(showsStaleWarning: false)
            }
        }
        .navigationTitle("코인 내역")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func historyList(showsStaleWarning: Bool) -> some View {
        List {
            if showsStaleWarning {
                Label(
                    "마지막으로 확인한 내역이에요. iCloud 연결 후 다시 확인해 주세요.",
                    systemImage: "icloud.slash"
                )
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("coinStore.history.stale")
                .accessibilitySortPriority(100)
            } else {
                Label("최신 내역이에요", systemImage: "checkmark.icloud")
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
                    Text("월 종료 시 남은 무료분은 소멸해요.")
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
                ? "구매 코인 지급"
                : "구매 코인 \(purchaseGrantStatus)"
        case .freeGrant:
            "월간 무료 지급"
        case .reservation:
            sourcePrefix(for: event) + " 사용 예약"
        case .spend:
            sourcePrefix(for: event) + " 사용"
        case .release:
            sourcePrefix(for: event) + " 사용 취소"
        case .refundAdjustment:
            "구매 코인 환불 보정"
        case .reversal:
            "구매 코인 환불 취소"
        }
    }

    private func sourcePrefix(for event: CoinLedgerEvent) -> String {
        switch event.source {
        case .monthlyFree: "월간 무료"
        case .purchased: "구매 코인"
        case .none: "코인"
        }
    }
}

private enum CoinLedgerHistoryContentState {
    case loading
    case empty
    case stale
    case current
}
