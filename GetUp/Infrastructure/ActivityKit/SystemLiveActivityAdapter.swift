import ActivityKit
import Foundation

struct SystemLiveActivityAdapter: RestrictionLiveActivityManaging {
    typealias AuthorizationStatus = @Sendable () async ->
        RestrictionLiveActivityAuthorizationStatus
    typealias ActiveActivities = @Sendable () async ->
        [RestrictionLiveActivitySnapshot]
    typealias RequestActivity = @Sendable (
        RestrictionLiveActivityAttributes,
        RestrictionLiveActivityAttributes.ContentState
    ) async throws -> Void
    typealias UpdateActivity = @Sendable (
        UUID,
        RestrictionLiveActivityAttributes.ContentState
    ) async throws -> Void
    typealias EndActivity = @Sendable (
        UUID,
        RestrictionLiveActivityAttributes.ContentState
    ) async throws -> Void

    private let readAuthorizationStatus: AuthorizationStatus
    private let readActiveActivities: ActiveActivities
    private let requestActivity: RequestActivity
    private let updateActivity: UpdateActivity
    private let endActivity: EndActivity

    init(
        authorizationStatus: @escaping AuthorizationStatus,
        activeActivities: @escaping ActiveActivities,
        requestActivity: @escaping RequestActivity,
        updateActivity: @escaping UpdateActivity,
        endActivity: @escaping EndActivity
    ) {
        readAuthorizationStatus = authorizationStatus
        readActiveActivities = activeActivities
        self.requestActivity = requestActivity
        self.updateActivity = updateActivity
        self.endActivity = endActivity
    }

    static func live() -> Self {
        Self(
            authorizationStatus: {
                ActivityAuthorizationInfo().areActivitiesEnabled
                    ? .enabled
                    : .disabled
            },
            activeActivities: {
                Activity<RestrictionLiveActivityAttributes>.activities.map {
                    RestrictionLiveActivitySnapshot(
                        attributes: $0.attributes,
                        contentState: $0.content.state
                    )
                }
            },
            requestActivity: { attributes, contentState in
                let content = ActivityContent(
                    state: contentState,
                    staleDate: contentState.endsAt
                )
                _ = try Activity<RestrictionLiveActivityAttributes>.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            },
            updateActivity: { activityID, contentState in
                guard let activity = activity(matching: activityID) else {
                    throw RestrictionLiveActivityError.updateFailed
                }
                await activity.update(ActivityContent(
                    state: contentState,
                    staleDate: contentState.endsAt
                ))
            },
            endActivity: { activityID, finalContentState in
                guard let activity = activity(matching: activityID) else {
                    throw RestrictionLiveActivityError.endFailed
                }
                await activity.end(
                    ActivityContent(
                        state: finalContentState,
                        staleDate: finalContentState.endsAt
                    ),
                    dismissalPolicy: .immediate
                )
            }
        )
    }

    func authorizationStatus() async -> RestrictionLiveActivityAuthorizationStatus {
        await readAuthorizationStatus()
    }

    func activeActivities() async -> [RestrictionLiveActivitySnapshot] {
        await readActiveActivities()
    }

    func request(
        attributes: RestrictionLiveActivityAttributes,
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws {
        do {
            try await requestActivity(attributes, contentState)
        } catch {
            throw RestrictionLiveActivityError.requestFailed
        }
    }

    func update(
        activityID: UUID,
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws {
        do {
            try await updateActivity(activityID, contentState)
        } catch {
            throw RestrictionLiveActivityError.updateFailed
        }
    }

    func end(
        activityID: UUID,
        finalContentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws {
        do {
            try await endActivity(activityID, finalContentState)
        } catch {
            throw RestrictionLiveActivityError.endFailed
        }
    }

    private static func activity(
        matching activityID: UUID
    ) -> Activity<RestrictionLiveActivityAttributes>? {
        Activity<RestrictionLiveActivityAttributes>.activities.first {
            $0.attributes.activityID == activityID
        }
    }
}
