@preconcurrency import ManagedSettings

struct ShieldActionResponsePolicy {
    func response(for _: ShieldAction) -> ShieldActionResponse {
        .close
    }
}
