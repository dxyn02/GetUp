import Foundation

enum CoinProductCatalogError: Error, Equatable, Sendable {
    case invalidConfiguration
}

struct CoinCatalogProduct: Equatable, Sendable {
    let product: CoinStoreProduct
    let quantity: Int
}

struct CoinProductCatalogLoadResult: Equatable, Sendable {
    let availableProducts: [CoinCatalogProduct]
    let unavailableProductIdentifiers: [String]
}

struct CoinProductCatalog: Sendable {
    private static let approvedQuantitiesByProductIdentifier = [
        "com.dxyn02.GetUp.coin.1": 1,
        "com.dxyn02.GetUp.coin.3": 3,
        "com.dxyn02.GetUp.coin.5": 5,
    ]

    private let quantitiesByProductIdentifier: [String: Int]

    var productIdentifiers: Set<String> {
        Set(quantitiesByProductIdentifier.keys)
    }

    init(bundle: Bundle = .main) throws {
        try self.init(infoDictionary: bundle.infoDictionary ?? [:])
    }

    init(infoDictionary: [String: Any]) throws {
        guard
            let entries = infoDictionary[
                SharedIdentifiers.coinProductCatalogInfoDictionaryKey
            ] as? [[String: Any]],
            entries.count == Self.approvedQuantitiesByProductIdentifier.count
        else {
            throw CoinProductCatalogError.invalidConfiguration
        }

        var configuredQuantities: [String: Int] = [:]
        configuredQuantities.reserveCapacity(entries.count)

        for entry in entries {
            guard
                let productIdentifier = entry[
                    SharedIdentifiers.coinProductIdentifierCatalogKey
                ] as? String,
                let quantity = entry[
                    SharedIdentifiers.coinProductQuantityCatalogKey
                ] as? Int,
                Self.approvedQuantitiesByProductIdentifier[productIdentifier] == quantity,
                configuredQuantities.updateValue(
                    quantity,
                    forKey: productIdentifier
                ) == nil
            else {
                throw CoinProductCatalogError.invalidConfiguration
            }
        }

        guard configuredQuantities == Self.approvedQuantitiesByProductIdentifier else {
            throw CoinProductCatalogError.invalidConfiguration
        }

        quantitiesByProductIdentifier = configuredQuantities
    }

    func quantity(for productIdentifier: String) -> Int? {
        quantitiesByProductIdentifier[productIdentifier]
    }

    func loadProducts(
        from storefront: any CoinStorefront
    ) async throws -> CoinProductCatalogLoadResult {
        let loadedProducts = try await storefront.products(for: productIdentifiers)
        var productsByIdentifier: [String: CoinStoreProduct] = [:]
        var duplicateIdentifiers: Set<String> = []

        for product in loadedProducts
        where quantitiesByProductIdentifier[product.id] != nil && !product.displayPrice.isEmpty {
            if productsByIdentifier.updateValue(product, forKey: product.id) != nil {
                duplicateIdentifiers.insert(product.id)
            }
        }

        for duplicateIdentifier in duplicateIdentifiers {
            productsByIdentifier.removeValue(forKey: duplicateIdentifier)
        }

        let sortedMappings = quantitiesByProductIdentifier.sorted { lhs, rhs in
            if lhs.value == rhs.value {
                return lhs.key < rhs.key
            }
            return lhs.value < rhs.value
        }
        let availableProducts = sortedMappings.compactMap { productIdentifier, quantity in
            productsByIdentifier[productIdentifier].map {
                CoinCatalogProduct(product: $0, quantity: quantity)
            }
        }
        let unavailableProductIdentifiers = sortedMappings.compactMap { productIdentifier, _ in
            productsByIdentifier[productIdentifier] == nil ? productIdentifier : nil
        }

        return CoinProductCatalogLoadResult(
            availableProducts: availableProducts,
            unavailableProductIdentifiers: unavailableProductIdentifiers
        )
    }
}
