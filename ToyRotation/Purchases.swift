import Foundation
import Security
import StoreKit

private actor TrialVault {
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hgsldswk.toyrotation.trial",
        kSecAttrAccount as String: "paid-first-open"
    ]

    func load(now: Date) -> Entitlement {
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        if SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
           let bytes = result as? Data, let entitlement = try? JSONDecoder().decode(Entitlement.self, from: bytes) {
            return entitlement
        }
        var entitlement = Entitlement(firstOpen: now)
        if !Launch.isFree { entitlement.proStartedAt = now }
        save(entitlement)
        return entitlement
    }

    func save(_ value: Entitlement) {
        var dates = value
        dates.purchasedPro = false
        guard let bytes = try? JSONEncoder().encode(dates) else { return }
        let attributes = [kSecValueData as String: bytes]
        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = bytes
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(item as CFDictionary, nil)
        }
    }
}

@MainActor
final class Purchases: ObservableObject {
    static let shared = Purchases()

    func hasPro(at now: Date) -> Bool { entitlement?.hasPro(at: now) ?? Launch.isFree }

    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var products: [Product] = []
    @Published private(set) var busy = false
    @Published var message: String?

    let proID = Bundle.main.object(forInfoDictionaryKey: "ToyRotationProProductID") as? String ?? "com.hgsldswk.toyrotation.pro"
    let trialID = Bundle.main.object(forInfoDictionaryKey: "ToyRotationTrialProductID") as? String ?? "com.hgsldswk.toyrotation.trial"
    private let vault = TrialVault()
    private var listener: Task<Void, Never>?
    private var revision = 0
    private var testMode = false

    deinit { listener?.cancel() }

    func start(now: Date, testing: Bool, expired: Bool) async {
        testMode = testing
        if testing {
            entitlement = Entitlement(firstOpen: expired ? now.addingTimeInterval(-30 * 86_400) : now)
            return
        }
        var saved = await vault.load(now: now)
        if !Launch.isFree && saved.proStartedAt == nil {
            saved.proStartedAt = now
            await vault.save(saved)
        }
        entitlement = saved
        guard !Launch.isFree else { return }
        listener = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard !Task.isCancelled else { return }
                if case .verified(let transaction) = result,
                   self?.proID == transaction.productID || self?.trialID == transaction.productID {
                    await self?.apply(transaction)
                }
            }
        }
        await refresh()
    }

    func refresh() async {
        guard !testMode, !Launch.isFree else { return }
        revision += 1
        let stamp = revision
        var pro = false
        var trial: Date?
        for await result in StoreKit.Transaction.currentEntitlements {
            guard case .verified(let transaction) = result, transaction.revocationDate == nil else { continue }
            if transaction.productID == proID { pro = true }
            if transaction.productID == trialID { trial = transaction.originalPurchaseDate }
        }
        guard revision == stamp, var value = entitlement else { return }
        value.purchasedPro = pro
        if let trial { value.trialClaimedAt = min(value.trialClaimedAt ?? trial, trial) }
        entitlement = value
        await vault.save(value)
    }

    func loadProducts() async {
        guard !testMode, !Launch.isFree, products.isEmpty else { return }
        do { products = try await Product.products(for: [proID, trialID]) }
        catch { message = L.t("purchase.catalog-error") }
    }

    func purchase(_ product: Product) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)): await apply(transaction)
            case .success(.unverified): message = L.t("purchase.verify-error")
            case .pending: message = L.t("purchase.pending")
            case .userCancelled: break
            @unknown default: message = L.t("purchase.verify-error")
            }
        } catch { message = L.t("purchase.error") }
    }

    func restore() async {
        guard !busy, !Launch.isFree else { return }
        busy = true
        defer { busy = false }
        if testMode {
            var value = entitlement ?? Entitlement()
            value.purchasedPro = true
            entitlement = value
            message = L.t("purchase.restored")
            return
        }
        do {
            try await AppStore.sync()
            await refresh()
            message = L.t(entitlement?.purchasedPro == true || entitlement?.trialClaimedAt != nil
                          ? "purchase.restored" : "purchase.none")
        } catch { message = L.t("purchase.restore-error") }
    }

    private func apply(_ transaction: StoreKit.Transaction) async {
        revision += 1
        if var value = entitlement, transaction.revocationDate == nil {
            if transaction.productID == proID { value.purchasedPro = true }
            if transaction.productID == trialID {
                value.trialClaimedAt = min(value.trialClaimedAt ?? transaction.originalPurchaseDate, transaction.originalPurchaseDate)
            }
            entitlement = value
            await vault.save(value)
        }
        await transaction.finish()
        await refresh()
    }
}

