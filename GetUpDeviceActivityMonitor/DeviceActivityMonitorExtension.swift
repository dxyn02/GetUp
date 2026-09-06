@preconcurrency import DeviceActivity
import Foundation

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
