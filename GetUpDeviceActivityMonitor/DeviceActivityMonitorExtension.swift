@preconcurrency import DeviceActivity
import Foundation
#if DEBUG
import ActivityKit
#endif

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        // 이 동기 경로는 Shield와 App Group occurrence만 갱신한다.
        // ActivityKit 시작·조정은 메인 앱 foreground 수명주기에만 맡긴다.
        if let handler = try? DeviceActivityIntervalRestrictionHandler.live(),
           handler.handle(activityName: activity.rawValue)
        {
            return
        }

        let confirmedAt = Date()
        Task { @MainActor in
            do {
                let container = try DependencyContainer.live()
                let restrictionCoordinator = try container
                    .makeRestrictionCoordinator()
                _ = try await restrictionCoordinator.handleTimeEvent(
                    confirmedAt: confirmedAt
                )
            } catch {
                // 보호 파일 read 또는 live 조립 실패 시 기존 shield와 schedule을
                // 보존하고 다음 시스템 event에서 다시 시도한다.
            }
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)

        #if DEBUG
        defer { DeviceActivityLiveActivityDiscoveryProbe.record() }
        #endif

        // 종료 callback도 최신 규칙·예외 전체를 동기 재평가하고 만료 예외를 정리한다.
        // ActivityKit에는 접근하지 않는다.
        if let handler = try? DeviceActivityIntervalRestrictionHandler.live(),
           handler.handle(activityName: activity.rawValue)
        {
            return
        }

        // 보호 snapshot을 읽지 못한 경우에만 마지막 규칙의 기존 안전 해제를 시도한다.
        // 이 fallback도 같은 App Group 잠금에 참여한다.
        if let handler = try? DeviceActivityIntervalEndHandler.live(),
           handler.handle(activityName: activity.rawValue)
        {
            return
        }

        let confirmedAt = Date()
        Task { @MainActor in
            do {
                let container = try DependencyContainer.live()
                let restrictionCoordinator = try container
                    .makeRestrictionCoordinator()
                _ = try await restrictionCoordinator.handleTimeEvent(
                    confirmedAt: confirmedAt
                )
            } catch {
                // 규칙 snapshot을 읽지 못하거나 live dependency 조립이 실패하면
                // 다른 활성 규칙을 오해해 지우지 않고 다음 시스템 event에서 재시도한다.
            }
        }
    }
}

#if DEBUG
// Discoverability is the first gate: do not mutate an activity before verifying
// that this extension can see the activity created by the containing app.
private enum DeviceActivityLiveActivityDiscoveryProbe {
    private struct Report: Codable {
        let recordedAt: Date
        let operatingSystemVersion: String
        let liveActivitiesEnabled: Bool
        let discoveredActivityCount: Int
    }

    static func record() {
        guard let identifier = SharedIdentifiers.appGroupIdentifier() else { return }
        let defaults = UserDefaults(suiteName: identifier)
        let diagnosticKey = "getup.debug.monitor-live-activity-probe"
        func recordStage(_ stage: String, count: Int? = nil) {
            var values: [String: Any] = [
                "stage": stage,
                "recordedAt": Date().timeIntervalSince1970,
                "operatingSystemVersion": ProcessInfo.processInfo.operatingSystemVersionString
            ]
            if let count { values["discoveredActivityCount"] = count }
            defaults?.set(values, forKey: diagnosticKey)
            // DEBUG-only checkpoint survives an extension returning immediately.
            defaults?.synchronize()
        }
        recordStage("beforeDiscovery")
        let count = Activity<RestrictionLiveActivityAttributes>.activities.count
        recordStage("discoveryCompleted", count: count)
        guard
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
              )
        else { return }

        let report = Report(
            recordedAt: Date(),
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            liveActivitiesEnabled: ActivityAuthorizationInfo().areActivitiesEnabled,
            discoveredActivityCount: count
        )
        let fileURL = containerURL.appendingPathComponent("device-activity-live-activity-probe.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var history = (try? Data(contentsOf: fileURL))
            .flatMap { try? decoder.decode([Report].self, from: $0) } ?? []
        history.append(report)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(Array(history.suffix(12))) else { return }
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            recordStage("fileWritten", count: count)
        } catch {
            recordStage("fileWriteFailed", count: count)
        }
    }
}
#endif
