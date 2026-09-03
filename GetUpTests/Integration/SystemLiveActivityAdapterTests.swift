import Foundation
import Testing
@testable import GetUp

@Suite("System Live Activity adapter")
struct SystemLiveActivityAdapterTests {
    @Test("Authorization and active activities are read through the system boundary")
    func readsAuthorizationAndActivities() async throws {
        let snapshot = try makeSnapshot()
        let client = SystemLiveActivityClientSpy(
            authorization: .disabled,
            activities: [snapshot]
        )
        let adapter = makeAdapter(client: client)

        #expect(await adapter.authorizationStatus() == .disabled)
        #expect(await adapter.activeActivities() == [snapshot])
        #expect(await client.authorizationReadCount == 1)
        #expect(await client.activitiesReadCount == 1)
    }

    @Test("Request, update, and immediate end forward domain payloads")
    func forwardsMutations() async throws {
        let initial = try makeSnapshot()
        let updated = try makeSnapshot(
            occurrenceID: "occurrence-2",
            endsAt: Self.now.addingTimeInterval(1_800)
        )
        let client = SystemLiveActivityClientSpy()
        let adapter = makeAdapter(client: client)

        try await adapter.request(
            attributes: initial.attributes,
            contentState: initial.contentState
        )
        try await adapter.update(
            activityID: initial.attributes.activityID,
            contentState: updated.contentState
        )
        try await adapter.end(
            activityID: initial.attributes.activityID,
            finalContentState: updated.contentState
        )

        #expect(await client.operations == [
            .request(initial),
            .update(initial.attributes.activityID, updated.contentState),
            .end(initial.attributes.activityID, updated.contentState),
        ])
    }

    @Test("Framework failures are normalized for each mutation")
    func normalizesFrameworkFailures() async throws {
        let snapshot = try makeSnapshot()

        for (failure, expected) in [
            (SystemLiveActivityClientSpy.Failure.request, RestrictionLiveActivityError.requestFailed),
            (.update, .updateFailed),
            (.end, .endFailed),
        ] {
            let client = SystemLiveActivityClientSpy(failure: failure)
            let adapter = makeAdapter(client: client)

            switch failure {
            case .request:
                await #expect(throws: expected) {
                    try await adapter.request(
                        attributes: snapshot.attributes,
                        contentState: snapshot.contentState
                    )
                }
            case .update:
                await #expect(throws: expected) {
                    try await adapter.update(
                        activityID: snapshot.attributes.activityID,
                        contentState: snapshot.contentState
                    )
                }
            case .end:
                await #expect(throws: expected) {
                    try await adapter.end(
                        activityID: snapshot.attributes.activityID,
                        finalContentState: snapshot.contentState
                    )
                }
            }
        }
    }

    private func makeAdapter(
        client: SystemLiveActivityClientSpy
    ) -> SystemLiveActivityAdapter {
        SystemLiveActivityAdapter(
            authorizationStatus: { await client.authorizationStatus() },
            activeActivities: { await client.activeActivities() },
            requestActivity: { attributes, contentState in
                try await client.request(
                    attributes: attributes,
                    contentState: contentState
                )
            },
            updateActivity: { activityID, contentState in
                try await client.update(
                    activityID: activityID,
                    contentState: contentState
                )
            },
            endActivity: { activityID, finalContentState in
                try await client.end(
                    activityID: activityID,
                    finalContentState: finalContentState
                )
            }
        )
    }

    private func makeSnapshot(
        occurrenceID: String = "occurrence-1",
        endsAt: Date = Self.now.addingTimeInterval(3_600)
    ) throws -> RestrictionLiveActivitySnapshot {
        RestrictionLiveActivitySnapshot(
            attributes: RestrictionLiveActivityAttributes(
                activityID: Self.activityID,
                restrictionStartedAt: Self.now.addingTimeInterval(-60)
            ),
            contentState: try RestrictionLiveActivityAttributes.ContentState(
                occurrenceID: occurrenceID,
                ruleDisplayName: "집중 시간",
                endsAt: endsAt,
                remainingDistance: .known(meters: 120),
                distanceObservedAt: Self.now,
                hasAdditionalRestrictions: false
            )
        )
    }

    private static let now = Date(timeIntervalSince1970: 1_788_192_300)
    private static let activityID = UUID(
        uuidString: "00000000-0000-4000-8000-000000000301"
    )!
}

private actor SystemLiveActivityClientSpy {
    enum Failure: Sendable {
        case request
        case update
        case end
    }

    enum Operation: Equatable, Sendable {
        case request(RestrictionLiveActivitySnapshot)
        case update(UUID, RestrictionLiveActivityAttributes.ContentState)
        case end(UUID, RestrictionLiveActivityAttributes.ContentState)
    }

    let authorization: RestrictionLiveActivityAuthorizationStatus
    let activities: [RestrictionLiveActivitySnapshot]
    let failure: Failure?
    private(set) var authorizationReadCount = 0
    private(set) var activitiesReadCount = 0
    private(set) var operations: [Operation] = []

    init(
        authorization: RestrictionLiveActivityAuthorizationStatus = .enabled,
        activities: [RestrictionLiveActivitySnapshot] = [],
        failure: Failure? = nil
    ) {
        self.authorization = authorization
        self.activities = activities
        self.failure = failure
    }

    func authorizationStatus() -> RestrictionLiveActivityAuthorizationStatus {
        authorizationReadCount += 1
        return authorization
    }

    func activeActivities() -> [RestrictionLiveActivitySnapshot] {
        activitiesReadCount += 1
        return activities
    }

    func request(
        attributes: RestrictionLiveActivityAttributes,
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) throws {
        operations.append(.request(RestrictionLiveActivitySnapshot(
            attributes: attributes,
            contentState: contentState
        )))
        if failure == .request {
            throw SystemLiveActivityClientError.failed
        }
    }

    func update(
        activityID: UUID,
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) throws {
        operations.append(.update(activityID, contentState))
        if failure == .update {
            throw SystemLiveActivityClientError.failed
        }
    }

    func end(
        activityID: UUID,
        finalContentState: RestrictionLiveActivityAttributes.ContentState
    ) throws {
        operations.append(.end(activityID, finalContentState))
        if failure == .end {
            throw SystemLiveActivityClientError.failed
        }
    }
}

private enum SystemLiveActivityClientError: Error {
    case failed
}
