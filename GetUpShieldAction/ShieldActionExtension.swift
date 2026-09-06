import Foundation
@preconcurrency import ManagedSettings

private final class ShieldActionCompletion: @unchecked Sendable {
    let handler: (ShieldActionResponse) -> Void

    init(_ handler: @escaping (ShieldActionResponse) -> Void) {
        self.handler = handler
    }
}

private final class ShieldCoinActionRuntime: @unchecked Sendable {
    private let contextReader: ShieldCoinActionContextReader
    private let handler: ShieldCoinActionHandler
    private let routeRepository: PendingAppRouteRepository
    private let responsePolicy = ShieldActionResponsePolicy()

    private init(
        contextReader: ShieldCoinActionContextReader,
        handler: ShieldCoinActionHandler,
        routeRepository: PendingAppRouteRepository
    ) {
        self.contextReader = contextReader
        self.handler = handler
        self.routeRepository = routeRepository
    }

    static func live() -> ShieldCoinActionRuntime? {
        guard
            let identifier = SharedIdentifiers.appGroupIdentifier(),
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
            )
        else {
            return nil
        }

        let routeRepository = PendingAppRouteRepository(containerURL: containerURL)
        let handler = ShieldCoinActionHandler(
            // The operational CloudKit compatibility gate remains default-deny.
            // A verified adapter replaces this closure after that gate succeeds.
            releaseRepresentative: { _ in .iCloudRecoveryRequired },
            savePendingRoute: { route in
                try await routeRepository.save(route)
            }
        )
        return ShieldCoinActionRuntime(
            contextReader: ShieldCoinActionContextReader(containerURL: containerURL),
            handler: handler,
            routeRepository: routeRepository
        )
    }

    func handle(applicationToken: ApplicationToken) async -> ShieldActionResponse {
        await handle { try await contextReader.context(for: applicationToken) }
    }

    func handle(categoryToken: ActivityCategoryToken) async -> ShieldActionResponse {
        await handle { try await contextReader.context(for: categoryToken) }
    }

    func handle(webDomainToken: WebDomainToken) async -> ShieldActionResponse {
        await handle { try await contextReader.context(for: webDomainToken) }
    }

    private func handle(
        loadContext: () async throws -> ShieldCoinActionContext
    ) async -> ShieldActionResponse {
        do {
            let context = try await loadContext()
            return await handler.handlePrimaryAction(
                context: context,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
            ).response
        } catch {
            return await saveRecoveryRoute()
        }
    }

    private func saveRecoveryRoute() async -> ShieldActionResponse {
        do {
            try await routeRepository.save(PendingAppRoute(
                routeID: UUID(),
                destination: .iCloudRecovery,
                createdAt: Date(),
                occurrenceID: nil,
                consumedAt: nil
            ))
            return responsePolicy.responseAfterSavingRoute(
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
            )
        } catch {
            return .defer
        }
    }
}

final class ShieldActionExtension: ShieldActionDelegate {
    private let responsePolicy = ShieldActionResponsePolicy()
    private let runtime = ShieldCoinActionRuntime.live()

    private func complete(
        action: ShieldAction,
        primaryAction: @escaping @Sendable () async -> ShieldActionResponse,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        guard action == .primaryButtonPressed, runtime != nil else {
            completionHandler(responsePolicy.response(for: action))
            return
        }

        let completion = ShieldActionCompletion(completionHandler)
#if DEBUG
        ActivityKitFeasibilityProbe.recordInvocation()
#endif
        Task { [completion] in
#if DEBUG
            async let probe: ActivityKitFeasibilityProbe.Report = ActivityKitFeasibilityProbe.run()
#endif
            completion.handler(await primaryAction())
#if DEBUG
            _ = await probe
#endif
        }
    }

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(
            action: action,
            primaryAction: { [runtime] in
                await runtime?.handle(applicationToken: application) ?? .close
            },
            completionHandler: completionHandler
        )
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(
            action: action,
            primaryAction: { [runtime] in
                await runtime?.handle(categoryToken: category) ?? .close
            },
            completionHandler: completionHandler
        )
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(
            action: action,
            primaryAction: { [runtime] in
                await runtime?.handle(webDomainToken: webDomain) ?? .close
            },
            completionHandler: completionHandler
        )
    }
}
