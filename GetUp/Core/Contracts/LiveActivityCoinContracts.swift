import Foundation

// MARK: - Stable diagnostics

/// A privacy-safe, stable identifier suitable for persistence and diagnostics.
///
/// Adapter-specific errors must be translated to one of these values before they
/// cross a domain boundary. Associated system error messages must not be logged.
enum LiveActivityCoinErrorCode: String, Codable, CaseIterable, Sendable {
    case activityAuthorizationDenied = "activity_authorization_denied"
    case activityRequestFailed = "activity_request_failed"
    case activityUpdateFailed = "activity_update_failed"
    case activityEndFailed = "activity_end_failed"
    case cloudAccountUnavailable = "cloud_account_unavailable"
    case cloudServerUnavailable = "cloud_server_unavailable"
    case cloudServerRecordChanged = "cloud_server_record_changed"
    case cloudResultUnknown = "cloud_result_unknown"
    case cloudRecordInvalid = "cloud_record_invalid"
    case cloudSchemaUnsupported = "cloud_schema_unsupported"
    case ledgerNotCurrent = "ledger_not_current"
    case ledgerEpochMismatch = "ledger_epoch_mismatch"
    case insufficientMonthlyAllowance = "insufficient_monthly_allowance"
    case insufficientPurchasedBalance = "insufficient_purchased_balance"
    case reconciliationRequired = "reconciliation_required"
    case storeProductUnavailable = "store_product_unavailable"
    case storeTransactionUnverified = "store_transaction_unverified"
    case storePurchaseFailed = "store_purchase_failed"
    case storeFinishFailed = "store_finish_failed"
    case releaseExceptionReadFailed = "release_exception_read_failed"
    case releaseExceptionWriteFailed = "release_exception_write_failed"
    case releaseExceptionDeleteFailed = "release_exception_delete_failed"
    case cancelled
    case unknown
}

protocol StableLiveActivityCoinError: Error, Sendable {
    var errorCode: LiveActivityCoinErrorCode { get }
}

// MARK: - ActivityKit boundary

enum RestrictionLiveActivityAuthorizationStatus: Equatable, Sendable {
    case enabled
    case disabled
    case unsupported
}

struct RestrictionLiveActivitySnapshot: Equatable, Sendable {
    let attributes: RestrictionLiveActivityAttributes
    let contentState: RestrictionLiveActivityAttributes.ContentState
}

protocol RestrictionLiveActivityManaging: Sendable {
    func authorizationStatus() async -> RestrictionLiveActivityAuthorizationStatus
    func activeActivities() async -> [RestrictionLiveActivitySnapshot]

    func request(
        attributes: RestrictionLiveActivityAttributes,
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws

    func update(
        activityID: UUID,
        contentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws

    func end(
        activityID: UUID,
        finalContentState: RestrictionLiveActivityAttributes.ContentState
    ) async throws
}

enum RestrictionLiveActivityError: Error, Equatable, Sendable,
    StableLiveActivityCoinError
{
    case authorizationDenied
    case requestFailed
    case updateFailed
    case endFailed

    var errorCode: LiveActivityCoinErrorCode {
        switch self {
        case .authorizationDenied: .activityAuthorizationDenied
        case .requestFailed: .activityRequestFailed
        case .updateFailed: .activityUpdateFailed
        case .endFailed: .activityEndFailed
        }
    }
}

// MARK: - CloudKit boundary

enum CloudKitRecordValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case int(Int)
    case int64(Int64)
    case date(Date)
    case uuid(UUID)
    case bool(Bool)
}

struct CloudKitRecordSnapshot: Codable, Equatable, Sendable {
    let recordType: String
    let recordName: String
    let changeTag: String?
    let fields: [String: CloudKitRecordValue]

    var schemaVersion: Int? {
        guard case let .int(value) = fields["schemaVersion"] else {
            return nil
        }
        return value
    }

    func replacingField(
        _ key: String,
        with value: CloudKitRecordValue
    ) -> CloudKitRecordSnapshot {
        var fields = fields
        fields[key] = value
        return CloudKitRecordSnapshot(
            recordType: recordType,
            recordName: recordName,
            changeTag: changeTag,
            fields: fields
        )
    }
}

struct CoinLedgerFetchRequest: Equatable, Sendable {
    let recordNames: [String]

