@preconcurrency import FamilyControls
import Foundation
@preconcurrency import ManagedSettings
import Testing
@testable import GetUp

@Suite("Shield content provider")
struct ShieldContentProviderTests {
    @Test("A single matching active rule shows its place, radius, and end time")
    func singleRuleShowsApprovedDetailedCopy() throws {
        let token = try applicationToken(seed: 1)
        let rule = TestFixtures.makeRule(
            activitySelection: selection(tokens: [token])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [rule])
            )
        )

        let content = provider.content(for: token)

        #expect(content.title == "집에서 500m 밖으로 나서세요")
        #expect(
            content.subtitle
                == "현재 ‘집’의 500m 범위 안에 있어요. 집의 중심에서 500m 밖으로 이동하거나 09:00 AM이 되면 자동으로 다시 사용할 수 있어요."
        )
        #expect(content.primaryButtonLabel == "앱 닫기")
    }

    @Test("Multiple matching active rules use the short accurate summary")
    func multipleRulesUseSummary() throws {
        let token = try applicationToken(seed: 2)
        let first = TestFixtures.makeRule(
            activitySelection: selection(tokens: [token])
        )
        let second = TestFixtures.makeRule(
            id: UUID(uuidString: "00000000-0000-4000-8000-000000000401")!,
            revision: 3,
            activitySelection: selection(tokens: [token])
        )
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(
                snapshot: snapshot(rules: [first, second])
            )
        )

        let content = provider.content(for: token)

        #expect(content.title == "2개 제한 규칙이 활성화 중이에요")
        #expect(content.subtitle == "각 규칙의 위치 또는 시간이 모두 끝나면 다시 사용할 수 있어요.")
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
            )
        )

        let content = provider.content(
            for: nil,
            categoryToken: categoryToken
        )

        #expect(content.title == "도서관에서 500m 밖으로 나서세요")
        #expect(
            content.subtitle
                == "현재 ‘도서관’의 500m 범위 안에 있어요. 도서관의 중심에서 500m 밖으로 이동하거나 09:00 AM이 되면 자동으로 다시 사용할 수 있어요."
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
            )
        )

        let content = provider.content(
            for: nil,
            webDomainToken: webDomainToken
        )

        #expect(content.title == "스터디 카페에서 500m 밖으로 나서세요")
    }

    @Test("A missing token or unreadable snapshot uses privacy-safe fallback copy")
    func unavailableSnapshotUsesFallback() throws {
        let provider = ShieldContentProvider(
            snapshotReader: FixedShieldSnapshotReader(error: TestFailure.expected)
        )

        let content = provider.content(for: nil)

        #expect(content.title == "밖으로 나설 시간이에요")
        #expect(
            content.subtitle
                == "설정한 위치에서 벗어나거나 시간이 끝나면 자동으로 다시 사용할 수 있어요."
        )
    }

    private func snapshot(
        rules: [RestrictionRuleSnapshot],
        placeName: String = "집"
    ) -> ShieldContentSnapshot {
        ShieldContentSnapshot(
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
            activeRuleRevisions: Set(
                rules.map {
                    ActiveRuleRevision(ruleID: $0.id, revision: $0.revision)
                }
            )
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
