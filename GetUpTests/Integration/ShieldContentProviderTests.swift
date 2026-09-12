@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings
import Testing
@testable import GetUp

@Suite("Shield content provider")
struct ShieldContentProviderTests {
    @Test("A single matching occurrence explains the representative, deadline, cost, and result")
    func singleOccurrenceShowsReleaseConfirmationCopy() throws {
        let token = try applicationToken(seed: 1)
        let rule = TestFixtures.makeRule(
            activitySelection: selection(tokens: [token])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule])
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(for: token)

        #expect(content.title == "집에서 500m 밖으로 나서세요")
        #expect(
            content.subtitle
                == "대표 규칙 ‘테스트 규칙’ · 07:50 AM까지 적용돼요. 무료 해제권을 먼저 사용하고, 없으면 구매 코인 1개를 사용해 이번 구간만 해제해요. 다른 규칙의 제한은 남지 않아요."
        )
        #expect(content.primaryButtonLabel == "해제권 1회 사용")
        #expect(content.secondaryButtonLabel == "앱 닫기")
    }

    @Test("English shield content localizes the Home preset name")
    func englishContentLocalizesHomePresetName() throws {
        let token = try applicationToken(seed: 11)
        let rule = TestFixtures.makeRule(
            activitySelection: selection(tokens: [token])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule])
            ),
            bundle: englishLocalizationBundle,
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(for: token)

        #expect(content.title == "Step 500m away from Home")
        #expect(
            content.subtitle
                == "Representative rule: ‘테스트 규칙’. It applies until 07:50 AM. Use a monthly free release first, or one purchased coin if none remain, to release only this interval. No other rule restriction will remain."
        )
        #expect(content.primaryButtonLabel == "Use 1 Release")
        #expect(content.secondaryButtonLabel == "Close App")
    }

    @Test("English shield content localizes the Work preset name")
    func englishContentLocalizesWorkPresetName() throws {
        let token = try applicationToken(seed: 12)
        let rule = TestFixtures.makeRule(
            activitySelection: selection(tokens: [token])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule], placeName: "회사")
            ),
            bundle: englishLocalizationBundle,
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(for: token)

        #expect(content.title == "Step 500m away from Work")
        #expect(content.subtitle.contains("Representative rule: ‘테스트 규칙’. It applies until 07:50 AM."))
    }

    @Test("Multiple matching occurrences select the earliest representative and warn what remains")
    func multipleOccurrencesSelectRepresentativeAndWarn() throws {
        let token = try applicationToken(seed: 2)
        let first = TestFixtures.makeRule(
            activitySelection: selection(tokens: [token])
        )
        let second = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000401")!,
            revision: 3,
            name: "두 번째 규칙",
            activitySelection: selection(tokens: [token])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(
                    rules: [second, first],
                    occurrences: [
                        try occurrence(for: second, activatedAt: TestFixtures.now.addingTimeInterval(-60)),
                        try occurrence(for: first, activatedAt: TestFixtures.now.addingTimeInterval(-120)),
                    ]
                )
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(for: token)

        #expect(content.title == "집에서 500m 밖으로 나서세요")
        #expect(content.subtitle.contains("대표 규칙 ‘테스트 규칙’ · 07:50 AM까지 적용돼요."))
        #expect(content.subtitle.hasSuffix("다른 규칙 1개의 제한은 남아요."))
        #expect(content.primaryButtonLabel == "해제권 1회 사용")
        #expect(content.secondaryButtonLabel == "앱 닫기")
    }

    @Test("A category shield for a custom saved place shows detailed content")
    func categoryShieldForCustomPlaceShowsDetailedContent() throws {
        let categoryToken = try TestFixtures.activityCategoryToken(seed: 3)
        let rule = TestFixtures.makeRule(
            activitySelection: selection(categoryTokens: [categoryToken])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule], placeName: "도서관")
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(
            for: nil,
            categoryToken: categoryToken
        )

        #expect(content.title == "도서관에서 500m 밖으로 나서세요")
        #expect(
            content.subtitle
                == "대표 규칙 ‘테스트 규칙’ · 07:50 AM까지 적용돼요. 무료 해제권을 먼저 사용하고, 없으면 구매 코인 1개를 사용해 이번 구간만 해제해요. 다른 규칙의 제한은 남지 않아요."
        )
    }

    @Test("A web domain shield for a custom saved place shows detailed content")
    func webDomainShieldForCustomPlaceShowsDetailedContent() throws {
        let webDomainToken = try TestFixtures.webDomainToken(seed: 4)
        let rule = TestFixtures.makeRule(
            activitySelection: selection(webDomainTokens: [webDomainToken])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule], placeName: "스터디 카페")
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(
            for: nil,
            webDomainToken: webDomainToken
        )

        #expect(content.title == "스터디 카페에서 500m 밖으로 나서세요")
    }

    @Test(
        "Every readable balance state presents the same free-first release agreement",
        arguments: CoinBalanceSyncState.allCasesForShieldPresentation
    )
    func balanceStateDoesNotPreselectFundingSource(syncState: CoinBalanceSyncState) throws {
        let token = try applicationToken(seed: 5)
        let rule = TestFixtures.makeRule(activitySelection: selection(tokens: [token]))
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(
                    rules: [rule],
                    balance: try balance(syncState: syncState)
                )
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(for: token)

        #expect(content.primaryButtonLabel == "해제권 1회 사용")
        #expect(content.secondaryButtonLabel == "앱 닫기")
        #expect(content.subtitle.contains("무료 해제권을 먼저 사용하고, 없으면 구매 코인 1개"))
        #expect(
            content.releaseFundingPolicy
                == .latestLedgerFreeFirst(purchasedFallbackQuantity: 1)
        )
    }

    @Test(
        "Mirror quantities never change the disclosed funding policy",
        arguments: [(2, 0), (0, 3), (0, 0), (2, 3)]
    )
    func mirrorQuantitiesDoNotPredictFundingSource(
        freeAvailable: Int,
        purchasedAvailable: Int
    ) throws {
        let token = try applicationToken(seed: UInt8(20 + freeAvailable + purchasedAvailable))
        let rule = TestFixtures.makeRule(activitySelection: selection(tokens: [token]))
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(
                    rules: [rule],
                    balance: try balance(
                        freeAvailable: freeAvailable,
                        purchasedAvailable: purchasedAvailable
                    )
                )
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(for: token)

        #expect(content.primaryButtonLabel == "해제권 1회 사용")
        #expect(content.subtitle.contains("무료 해제권을 먼저 사용하고, 없으면 구매 코인 1개"))
        #expect(
            content.releaseFundingPolicy
                == .latestLedgerFreeFirst(purchasedFallbackQuantity: 1)
        )
    }

    @Test("A missing token or unreadable snapshot uses privacy-safe fallback copy")
    func unavailableSnapshotUsesFallback() throws {
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(error: TestFailure.expected)
        )

        let content = provider.content(for: nil)

        #expect(content.title == "밖으로 나설 시간이에요")
        #expect(content.subtitle == "설정한 위치에서 벗어나거나 시간이 끝나면 자동으로 다시 사용할 수 있어요.")
        #expect(content.primaryButtonLabel == "앱 닫기")
        #expect(content.secondaryButtonLabel == nil)
    }

    @Test("The diagnostic identifies a missing Shield token before reading snapshots")
    func missingTokenDiagnosticIsSpecific() {
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(error: TestFailure.expected),
            now: { TestFixtures.now }
        )

        let result = provider.contentResult(for: nil)

        #expect(result.diagnostic.outcome == .fallback)
        #expect(result.diagnostic.fallbackReason == .missingShieldToken)
        #expect(result.diagnostic.recordedAt == TestFixtures.now)
        #expect(result.diagnostic.ruleCount == nil)
    }

    @Test("The diagnostic identifies the exact unreadable App Group snapshot")
    func snapshotDiagnosticIncludesFailingFile() throws {
        let token = try applicationToken(seed: 31)
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                error: ShieldSnapshotReaderError.snapshotDecodingFailed(
                    fileName: SharedIdentifiers.activeRestrictionSnapshotFileName
                )
            ),
            now: { TestFixtures.now }
        )

        let result = provider.contentResult(for: token)

        #expect(result.diagnostic.outcome == .fallback)
        #expect(result.diagnostic.fallbackReason == .snapshotDecodingFailed)
        #expect(
            result.diagnostic.failingFileName
                == SharedIdentifiers.activeRestrictionSnapshotFileName
        )
        #expect(result.diagnostic.hasApplicationToken)
    }

    @Test("The diagnostic separates active occurrences from token matches")
    func unmatchedTokenDiagnosticIncludesCountsAndSchemas() throws {
        let selectedToken = try applicationToken(seed: 32)
        let shieldToken = try applicationToken(seed: 33)
        let rule = TestFixtures.makeRule(
            activitySelection: selection(tokens: [selectedToken])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule])
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let result = provider.contentResult(for: shieldToken)

        #expect(result.diagnostic.fallbackReason == .noMatchingOccurrence)
        #expect(result.diagnostic.ruleCount == 1)
        #expect(result.diagnostic.savedPlaceCount == 1)
        #expect(result.diagnostic.activeOccurrenceCount == 1)
        #expect(result.diagnostic.matchingOccurrenceCount == 0)
        #expect(
            result.diagnostic.rulesSchemaVersion
                == RestrictionRuleCollectionSnapshot.currentSchemaVersion
        )
    }

    @Test("An expired stored application token is refreshed before Shield matching")
    func expiredApplicationTokenIsRefreshedBeforeMatching() throws {
        let expiredToken = try applicationToken(seed: 34)
        let callbackToken = try applicationToken(seed: 35)
        let rule = TestFixtures.makeRule(
            activitySelection: selection(tokens: [expiredToken])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule])
            ),
            tokenRefresher: FixedShieldTokenRefresher(
                refreshedApplicationTokens: [callbackToken]
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let result = provider.contentResult(for: callbackToken)

        #expect(result.diagnostic.outcome == .releaseContent)
        #expect(result.diagnostic.fallbackReason == .none)
        #expect(result.diagnostic.activeOccurrenceCount == 1)
        #expect(result.diagnostic.matchingOccurrenceCount == 1)
        #expect(result.content.primaryButtonLabel == "해제권 1회 사용")
    }

    @Test("An expired or missing representative occurrence uses the close-only fallback")
    func missingRepresentativeUsesCloseOnlyFallback() throws {
        let token = try applicationToken(seed: 6)
        let rule = TestFixtures.makeRule(activitySelection: selection(tokens: [token]))
        let expired = try occurrence(
            for: rule,
            endAt: TestFixtures.now,
            activatedAt: TestFixtures.now.addingTimeInterval(-600)
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule], occurrences: [expired])
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(for: token)

        #expect(content.primaryButtonLabel == "앱 닫기")
        #expect(content.secondaryButtonLabel == nil)
    }

    @Test("Duplicate rule identities are treated as a corrupt close-only snapshot")
    func duplicateRuleIdentityUsesCloseOnlyFallback() throws {
        let token = try applicationToken(seed: 7)
        let first = TestFixtures.makeRule(activitySelection: selection(tokens: [token]))
        let duplicate = TestFixtures.makeRule(
            id: first.id,
            revision: first.revision,
            name: "중복 규칙",
            activitySelection: selection(tokens: [token])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(
                    rules: [first, duplicate],
                    occurrences: [try occurrence(for: first)]
                )
            ),
            now: { TestFixtures.now },
            calendar: TestFixtures.calendar
        )

        let content = provider.content(for: token)

        #expect(content.primaryButtonLabel == "앱 닫기")
        #expect(content.secondaryButtonLabel == nil)
    }

    private func snapshot(
        rules: [RestrictionRuleSnapshot],
        placeName: String = "집",
        occurrences: [RestrictionOccurrence]? = nil,
        balance: CoinBalanceSnapshot? = nil
    ) -> ShieldContentSnapshot {
        let resolvedOccurrences = occurrences ?? rules.map { try! occurrence(for: $0) }
        return ShieldContentSnapshot(
            rules: RestrictionRuleCollectionSnapshot(revision: 1, rules: rules),
            savedPlaces: SavedPlaceCollectionSnapshot(
                revision: 1,
                places: [
                    SavedPlaceSnapshot(
                        id: rules.first?.savedPlaceID ?? TestFixtures.makeRule().savedPlaceID,
                        name: placeName,
                        coordinate: ReferenceLocation(latitude: 37, longitude: 127),
                        createdAt: TestFixtures.now,
                        updatedAt: TestFixtures.now
                    ),
                ]
            ),
            activeRestrictions: try! ActiveRestrictionSnapshot(
                revision: 1,
                occurrences: resolvedOccurrences,
                observedAt: TestFixtures.now
            ),
            coinBalance: balance ?? (try! self.balance(syncState: .current))
        )
    }

    private func occurrence(
        for rule: RestrictionRuleSnapshot,
        endAt: Date = TestFixtures.now.addingTimeInterval(3_000),
        activatedAt: Date = TestFixtures.now.addingTimeInterval(-300)
    ) throws -> RestrictionOccurrence {
        try RestrictionOccurrence(
            ruleID: rule.id,
            ruleRevision: rule.revision,
            startAt: TestFixtures.now.addingTimeInterval(-600),
            endAt: endAt,
            activatedAt: activatedAt
        )
    }

    private func balance(syncState: CoinBalanceSyncState) throws -> CoinBalanceSnapshot {
        try balance(
            freeAvailable: syncState == .current ? 1 : 0,
            purchasedAvailable: syncState == .current ? 3 : 0,
            syncState: syncState
        )
    }

    private func balance(
        freeAvailable: Int,
        purchasedAvailable: Int,
        syncState: CoinBalanceSyncState = .current
    ) throws -> CoinBalanceSnapshot {
        try CoinBalanceSnapshot(
            purchasedAvailable: purchasedAvailable,
            currentMonthID: "2026-09",
            freeAvailable: freeAvailable,
            syncState: syncState,
            syncedAt: TestFixtures.now,
            ledgerEpochID: syncState == .current
                ? UUID(uuidString: "00000000-0000-4000-8000-000000000501")!
                : nil,
            hadConfirmedLedger: syncState == .current
        )
    }

    private func selection(
        tokens: Set<ApplicationToken> = [],
        categoryTokens: Set<ActivityCategoryToken> = [],
        webDomainTokens: Set<WebDomainToken> = []
    ) -> FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        selection.applicationTokens = tokens
        selection.categoryTokens = categoryTokens
        selection.webDomainTokens = webDomainTokens
        return selection
    }

    private func applicationToken(seed: UInt8) throws -> ApplicationToken {
        let data = try JSONEncoder().encode(["data": Data([seed])])
        return try JSONDecoder().decode(ApplicationToken.self, from: data)
    }

    private var englishLocalizationBundle: Bundle {
        let path = Bundle.main.path(forResource: "en", ofType: "lproj")!
        return Bundle(path: path)!
    }
}

