import Foundation
import Testing
@testable import GetUp

@Suite("Coin product catalog")
struct CoinProductCatalogTests {
    @Test("Bundle catalog maps only the approved one, three, and five coin products")
    func bundleCatalogMapsApprovedProductsExactly() throws {
        let catalog = try CoinProductCatalog(bundle: .main)

        #expect(catalog.productIdentifiers == Self.expectedProductIdentifiers)
        #expect(catalog.quantity(for: Self.oneCoinProductID) == 1)
        #expect(catalog.quantity(for: Self.threeCoinProductID) == 3)
        #expect(catalog.quantity(for: Self.fiveCoinProductID) == 5)
        #expect(catalog.quantity(for: "com.dxyn02.GetUp.coin.10") == nil)
    }

    @Test("Catalog rejects missing, duplicate, or altered product mappings")
    func rejectsAnythingOtherThanExactApprovedMappings() {
        let invalidConfigurations: [[String: Any]] = [
            Self.infoDictionary(entries: [
                (Self.oneCoinProductID, 1),
                (Self.threeCoinProductID, 3),
            ]),
            Self.infoDictionary(entries: [
                (Self.oneCoinProductID, 1),
                (Self.threeCoinProductID, 3),
                (Self.threeCoinProductID, 5),
            ]),
            Self.infoDictionary(entries: [
                (Self.oneCoinProductID, 1),
                (Self.threeCoinProductID, 3),
                (Self.fiveCoinProductID, 10),
            ]),
        ]

        for configuration in invalidConfigurations {
            #expect(throws: CoinProductCatalogError.invalidConfiguration) {
                try CoinProductCatalog(infoDictionary: configuration)
            }
        }
    }

    @Test("Loaded products retain StoreKit localized copy and price and sort by quantity")
    func retainsLocalizedStoreKitPresentation() async throws {
        let catalog = try Self.catalog()
        let storefront = CoinStorefrontFake(products: [.success([
            Self.product(
                id: Self.fiveCoinProductID,
                name: "다섯 코인",
                description: "해제권 5회",
                price: "₩4,400"
            ),
            Self.product(
                id: Self.oneCoinProductID,
                name: "코인 1개",
                description: "제한을 한 번 해제합니다.",
                price: "₩1,100"
            ),
            Self.product(
                id: Self.threeCoinProductID,
                name: "Three Coins",
                description: "Three restriction releases",
                price: "$1.99"
            ),
        ])])

        let result = try await catalog.loadProducts(from: storefront)

        #expect(result.availableProducts.map(\.quantity) == [1, 3, 5])
        #expect(result.availableProducts.map(\.product.displayName) == [
            "코인 1개", "Three Coins", "다섯 코인",
        ])
        #expect(result.availableProducts.map(\.product.displayDescription) == [
            "제한을 한 번 해제합니다.", "Three restriction releases", "해제권 5회",
        ])
        #expect(result.availableProducts.map(\.product.displayPrice) == [
            "₩1,100", "$1.99", "₩4,400",
        ])
        #expect(result.unavailableProductIdentifiers.isEmpty)
        #expect(await storefront.productRequests == [Self.expectedProductIdentifiers])
    }

    @Test("Missing StoreKit products are reported unavailable without invented prices")
    func reportsPartiallyUnavailableProducts() async throws {
        let catalog = try Self.catalog()
        let storefront = CoinStorefrontFake(products: [.success([
            Self.product(id: Self.oneCoinProductID, price: "₩1,100"),
            Self.product(id: Self.fiveCoinProductID, price: "₩4,400"),
        ])])

        let result = try await catalog.loadProducts(from: storefront)

        #expect(result.availableProducts.map(\.quantity) == [1, 5])
        #expect(result.availableProducts.map(\.product.displayPrice) == ["₩1,100", "₩4,400"])
        #expect(result.unavailableProductIdentifiers == [Self.threeCoinProductID])
        #expect(result.availableProducts.allSatisfy { !$0.product.displayPrice.isEmpty })
    }

    @Test("Unexpected StoreKit products never enter the approved catalog")
    func ignoresUnexpectedStoreKitProducts() async throws {
        let catalog = try Self.catalog()
        let storefront = CoinStorefrontFake(products: [.success([
            Self.product(id: Self.oneCoinProductID, price: "₩1,100"),
            Self.product(id: "com.dxyn02.GetUp.coin.100", price: "₩99,000"),
        ])])

        let result = try await catalog.loadProducts(from: storefront)

        #expect(result.availableProducts.map(\.product.id) == [Self.oneCoinProductID])
        #expect(result.unavailableProductIdentifiers == [
            Self.threeCoinProductID,
            Self.fiveCoinProductID,
        ])
    }

    @Test("A reload failure throws and never returns a previously displayed price")
    func reloadFailureDoesNotReusePreviousProducts() async throws {
        let catalog = try Self.catalog()
        let storefront = CoinStorefrontFake(products: [
            .success([
                Self.product(id: Self.oneCoinProductID, price: "₩1,100"),
                Self.product(id: Self.threeCoinProductID, price: "₩2,900"),
                Self.product(id: Self.fiveCoinProductID, price: "₩4,400"),
            ]),
            .failure(.productUnavailable),
        ])

        let firstResult = try await catalog.loadProducts(from: storefront)
        #expect(firstResult.availableProducts.map(\.product.displayPrice) == [
            "₩1,100", "₩2,900", "₩4,400",
        ])

        await #expect(throws: CoinStoreError.productUnavailable) {
            try await catalog.loadProducts(from: storefront)
        }
        #expect(await storefront.productRequests.count == 2)
    }
}

private extension CoinProductCatalogTests {
    static let oneCoinProductID = "com.dxyn02.GetUp.coin.1"
    static let threeCoinProductID = "com.dxyn02.GetUp.coin.3"
    static let fiveCoinProductID = "com.dxyn02.GetUp.coin.5"

    static let expectedProductIdentifiers: Set<String> = [
        oneCoinProductID,
        threeCoinProductID,
        fiveCoinProductID,
    ]

    static func catalog() throws -> CoinProductCatalog {
        try CoinProductCatalog(infoDictionary: infoDictionary(entries: [
            (oneCoinProductID, 1),
            (threeCoinProductID, 3),
            (fiveCoinProductID, 5),
        ]))
    }

    static func infoDictionary(entries: [(String, Int)]) -> [String: Any] {
        [
            SharedIdentifiers.coinProductCatalogInfoDictionaryKey: entries.map { identifier, quantity in
                [
                    SharedIdentifiers.coinProductIdentifierCatalogKey: identifier,
                    SharedIdentifiers.coinProductQuantityCatalogKey: quantity,
                ] as [String: Any]
            },
        ]
    }

    static func product(
        id: String,
        name: String = "Coin",
        description: String = "Restriction release coin",
        price: String
    ) -> CoinStoreProduct {
        CoinStoreProduct(
            id: id,
            displayName: name,
            displayDescription: description,
            displayPrice: price
        )
    }
}
