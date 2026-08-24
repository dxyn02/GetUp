@preconcurrency import DeviceActivity
import Foundation

final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)

        Task { @MainActor in
            do {
                let container = try DependencyContainer.live()
                let lifecycle = try AppLifecycleCoordinator.live(
                    container: container
                )
                _ = try await lifecycle.restore()
            } catch {
                // 보호 파일을 아직 읽을 수 없거나 live dependency 조립이 실패하면
                // 기존 shield 상태를 보존하고 다음 시스템 event에서 다시 시도한다.
            }
        }
    }
}
