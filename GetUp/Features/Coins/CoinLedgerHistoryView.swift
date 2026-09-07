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
        case .purchaseGrant: purchaseGrantStatus
        case .freeGrant: "무료 지급"
        case .reservation: "사용 예약"
        case .spend: "사용 완료"
        case .release: "원상 복구"
        case .refundAdjustment: "환불 보정"
        case .reversal: "환불 취소"
        }
    }
}
