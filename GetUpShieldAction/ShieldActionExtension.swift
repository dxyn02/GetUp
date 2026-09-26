import Foundation
@preconcurrency import ManagedSettings

private final class ShieldActionCompletion: @unchecked Sendable {
    let handler: (ShieldActionResponse) -> Void

    init(_ handler: @escaping (ShieldActionResponse) -> Void) {
        self.handler = handler
    }
}

private final class ShieldActionDiagnosticRecorder: @unchecked Sendable {
    private let defaults: UserDefaults?

    init(appGroupIdentifier: String) {
        defaults = UserDefaults(suiteName: appGroupIdentifier)
    }

    func record(_ stage: String, detail: String? = nil) {
        var value: [String: Any] = [
            "stage": stage,
            "recordedAt": Date().timeIntervalSince1970
        ]
        if let detail {
            value["detail"] = detail
        }
        defaults?.set(value, forKey: SharedIdentifiers.shieldActionDiagnosticDefaultsKey)
        defaults?.synchronize()
    }

    func errorDetail(_ error: any Error) -> String {
        if let error = error as? ShieldCoinActionContextReaderError {
            switch error {
            case .snapshotUnavailable: return "snapshotUnavailable"
            case .noMatchingOccurrence: return "noMatchingOccurrence"
            }
        }
        return String(describing: type(of: error))
    }
}

/// Production entry point: local occurrence lookup and an App Group route write only.
private final class ShieldReleaseRouteRuntime: @unchecked Sendable {
    private let contextReader: ShieldCoinActionContextReader
    private let handler: ShieldReleaseRouteHandler
    private let diagnosticRecorder: ShieldActionDiagnosticRecorder

    private init(
        contextReader: ShieldCoinActionContextReader,
        handler: ShieldReleaseRouteHandler,
        diagnosticRecorder: ShieldActionDiagnosticRecorder
    ) {
        self.contextReader = contextReader
        self.handler = handler
        self.diagnosticRecorder = diagnosticRecorder
    }

    static func live() -> ShieldReleaseRouteRuntime? {
        guard let identifier = SharedIdentifiers.appGroupIdentifier(),
              let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: identifier
              ) else {
            return nil
        }
        let repository = PendingAppRouteRepository(containerURL: containerURL)
        return ShieldReleaseRouteRuntime(
            contextReader: ShieldCoinActionContextReader(containerURL: containerURL),
            handler: ShieldReleaseRouteHandler(
                loadRoute: { try await repository.load() },
                saveRoute: { try await repository.save($0) }
            ),
            diagnosticRecorder: ShieldActionDiagnosticRecorder(appGroupIdentifier: identifier)
        )
    }

    func handle(applicationToken: ApplicationToken) async -> ShieldActionResponse {
        await handle { [contextReader] in
            try contextReader.releaseOccurrence(for: applicationToken)
        }
    }

    func handle(categoryToken: ActivityCategoryToken) async -> ShieldActionResponse {
        await handle { [contextReader] in
            try contextReader.releaseOccurrence(for: categoryToken)
        }
    }

    func handle(webDomainToken: WebDomainToken) async -> ShieldActionResponse {
        await handle { [contextReader] in
            try contextReader.releaseOccurrence(for: webDomainToken)
        }
    }

    private func handle(
        loadOccurrence: @Sendable () throws -> RestrictionOccurrence
    ) async -> ShieldActionResponse {
        do {
            let occurrence = try loadOccurrence()
            let response = await handler.handlePrimaryAction(
                occurrenceID: occurrence.id,
                operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersion
            )
#if DEBUG
            diagnosticRecorder.record(
                response == .defer ? "releaseRouteFailed" : "releaseRouteSaved"
            )
#endif
            return response
        } catch {
#if DEBUG
            diagnosticRecorder.record(
                "releaseContextUnavailable",
                detail: diagnosticRecorder.errorDetail(error)
            )
#endif
            return .defer
        }
    }
}

final class ShieldActionExtension: ShieldActionDelegate {
    private let responsePolicy = ShieldActionResponsePolicy()
    private let runtime = ShieldReleaseRouteRuntime.live()

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
