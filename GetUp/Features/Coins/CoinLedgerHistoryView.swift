import SwiftUI

struct CoinLedgerHistoryView: View {
    let events: [CoinLedgerEvent]
    let purchaseGrantStatus: String

    var body: some View {
        List(events, id: \.eventID) { event in
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(status(for: event))
                        .font(.headline)
                        .accessibilityIdentifier("coinStore.history.status")
                    if event.kind == .freeGrant, event.source == .monthlyFree {
                        Text("월 종료 시 남은 무료분은 소멸해요.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("coinStore.history.monthEnd")
                    }
                    Text(event.createdAt, format: .dateTime.year().month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("coinStore.history.timestamp")
                }
                Spacer()
                Text(signedQuantity(for: event))
                    .font(.headline.monospacedDigit())
                    .accessibilityIdentifier("coinStore.history.quantity")
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("coinStore.history.\(event.kind.rawValue)")
        }
        .overlay {
            if events.isEmpty {
                ContentUnavailableView("아직 코인 내역이 없어요", systemImage: "clock")
            }
        }
        .navigationTitle("코인 내역")
        .navigationBarTitleDisplayMode(.inline)
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
