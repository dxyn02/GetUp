import Foundation
import StoreKitTest
import Testing

@Suite("StoreKit configuration", .serialized)
struct StoreKitConfigurationTests {
    @Test("Configuration declares the approved consumables with Korean and English copy")
    func configurationContent() throws {
        let data = try Data(contentsOf: Self.configurationURL)
        let configuration = try JSONDecoder().decode(
            StoreKitConfigurationFixture.self,
            from: data
        )
        let products = configuration.products

        let expected: [String: (price: String, ko: String, en: String)] = [
            "com.dxyn02.GetUp.coin.1": ("1100", "코인 1개", "1 Coin"),
            "com.dxyn02.GetUp.coin.3": ("2900", "코인 3개", "3 Coins"),
            "com.dxyn02.GetUp.coin.5": ("4400", "코인 5개", "5 Coins"),
        ]
        #expect(products.count == 3)
        #expect(Set(products.map(\.productID)) == Set(expected.keys))

        for product in products {
            let fixture = try #require(expected[product.productID])
            #expect(product.type == "Consumable")
            #expect(product.displayPrice == fixture.price)
            #expect(!product.familyShareable)
            #expect(product.localizations.count == 2)
            let byLocale = Dictionary(
                uniqueKeysWithValues: product.localizations.map { ($0.locale, $0) }
            )
            #expect(byLocale["ko_KR"]?.displayName == fixture.ko)
            #expect(byLocale["en_US"]?.displayName == fixture.en)
            #expect(byLocale["ko_KR"]?.description.isEmpty == false)
            #expect(byLocale["en_US"]?.description.isEmpty == false)
        }
    }

    @Test("StoreKit test session accepts and resets the configuration")
    func storeKitAcceptsConfiguration() throws {
        let session = try SKTestSession(contentsOf: Self.configurationURL)
        session.resetToDefaultState()
        #expect(session.allTransactions().isEmpty)
    }

    private static var configurationURL: URL {
        get throws {
            try #require(
                Bundle(for: StoreKitConfigurationBundleToken.self).url(
                    forResource: "GetUp",
                    withExtension: "storekit"
                )
            )
        }
    }
}

private final class StoreKitConfigurationBundleToken {}

private struct StoreKitConfigurationFixture: Decodable {
    let products: [StoreKitProductFixture]
}

private struct StoreKitProductFixture: Decodable {
    let displayPrice: String
    let familyShareable: Bool
    let localizations: [StoreKitLocalizationFixture]
    let productID: String
    let type: String
}

private struct StoreKitLocalizationFixture: Decodable {
    let description: String
    let displayName: String
    let locale: String
}
