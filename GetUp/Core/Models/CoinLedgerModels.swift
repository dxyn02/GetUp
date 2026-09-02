import Foundation

enum LedgerEpochReason: String, Codable, Equatable, Hashable, Sendable {
    case initialSetup
    case userConfirmedResetAfterDeletion
}

struct LedgerEpoch: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let epochID: UUID
    let createdAt: Date
    let reason: LedgerEpochReason
    let suppressedFreeMonthID: String?
    let disclosureVersion: Int

    init(
        schemaVersion: Int = LedgerEpoch.currentSchemaVersion,
        epochID: UUID,
        createdAt: Date,
        reason: LedgerEpochReason,
        suppressedFreeMonthID: String?,
        disclosureVersion: Int
    ) {
        self.schemaVersion = schemaVersion
        self.epochID = epochID
        self.createdAt = createdAt
        self.reason = reason
        self.suppressedFreeMonthID = suppressedFreeMonthID
        self.disclosureVersion = disclosureVersion
    }
}

struct CoinAccount: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let purchasedAvailable: Int
    let purchasedReserved: Int
    let revision: Int
    let updatedAt: Date

    var purchasedUsable: Int {
        purchasedAvailable - purchasedReserved
    }

    init(
        schemaVersion: Int = CoinAccount.currentSchemaVersion,
        purchasedAvailable: Int,
        purchasedReserved: Int,
        revision: Int,
        updatedAt: Date
    ) throws {
        guard
            purchasedAvailable >= 0,
            purchasedReserved >= 0,
            purchasedReserved <= purchasedAvailable,
            revision >= 0
        else {
            throw LiveActivityCoinModelError.invalidPurchasedBalance
        }

        self.schemaVersion = schemaVersion
        self.purchasedAvailable = purchasedAvailable
        self.purchasedReserved = purchasedReserved
        self.revision = revision
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            purchasedAvailable: container.decode(Int.self, forKey: .purchasedAvailable),
            purchasedReserved: container.decode(Int.self, forKey: .purchasedReserved),
            revision: container.decode(Int.self, forKey: .revision),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

struct MonthlyAllowance: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let monthID: String
    let quota: Int
    let used: Int
    let reserved: Int
    let creationDate: Date
    let updatedAt: Date

    var available: Int {
        quota - used - reserved
    }

    init(
        schemaVersion: Int = MonthlyAllowance.currentSchemaVersion,
        monthID: String,
        quota: Int,
        used: Int,
        reserved: Int,
        creationDate: Date,
        updatedAt: Date
    ) throws {
        guard
            quota >= 0,
            used >= 0,
            reserved >= 0,
            used + reserved <= quota
        else {
            throw LiveActivityCoinModelError.invalidMonthlyAllowanceBalance
        }

        self.schemaVersion = schemaVersion
        self.monthID = monthID
        self.quota = quota
        self.used = used
        self.reserved = reserved
        self.creationDate = creationDate
        self.updatedAt = updatedAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            monthID: container.decode(String.self, forKey: .monthID),
            quota: container.decode(Int.self, forKey: .quota),
            used: container.decode(Int.self, forKey: .used),
            reserved: container.decode(Int.self, forKey: .reserved),
            creationDate: container.decode(Date.self, forKey: .creationDate),
            updatedAt: container.decode(Date.self, forKey: .updatedAt)
        )
    }
}

enum PurchaseEnvironment: String, Codable, Equatable, Hashable, Sendable {
    case sandbox
    case production
}

enum PurchaseVerificationState: String, Codable, Equatable, Hashable, Sendable {
    case verified
}

struct PurchaseGrant: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let transactionID: UInt64
    let environment: PurchaseEnvironment
    let productID: String
    let quantity: Int
    let purchaseDate: Date
    let verificationState: PurchaseVerificationState
    let adjustedQuantity: Int

    var remainingQuantity: Int {
        quantity - adjustedQuantity
    }

    init(
        schemaVersion: Int = PurchaseGrant.currentSchemaVersion,
        transactionID: UInt64,
        environment: PurchaseEnvironment,
        productID: String,
        quantity: Int,
        purchaseDate: Date,
        adjustedQuantity: Int
    ) throws {
        guard
            transactionID > 0,
            !productID.isEmpty,
            quantity > 0,
            (0...quantity).contains(adjustedQuantity)
        else {
            throw LiveActivityCoinModelError.invalidPurchaseAdjustment
        }

        self.schemaVersion = schemaVersion
        self.transactionID = transactionID
        self.environment = environment
        self.productID = productID
        self.quantity = quantity
        self.purchaseDate = purchaseDate
        self.verificationState = .verified
        self.adjustedQuantity = adjustedQuantity
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let verificationState = try container.decode(
            PurchaseVerificationState.self,
            forKey: .verificationState
        )
        guard verificationState == .verified else {
            throw LiveActivityCoinModelError.invalidPurchaseAdjustment
        }

        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            transactionID: container.decode(UInt64.self, forKey: .transactionID),
            environment: container.decode(PurchaseEnvironment.self, forKey: .environment),
            productID: container.decode(String.self, forKey: .productID),
            quantity: container.decode(Int.self, forKey: .quantity),
            purchaseDate: container.decode(Date.self, forKey: .purchaseDate),
            adjustedQuantity: container.decode(Int.self, forKey: .adjustedQuantity)
        )
    }
}

