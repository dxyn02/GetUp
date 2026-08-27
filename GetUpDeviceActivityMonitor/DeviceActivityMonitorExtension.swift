@preconcurrency import DeviceActivity
import Foundation

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        if let handler = try? DeviceActivityIntervalStartHandler.live(),
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
