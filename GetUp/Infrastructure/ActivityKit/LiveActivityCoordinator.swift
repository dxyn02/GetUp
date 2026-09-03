import Foundation

enum LiveActivityAdjustmentContext: Equatable, Sendable {
    case foreground
    case background
}

enum LiveActivityCoordinationAction: Equatable, Sendable {
    case request
    case update(UUID)
    case end(UUID)
}

struct LiveActivityCoordinationResult: Equatable, Sendable {
    let actions: [LiveActivityCoordinationAction]
    let failureCodes: [LiveActivityCoinErrorCode]

    static let noChange = LiveActivityCoordinationResult(
        actions: [],
        failureCodes: []
    )
}

private struct SystemLiveActivityClock: Clock {
    var now: Date { Date() }
}

actor LiveActivityCoordinator {
    private let manager: any RestrictionLiveActivityManaging
    private let clock: any Clock

    init(
        manager: any RestrictionLiveActivityManaging,
        clock: any Clock = SystemLiveActivityClock()
    ) {
        self.manager = manager
        self.clock = clock
    }

    func reconcile(
        context: LiveActivityAdjustmentContext,
        desiredActivity: RestrictionLiveActivitySnapshot?
    ) async -> LiveActivityCoordinationResult {
        guard context == .foreground else {
            return .noChange
        }

        if desiredActivity != nil {
            let authorization = await manager.authorizationStatus()
            guard authorization == .enabled else {
                return LiveActivityCoordinationResult(
                    actions: [],
                    failureCodes: [.activityAuthorizationDenied]
                )
            }
        }

        let activities = await manager.activeActivities().sorted {
            $0.attributes.activityID.uuidString < $1.attributes.activityID.uuidString
        }
        let now = clock.now

        guard let desiredActivity else {
            return await endAll(activities, now: now)
        }

        guard !activities.isEmpty else {
            return await request(desiredActivity, now: now)
        }

        let keeper = activities.first(where: {
            $0.attributes.activityID == desiredActivity.attributes.activityID
        }) ?? activities[0]
        var actions: [LiveActivityCoordinationAction] = []
        var failureCodes: [LiveActivityCoinErrorCode] = []

        for activity in activities where activity.attributes.activityID != keeper.attributes.activityID {
            do {
                let finalState = try LiveActivityTimePolicy.ending(
                    contentState: activity.contentState,
                    now: now
                )
                try await manager.end(
                    activityID: activity.attributes.activityID,
                    finalContentState: finalState
                )
                actions.append(.end(activity.attributes.activityID))
            } catch {
                failureCodes.append(code(for: error, fallback: .activityEndFailed))
            }
        }

        do {
            let desiredState = try LiveActivityTimePolicy.clamping(
                contentState: desiredActivity.contentState,
                now: now
            )
            if keeper.contentState != desiredState {
                try await manager.update(
                    activityID: keeper.attributes.activityID,
                    contentState: desiredState
                )
                actions.append(.update(keeper.attributes.activityID))
            }
        } catch {
            failureCodes.append(code(for: error, fallback: .activityUpdateFailed))
        }

        return LiveActivityCoordinationResult(
            actions: actions,
            failureCodes: failureCodes
        )
    }

    private func request(
        _ desiredActivity: RestrictionLiveActivitySnapshot,
        now: Date
    ) async -> LiveActivityCoordinationResult {
        do {
            let contentState = try LiveActivityTimePolicy.clamping(
                contentState: desiredActivity.contentState,
                now: now
            )
            try await manager.request(
                attributes: desiredActivity.attributes,
                contentState: contentState
            )
            return LiveActivityCoordinationResult(
                actions: [.request],
                failureCodes: []
            )
        } catch {
            return LiveActivityCoordinationResult(
                actions: [],
                failureCodes: [code(for: error, fallback: .activityRequestFailed)]
            )
        }
    }

    private func endAll(
        _ activities: [RestrictionLiveActivitySnapshot],
        now: Date
    ) async -> LiveActivityCoordinationResult {
        var actions: [LiveActivityCoordinationAction] = []
        var failureCodes: [LiveActivityCoinErrorCode] = []

        for activity in activities {
            do {
                let finalState = try LiveActivityTimePolicy.ending(
                    contentState: activity.contentState,
                    now: now
                )
                try await manager.end(
                    activityID: activity.attributes.activityID,
                    finalContentState: finalState
                )
                actions.append(.end(activity.attributes.activityID))
            } catch {
                failureCodes.append(code(for: error, fallback: .activityEndFailed))
            }
        }

        return LiveActivityCoordinationResult(
            actions: actions,
            failureCodes: failureCodes
        )
    }

    private func code(
        for error: any Error,
        fallback: LiveActivityCoinErrorCode
    ) -> LiveActivityCoinErrorCode {
        (error as? any StableLiveActivityCoinError)?.errorCode ?? fallback
    }
}
