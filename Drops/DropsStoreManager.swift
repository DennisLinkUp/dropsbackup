import StoreKit
import Foundation

// Typealias um Naming-Konflikt mit dem Projekt-eigenen `AppStore` zu umgehen
private typealias SKAppStore = StoreKit.AppStore

// MARK: - Drops+ Store Manager (StoreKit 2)

@MainActor
final class DropsStoreManager: ObservableObject {

    static let shared = DropsStoreManager()

    /// Produkt-ID im App Store Connect — Typ: Non-Consumable (Einmalkauf)
    let productID = "com.dennis.drops.dropsplus"

    @Published private(set) var isPlusUser = false
    @Published private(set) var product: Product? = nil
    @Published var isLoading = false
    @Published var purchaseError: String? = nil

    private var updatesTask: Task<Void, Never>?

    private init() {
        Task {
            await loadProduct()
            await refreshEntitlements()
        }
        updatesTask = listenForTransactionUpdates()
    }

    deinit { updatesTask?.cancel() }

    // MARK: - Produkt laden

    func loadProduct() async {
        do {
            let products = try await Product.products(for: [productID])
            product = products.first
        } catch {
            print("DropsStoreManager: Produkt konnte nicht geladen werden:", error)
        }
    }

    // MARK: - Berechtigungen prüfen

    func refreshEntitlements() async {
        var found = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let tx) = result,
               tx.productID == productID,
               tx.revocationDate == nil {
                found = true
                await tx.finish()
            }
        }
        applyPlusStatus(found)
    }

    // MARK: - Kauf

    func purchase() async {
        guard let product else {
            purchaseError = "Produkt konnte nicht geladen werden. Bitte versuche es erneut."
            return
        }
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let tx) = verification {
                    applyPlusStatus(true)
                    await tx.finish()
                } else {
                    purchaseError = "Kauf konnte nicht verifiziert werden. Bitte wende dich an den Support."
                }
            case .userCancelled:
                break   // kein Fehler — User hat selbst abgebrochen
            case .pending:
                purchaseError = "Kauf ausstehend (z.B. Elternfreigabe erforderlich)."
            @unknown default:
                break
            }
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Plus-Status anwenden (UI + Firebase + Notification)

    /// Setzt den Plus-Status lokal, synchronisiert nach Firebase (damit der Admin-Panel
    /// und andere Geräte den Wert sehen) und benachrichtigt den AppStore über eine
    /// Notification, damit die Paywall/UI sofort aktualisiert wird.
    private func applyPlusStatus(_ isPlus: Bool) {
        let changed = isPlusUser != isPlus
        isPlusUser = isPlus
        if changed {
            RealtimeDBManager.shared.setMyPlusStatus(isPlus)
        }
        NotificationCenter.default.post(
            name: .dropsPlusStatusChanged,
            object: nil,
            userInfo: ["isPlus": isPlus]
        )
    }

    // MARK: - Kauf wiederherstellen

    func restorePurchases() async {
        isLoading = true
        purchaseError = nil
        defer { isLoading = false }
        do {
            try await SKAppStore.sync()
            await refreshEntitlements()
        } catch {
            purchaseError = error.localizedDescription
        }
    }

    // MARK: - Transaktions-Updates (externe Käufe, Widerrufe, …)

    private func listenForTransactionUpdates() -> Task<Void, Never> {
        Task(priority: .background) {
            for await result in Transaction.updates {
                if case .verified(let tx) = result, tx.productID == self.productID {
                    await MainActor.run {
                        self.applyPlusStatus(tx.revocationDate == nil)
                    }
                    await tx.finish()
                }
            }
        }
    }
}
