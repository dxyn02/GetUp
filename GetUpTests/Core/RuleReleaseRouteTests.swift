import Foundation
import Testing
@testable import GetUp

@Suite("Rule release route lifecycle")
struct RuleReleaseRouteTests {
    @Test("A release route starts pending with a stable command identifier")
    func releaseRouteStartsPending() throws {
        let route = try makeRoute()

        #expect(route.destination == .releaseProcessing)
        #expect(route.commandID == Self.commandID)
        #expect(route.state == .pending)
        #expect(route.claimedAt == nil)
        #expect(route.terminalOutcome == nil)
        #expect(route.retryAfter == nil)
        #expect(route.presentedAt == nil)
        #expect(route.acknowledgedAt == nil)
        #expect(try roundTrip(route) == route)
    }

    @Test("Claim and terminal transitions preserve the release command identifier")
    func claimAndTerminalPreserveCommandID() throws {
        let pending = try makeRoute()
        let claimedAt = Self.createdAt.addingTimeInterval(30)
        let processing = try pending.claiming(at: claimedAt)
        let terminalAt = claimedAt.addingTimeInterval(2)
        let terminal = try processing.recordingTerminal(
            outcome: .completed,
            retryAfter: nil,
            at: terminalAt
        )

        #expect(processing.state == .processing)
        #expect(processing.commandID == Self.commandID)
        #expect(processing.claimedAt == claimedAt)
        #expect(terminal.state == .terminal)
        #expect(terminal.commandID == Self.commandID)
        #expect(terminal.terminalOutcome == .completed)
        #expect(terminal.presentedAt == nil)
        #expect(terminal.acknowledgedAt == nil)
    }

    @Test("Presenting a terminal result does not acknowledge or delete it")
    func presentationIsNotAcknowledgement() throws {
        let terminal = try makeRoute()
            .claiming(at: Self.createdAt.addingTimeInterval(1))
            .recordingTerminal(
                outcome: .insufficient,
                retryAfter: nil,
                at: Self.createdAt.addingTimeInterval(2)
            )
        let presentedAt = Self.createdAt.addingTimeInterval(3)
        let presented = try terminal.markingPresented(at: presentedAt)

        #expect(presented.state == .terminal)
        #expect(presented.presentedAt == presentedAt)
        #expect(presented.acknowledgedAt == nil)
    }

    @Test("Only a retryable terminal result can restart the same command")
    func onlyRetryableTerminalCanRetry() throws {
        let retryAfter = Self.createdAt.addingTimeInterval(20)
        let terminal = try makeRoute()
            .claiming(at: Self.createdAt.addingTimeInterval(1))
            .recordingTerminal(
                outcome: .retryable,
                retryAfter: retryAfter,
                at: Self.createdAt.addingTimeInterval(2)
            )
            .markingPresented(at: Self.createdAt.addingTimeInterval(3))
        let retried = try terminal.retrying(at: retryAfter)

        #expect(retried.state == .processing)
        #expect(retried.commandID == Self.commandID)
        #expect(retried.claimedAt == retryAfter)
        #expect(retried.terminalOutcome == nil)
        #expect(retried.retryAfter == nil)
        #expect(retried.presentedAt == nil)
        #expect(retried.acknowledgedAt == nil)

        #expect(throws: LiveActivityCoinModelError.invalidPendingAppRoute) {
            try terminal.retrying(at: retryAfter.addingTimeInterval(-1))
        }

        let completed = try makeRoute()
            .claiming(at: Self.createdAt.addingTimeInterval(1))
            .recordingTerminal(
                outcome: .completed,
                retryAfter: nil,
                at: Self.createdAt.addingTimeInterval(2)
            )
        #expect(throws: LiveActivityCoinModelError.invalidPendingAppRoute) {
            try completed.retrying(at: Self.createdAt.addingTimeInterval(3))
        }
    }

    @Test("Invalid release route transitions fail closed")
    func invalidTransitionsFailClosed() throws {
        let pending = try makeRoute()

        #expect(throws: LiveActivityCoinModelError.invalidPendingAppRoute) {
            try pending.recordingTerminal(
                outcome: .completed,
                retryAfter: nil,
                at: Self.createdAt.addingTimeInterval(1)
            )
        }
        #expect(throws: LiveActivityCoinModelError.invalidPendingAppRoute) {
            try pending.claiming(at: Self.createdAt.addingTimeInterval(-1))
        }
        #expect(throws: LiveActivityCoinModelError.invalidPendingAppRoute) {
            try PendingAppRoute.releaseProcessing(
                routeID: Self.routeID,
                commandID: Self.commandID,
                createdAt: Self.createdAt,
                occurrenceID: ""
            )
        }
    }
}

private extension RuleReleaseRouteTests {
    static let routeID = UUID(uuidString: "00000000-0000-4000-8000-000000000601")!
    static let commandID = UUID(uuidString: "00000000-0000-4000-8000-000000000602")!
    static let createdAt = Date(timeIntervalSince1970: 1_788_192_000)

    func makeRoute() throws -> PendingAppRoute {
        try PendingAppRoute.releaseProcessing(
            routeID: Self.routeID,
            commandID: Self.commandID,
            createdAt: Self.createdAt,
            occurrenceID: "occurrence-release"
        )
    }

    func roundTrip<T: Codable>(_ value: T) throws -> T {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: encoder.encode(value))
    }
}
