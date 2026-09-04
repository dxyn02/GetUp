@preconcurrency import ManagedSettings

#if DEBUG
private final class ShieldActionCompletion: @unchecked Sendable {
    let handler: (ShieldActionResponse) -> Void

    init(_ handler: @escaping (ShieldActionResponse) -> Void) {
        self.handler = handler
    }
}
#endif

final class ShieldActionExtension: ShieldActionDelegate {
    private let responsePolicy = ShieldActionResponsePolicy()

    private func complete(
        action: ShieldAction,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        let response = responsePolicy.response(for: action)
#if DEBUG
        ActivityKitFeasibilityProbe.recordInvocation()
        let completion = ShieldActionCompletion(completionHandler)
        Task { [completion] in
            _ = await ActivityKitFeasibilityProbe.run()
            completion.handler(response)
        }
#else
        completionHandler(response)
#endif
    }

    override func handle(
        action: ShieldAction,
        for application: ApplicationToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for category: ActivityCategoryToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(action: action, completionHandler: completionHandler)
    }

    override func handle(
        action: ShieldAction,
        for webDomain: WebDomainToken,
        completionHandler: @escaping (ShieldActionResponse) -> Void
    ) {
        complete(action: action, completionHandler: completionHandler)
    }
}