private extension CoinBalanceSyncState {
    static let allCasesForShieldPresentation: [Self] = [
        .setupRequired,
        .current,
        .syncing,
        .stale,
        .unavailable,
        .deletionConfirmed,
        .resetRequired,
    ]
}

private struct FixedShieldSnapshotReader: ShieldSnapshotReading {
    let result: Result<ShieldContentSnapshot, any Error>

    init(snapshot: ShieldContentSnapshot) {
        result = .success(snapshot)
    }

    init(error: any Error) {
        result = .failure(error)
    }

    func readSnapshot() throws -> ShieldContentSnapshot {
        try result.get()
    }
}

private enum TestFailure: Error {
    case expected
}

private struct FixedShieldTokenRefresher: ShieldTokenRefreshing {
    var refreshedApplicationTokens: Set<ApplicationToken> = []
    var refreshedCategoryTokens: Set<ActivityCategoryToken> = []
    var refreshedWebDomainTokens: Set<WebDomainToken> = []

    func applicationTokens(
        _ tokens: Set<ApplicationToken>
    ) throws -> Set<ApplicationToken> {
        refreshedApplicationTokens
    }

    func categoryTokens(
        _ tokens: Set<ActivityCategoryToken>
    ) throws -> Set<ActivityCategoryToken> {
        refreshedCategoryTokens
    }

    func webDomainTokens(
        _ tokens: Set<WebDomainToken>
    ) throws -> Set<WebDomainToken> {
        refreshedWebDomainTokens
    }
}