enum CoinLedgerEventKind: String, Codable, Equatable, Hashable, Sendable {
    case purchaseGrant
    case freeGrant
    case reservation
    case spend
    case release
    case refundAdjustment
    case reversal
}

enum CoinLedgerEventSource: String, Codable, Equatable, Hashable, Sendable {
    case monthlyFree
    case purchased
    case none
}

struct CoinLedgerEvent: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let eventID: String
    let kind: CoinLedgerEventKind
    let source: CoinLedgerEventSource
    let quantity: Int
    let relatedTransactionID: UInt64?
    let relatedCommandID: UUID?
    let occurrenceID: String?
    let createdAt: Date

    init(
        schemaVersion: Int = CoinLedgerEvent.currentSchemaVersion,
        eventID: String,
        kind: CoinLedgerEventKind,
        source: CoinLedgerEventSource,
        quantity: Int,
        relatedTransactionID: UInt64?,
        relatedCommandID: UUID?,
        occurrenceID: String?,
        createdAt: Date
    ) throws {
        guard !eventID.isEmpty, quantity > 0 else {
            throw LiveActivityCoinModelError.invalidCoinLedgerEvent
        }

        self.schemaVersion = schemaVersion
        self.eventID = eventID
        self.kind = kind
        self.source = source
        self.quantity = quantity
        self.relatedTransactionID = relatedTransactionID
        self.relatedCommandID = relatedCommandID
        self.occurrenceID = occurrenceID
        self.createdAt = createdAt
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            eventID: container.decode(String.self, forKey: .eventID),
            kind: container.decode(CoinLedgerEventKind.self, forKey: .kind),
            source: container.decode(CoinLedgerEventSource.self, forKey: .source),
            quantity: container.decode(Int.self, forKey: .quantity),
            relatedTransactionID: container.decodeIfPresent(
                UInt64.self,
                forKey: .relatedTransactionID
            ),
            relatedCommandID: container.decodeIfPresent(
                UUID.self,
                forKey: .relatedCommandID
            ),
            occurrenceID: container.decodeIfPresent(String.self, forKey: .occurrenceID),
            createdAt: container.decode(Date.self, forKey: .createdAt)
        )
    }
}

enum CoinBalanceSyncState: String, Codable, Equatable, Hashable, Sendable {
    case setupRequired
    case current
    case syncing
    case stale
    case unavailable
    case deletionConfirmed
    case resetRequired
}

struct CoinBalanceSnapshot: Codable, Equatable, Hashable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let purchasedAvailable: Int
    let currentMonthID: String
    let freeAvailable: Int
    let syncState: CoinBalanceSyncState
    let syncedAt: Date
    let ledgerEpochID: UUID?
    let hadConfirmedLedger: Bool

    init(
        schemaVersion: Int = CoinBalanceSnapshot.currentSchemaVersion,
        purchasedAvailable: Int,
        currentMonthID: String,
        freeAvailable: Int,
        syncState: CoinBalanceSyncState,
        syncedAt: Date,
        ledgerEpochID: UUID?,
        hadConfirmedLedger: Bool
    ) throws {
        guard
            purchasedAvailable >= 0,
            (0...2).contains(freeAvailable),
            syncState != .current || (ledgerEpochID != nil && hadConfirmedLedger)
        else {
            throw LiveActivityCoinModelError.invalidCoinBalanceSnapshot
        }

        self.schemaVersion = schemaVersion
        self.purchasedAvailable = purchasedAvailable
        self.currentMonthID = currentMonthID
        self.freeAvailable = freeAvailable
        self.syncState = syncState
        self.syncedAt = syncedAt
        self.ledgerEpochID = ledgerEpochID
        self.hadConfirmedLedger = hadConfirmedLedger
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            schemaVersion: container.decode(Int.self, forKey: .schemaVersion),
            purchasedAvailable: container.decode(Int.self, forKey: .purchasedAvailable),
            currentMonthID: container.decode(String.self, forKey: .currentMonthID),
            freeAvailable: container.decode(Int.self, forKey: .freeAvailable),
            syncState: container.decode(CoinBalanceSyncState.self, forKey: .syncState),
            syncedAt: container.decode(Date.self, forKey: .syncedAt),
            ledgerEpochID: container.decodeIfPresent(UUID.self, forKey: .ledgerEpochID),
            hadConfirmedLedger: container.decode(Bool.self, forKey: .hadConfirmedLedger)
        )
    }
}