    init(recordNames: [String]) {
        self.recordNames = recordNames
    }
}

enum CoinLedgerSavePolicy: Equatable, Sendable {
    case ifServerRecordUnchanged
}

struct CoinLedgerModifyRequest: Equatable, Sendable {
    let recordsToSave: [CloudKitRecordSnapshot]
    let recordNamesToDelete: [String]
    let isAtomic: Bool
    let savePolicy: CoinLedgerSavePolicy

    init(
        recordsToSave: [CloudKitRecordSnapshot],
        recordNamesToDelete: [String] = [],
        isAtomic: Bool = true,
        savePolicy: CoinLedgerSavePolicy = .ifServerRecordUnchanged
    ) {
        self.recordsToSave = recordsToSave
        self.recordNamesToDelete = recordNamesToDelete
        self.isAtomic = isAtomic
        self.savePolicy = savePolicy
    }
}

enum CoinLedgerDatabaseError: Error, Equatable, Sendable,
    StableLiveActivityCoinError
{
    case accountUnavailable
    case serverUnavailable
    case serverRecordChanged
    case resultUnknown
    case invalidRecord
    case unsupportedSchema
    case unexpectedRequest

    var errorCode: LiveActivityCoinErrorCode {
        switch self {
        case .accountUnavailable: .cloudAccountUnavailable
        case .serverUnavailable: .cloudServerUnavailable
        case .serverRecordChanged: .cloudServerRecordChanged
        case .resultUnknown: .cloudResultUnknown
        case .invalidRecord: .cloudRecordInvalid
        case .unsupportedSchema: .cloudSchemaUnsupported
        case .unexpectedRequest: .unknown
        }
    }
}

protocol CoinLedgerCloudDatabase: Sendable {
    func fetch(_ request: CoinLedgerFetchRequest) async throws -> [CloudKitRecordSnapshot]
    func modify(_ request: CoinLedgerModifyRequest) async throws -> [CloudKitRecordSnapshot]
}

// MARK: - Ledger boundary

struct MonthlyAllowanceCreationRequest: Equatable, Sendable {
    enum Trigger: Equatable, Sendable {
        case appForeground
        case shieldRelease
    }

    let monthID: String
    let epochID: UUID
    let trigger: Trigger
}

protocol MonthlyAllowanceRepository: Sendable {
    func createAllowanceIfNeeded(
        _ request: MonthlyAllowanceCreationRequest
    ) async throws -> MonthlyAllowance
}

struct MonthlyFreeReservationRequest: Equatable, Sendable {
    let commandID: UUID
    let occurrenceID: String
    let ruleID: UUID
    let ruleRevision: Int
    let monthID: String
    let ledgerEpochID: UUID
    let requestedFrom: ReleaseRequestSource
    let requestedAt: Date
}

struct CoinReleaseReservation: Equatable, Sendable {
    let command: ReleaseCommand
    let allowance: MonthlyAllowance?
    let account: CoinAccount?
}

struct PurchasedCoinReservationRequest: Equatable, Sendable {
    let commandID: UUID
    let occurrenceID: String
    let ruleID: UUID
    let ruleRevision: Int
    let ledgerEpochID: UUID
    let requestedFrom: ReleaseRequestSource
    let requestedAt: Date
}

struct PurchaseGrantRequest: Equatable, Sendable {
    let transaction: VerifiedCoinTransaction
    let quantity: Int
}

protocol CoinLedgerRepository: MonthlyAllowanceRepository, Sendable {
    func reserveMonthlyFree(
        _ request: MonthlyFreeReservationRequest
    ) async throws -> CoinReleaseReservation

    /// Rechecks free allowance atomically; may return monthlyFree if free funds are now available.
    func reservePurchasedCoin(
        _ request: PurchasedCoinReservationRequest
    ) async throws -> CoinReleaseReservation

