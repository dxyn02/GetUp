#if DEBUG
import ActivityKit
import Foundation

enum ActivityKitFeasibilityProbe {
    enum Outcome: String, Codable, Sendable {
        case success
        case unsupported
        case failure
        case timeout
    }

    struct Report: Codable, Sendable {
        let outcome: Outcome
        let operatingSystemVersion: String
        let recordedAt: Date
        let activityFound: Bool
        let updateVerified: Bool
        let endRequested: Bool
        let detail: String
    }

    static let resultFileName = "activitykit-feasibility-probe.json"
    static let resultDefaultsKey = "getup.debug.activitykit-feasibility-probe"

    static func recordInvocation() {
        persist(makeReport(
            outcome: .failure,
            detail: "The Shield callback started, but the asynchronous probe did not finish."
        ))
    }

    static func run(timeout: Duration = .seconds(4)) async -> Report {
        let report = await withTaskGroup(of: Report.self) { group in
            group.addTask {
                await execute()
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return cancelledReport()
                }
                return makeReport(
                    outcome: .timeout,
                    detail: "ActivityKit direct adjustment exceeded the probe deadline."
                )
            }

            let first = await group.next() ?? makeReport(
                outcome: .failure,
                detail: "The probe produced no result."
            )
            group.cancelAll()
            return first
        }

        persist(report)
        return report
    }

    private static func execute() async -> Report {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            return makeReport(
                outcome: .unsupported,
                detail: "Live Activities are disabled on this device."
            )
        }

        guard let activity = Activity<RestrictionLiveActivityAttributes>.activities.first else {
            return makeReport(
                outcome: .unsupported,
                detail: "The Shield Action extension could not discover the app-created activity."
            )
        }

        let originalState = activity.content.state
        let probeState: RestrictionLiveActivityAttributes.ContentState
        do {
            probeState = try .init(
                occurrenceID: originalState.occurrenceID,
                ruleDisplayName: originalState.ruleDisplayName,
                endsAt: originalState.endsAt,
                remainingDistance: originalState.remainingDistance,
                distanceObservedAt: originalState.distanceObservedAt,
                hasAdditionalRestrictions: originalState.hasAdditionalRestrictions
            )
        } catch {
            return makeReport(
                outcome: .failure,
                activityFound: true,
                detail: "The existing content state could not be reconstructed."
            )
        }

        await activity.update(ActivityContent(
            state: probeState,
            staleDate: probeState.endsAt
        ))

        let updateVerified = Activity<RestrictionLiveActivityAttributes>.activities.contains {
            $0.attributes.activityID == activity.attributes.activityID
                && $0.content.state == probeState
        }
        guard updateVerified else {
            return makeReport(
                outcome: .failure,
                activityFound: true,
                detail: "The update call returned, but the extension could not read back the new state."
            )
        }

        await activity.end(
            ActivityContent(state: probeState, staleDate: probeState.endsAt),
            dismissalPolicy: .immediate
        )

        return makeReport(
            outcome: .success,
            activityFound: true,
            updateVerified: true,
            endRequested: true,
            detail: "The extension discovered, updated, and requested immediate end for the app-created activity."
        )
    }

    private static func persist(_ report: Report) {
        guard
            let appGroupIdentifier = SharedIdentifiers.appGroupIdentifier(),
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            ),
            let data = try? JSONEncoder.probeEncoder.encode(report)
        else {
            return
        }

        let defaults = UserDefaults(suiteName: appGroupIdentifier)
        defaults?.set(data, forKey: resultDefaultsKey)
        defaults?.synchronize()

        try? data.write(
            to: containerURL.appendingPathComponent(resultFileName),
            options: .atomic
        )
    }

    private static func makeReport(
        outcome: Outcome,
        activityFound: Bool = false,
        updateVerified: Bool = false,
        endRequested: Bool = false,
        detail: String
    ) -> Report {
        Report(
            outcome: outcome,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            recordedAt: Date(),
            activityFound: activityFound,
            updateVerified: updateVerified,
            endRequested: endRequested,
            detail: detail
        )
    }

    private static func cancelledReport() -> Report {
        makeReport(
            outcome: .failure,
            detail: "The timeout task was cancelled after the probe completed."
        )
    }
}

private extension JSONEncoder {
    static var probeEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
#endif
