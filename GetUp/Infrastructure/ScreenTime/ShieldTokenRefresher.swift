@preconcurrency import FamilyControls
@preconcurrency import ManagedSettings

protocol ShieldTokenRefreshing: Sendable {
    func applicationTokens(_ tokens: Set<ApplicationToken>) throws -> Set<ApplicationToken>
    func categoryTokens(
        _ tokens: Set<ActivityCategoryToken>
    ) throws -> Set<ActivityCategoryToken>
    func webDomainTokens(_ tokens: Set<WebDomainToken>) throws -> Set<WebDomainToken>
}

struct SystemShieldTokenRefresher: ShieldTokenRefreshing {
    func applicationTokens(
        _ tokens: Set<ApplicationToken>
    ) throws -> Set<ApplicationToken> {
        guard #available(iOS 26.5, *) else {
            return tokens
        }
        var refreshed = Array(tokens)
        try ManagedSettingsStore.refresh(&refreshed)
        return Set(refreshed)
    }

    func categoryTokens(
        _ tokens: Set<ActivityCategoryToken>
    ) throws -> Set<ActivityCategoryToken> {
        guard #available(iOS 26.5, *) else {
            return tokens
        }
        var refreshed = Array(tokens)
        try ManagedSettingsStore.refresh(&refreshed)
        return Set(refreshed)
    }

    func webDomainTokens(
        _ tokens: Set<WebDomainToken>
    ) throws -> Set<WebDomainToken> {
        guard #available(iOS 26.5, *) else {
            return tokens
        }
        var refreshed = Array(tokens)
        try ManagedSettingsStore.refresh(&refreshed)
        return Set(refreshed)
    }
}

func shieldTokenMatches<Token: Hashable>(
    _ callbackToken: Token,
    storedTokens: Set<Token>,
    refresh: (Set<Token>) throws -> Set<Token>
) -> Bool {
    if storedTokens.contains(callbackToken) {
        return true
    }
    return (try? refresh(storedTokens).contains(callbackToken)) == true
}