    func fetchReleaseCommand(commandID: UUID) async throws -> ReleaseCommand?
    func markReleaseApplied(commandID: UUID, at date: Date) async throws -> ReleaseCommand
    func commitRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand
    func compensateRelease(commandID: UUID, at date: Date) async throws -> ReleaseCommand
    func grantPurchase(_ request: PurchaseGrantRequest) async throws -> PurchaseGrant
}

enum CoinLedgerRepositoryError: Error, Equatable, Sendable,
    StableLiveActivityCoinError
{
    case ledgerNotCurrent
    case ledgerEpochMismatch
    case insufficientMonthlyAllowance
    case insufficientPurchasedBalance
    case reconciliationRequired(commandID: UUID)
    case database(CoinLedgerDatabaseError)

    var errorCode: LiveActivityCoinErrorCode {
        switch self {
        case .ledgerNotCurrent: .ledgerNotCurrent
        case .ledgerEpochMismatch: .ledgerEpochMismatch
        case .insufficientMonthlyAllowance: .insufficientMonthlyAllowance
        case .insufficientPurchasedBalance: .insufficientPurchasedBalance
        case .reconciliationRequired: .reconciliationRequired
        case .database(let error): error.errorCode
        }
    }
}

// MARK: - StoreKit boundary

struct CoinStoreProduct: Equatable, Sendable {
    let id: String
    let displayName: String
    let displayDescription: String
    let displayPrice: String
}

struct VerifiedCoinTransaction: Equatable, Sendable {
    let id: UInt64
    let environment: PurchaseEnvironment
    let productID: String
    let purchaseDate: Date
    let revocationDate: Date?
}

enum CoinStorePurchaseResult: Equatable, Sendable {
    case verified(VerifiedCoinTransaction)
    case unverified
    case pending
    case userCancelled
}

enum CoinStoreTransactionUpdate: Equatable, Sendable {
    case verified(VerifiedCoinTransaction)
    case unverified
}

protocol CoinStorefront: Sendable {
    func products(for identifiers: Set<String>) async throws -> [CoinStoreProduct]
    func purchase(productID: String) async throws -> CoinStorePurchaseResult
    func unfinishedTransactions() async -> [CoinStoreTransactionUpdate]
    func transactionUpdates() -> AsyncStream<CoinStoreTransactionUpdate>
    func finish(transactionID: UInt64) async throws
}

enum CoinStoreError: Error, Equatable, Sendable, StableLiveActivityCoinError {
    case productUnavailable
    case transactionUnverified
    case purchaseFailed
    case finishFailed

    var errorCode: LiveActivityCoinErrorCode {
        switch self {
        case .productUnavailable: .storeProductUnavailable
        case .transactionUnverified: .storeTransactionUnverified
        case .purchaseFailed: .storePurchaseFailed
        case .finishFailed: .storeFinishFailed
        }
    }
}

// MARK: - App Group release boundary

protocol ActiveRestrictionSnapshotRepository: Sendable {
    func loadActiveRestrictionSnapshot() async throws -> ActiveRestrictionSnapshot?
    func saveActiveRestrictionSnapshot(_ snapshot: ActiveRestrictionSnapshot) async throws
}

protocol CoinBalanceSnapshotRepository: Sendable {
    func loadCoinBalanceSnapshot() async throws -> CoinBalanceSnapshot?
    func saveCoinBalanceSnapshot(_ snapshot: CoinBalanceSnapshot) async throws
}

protocol ReleaseExceptionRepository: Sendable {
    func loadReleaseExceptions() async throws -> [ReleaseException]
    /// Full replacement only; never use a stale collection for command insertion or rollback.
    func saveReleaseExceptions(_ exceptions: [ReleaseException]) async throws
    /// Atomic insert; identical persisted payload is idempotent, conflicting owner/content fails.
    func insertReleaseException(_ exception: ReleaseException) async throws -> [ReleaseException]
    /// Atomic removal matching both identifiers; unrelated owners and missing records are untouched.
    func removeReleaseException(commandID: UUID, occurrenceID: String) async throws -> [ReleaseException]
}

protocol PendingAppRoutePersisting: Sendable {
    func save(_ route: PendingAppRoute) async throws
    func load() async throws -> PendingAppRoute?
}

enum ReleaseExceptionRepositoryError: Error, Equatable, Sendable,
    StableLiveActivityCoinError
{
    case readFailed
    case writeFailed
    case deletionFailed
    case conflict

    var errorCode: LiveActivityCoinErrorCode {
        switch self {
        case .readFailed: .releaseExceptionReadFailed
        case .writeFailed: .releaseExceptionWriteFailed
        case .deletionFailed: .releaseExceptionDeleteFailed
        case .conflict: .releaseExceptionWriteFailed
        }
    }
}
