import Foundation

final class ImportLearningStore {
    static let shared = ImportLearningStore()

    private let defaults = UserDefaults.standard
    private let storageKey = "import_learning_store_v1"

    private init() {}

    func apply(to draft: inout ReceiptDraft) {
        let storage = load()
        var learnedChanges: [String] = []

        let originalMerchantKey = Self.normalizedKey(draft.merchantName)
        if let learnedMerchant = storage.merchantAliases[originalMerchantKey] {
            if Self.normalizedKey(draft.merchantName) != Self.normalizedKey(learnedMerchant) {
                learnedChanges.append("merchant")
            }
            draft.merchantName = learnedMerchant
        }

        let merchantKey = Self.normalizedKey(draft.merchantName)
        let productKey = Self.normalizedKey(draft.productName)
        let merchantProductKey = Self.merchantProductKey(merchant: merchantKey, product: productKey)

        if let learnedProduct = storage.productAliases[merchantProductKey] {
            if Self.normalizedKey(draft.productName) != Self.normalizedKey(learnedProduct) {
                learnedChanges.append("product name")
            }
            draft.productName = learnedProduct
        }

        let refreshedProductKey = Self.normalizedKey(draft.productName)
        let refreshedMerchantProductKey = Self.merchantProductKey(merchant: merchantKey, product: refreshedProductKey)

        if let learnedCategory = storage.merchantProductCategories[refreshedMerchantProductKey]
            ?? storage.merchantCategories[merchantKey] {
            if draft.categoryName != learnedCategory {
                learnedChanges.append("category")
            }
            draft.categoryName = learnedCategory
        }

        if let learnedWarranty = storage.merchantProductWarranties[refreshedMerchantProductKey],
           draft.warrantyStatus != .confirmed {
            if draft.warrantyStatus != learnedWarranty.status || draft.warrantyMonths != learnedWarranty.months {
                learnedChanges.append("warranty")
            }
            draft.warrantyStatus = learnedWarranty.status
            draft.warrantyMonths = learnedWarranty.months
            draft.warrantyConfidenceNote = "Keep Sure remembered how you confirmed coverage for this product before. Review it once more, then save if it still looks right."
        }

        if !learnedChanges.isEmpty {
            let uniqueChanges = Array(NSOrderedSet(array: learnedChanges)) as? [String] ?? learnedChanges
            let joined = uniqueChanges.joined(separator: ", ")
            draft.learnedAdjustmentSummary = "Adjusted from your earlier reviews: \(joined)."
        } else {
            draft.learnedAdjustmentSummary = ""
        }
    }

    func recordCorrection(from initialDraft: ReceiptDraft, to finalDraft: ReceiptDraft) {
        guard initialDraft.sourceType != "Manual" else { return }

        var storage = load()

        let initialMerchantKey = Self.normalizedKey(initialDraft.merchantName)
        let finalMerchant = finalDraft.merchantName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !initialMerchantKey.isEmpty,
           !finalMerchant.isEmpty,
           Self.normalizedKey(initialDraft.merchantName) != Self.normalizedKey(finalMerchant) {
            storage.merchantAliases[initialMerchantKey] = finalMerchant
        }

        let finalMerchantKey = Self.normalizedKey(finalMerchant)
        let initialProductKey = Self.normalizedKey(initialDraft.productName)
        let finalProduct = finalDraft.productName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalMerchantKey.isEmpty,
           !initialProductKey.isEmpty,
           !finalProduct.isEmpty,
           Self.normalizedKey(initialDraft.productName) != Self.normalizedKey(finalProduct) {
            let key = Self.merchantProductKey(merchant: finalMerchantKey, product: initialProductKey)
            storage.productAliases[key] = finalProduct
        }

        let finalProductKey = Self.normalizedKey(finalProduct)
        if !finalMerchantKey.isEmpty, !finalDraft.categoryName.isEmpty {
            storage.merchantCategories[finalMerchantKey] = finalDraft.categoryName
        }

        if !finalMerchantKey.isEmpty, !finalProductKey.isEmpty, !finalDraft.categoryName.isEmpty {
            let key = Self.merchantProductKey(merchant: finalMerchantKey, product: finalProductKey)
            storage.merchantProductCategories[key] = finalDraft.categoryName

            if finalDraft.warrantyStatus != .none, finalDraft.warrantyMonths > 0 {
                storage.merchantProductWarranties[key] = StoredWarrantyPreference(
                    status: finalDraft.warrantyStatus,
                    months: finalDraft.warrantyMonths
                )
            }
        }

        save(storage)
    }

    func forgetLearnedAdjustments(appliedTo draft: ReceiptDraft) {
        guard let baseline = draft.importBaseline else { return }

        var storage = load()

        let baselineMerchantKey = Self.normalizedKey(baseline.merchantName)
        let currentMerchantKey = Self.normalizedKey(draft.merchantName)
        let baselineProductKey = Self.normalizedKey(baseline.productName)
        let currentProductKey = Self.normalizedKey(draft.productName)

        if !baselineMerchantKey.isEmpty {
            storage.merchantAliases.removeValue(forKey: baselineMerchantKey)
        }

        if !currentMerchantKey.isEmpty, !baselineProductKey.isEmpty {
            storage.productAliases.removeValue(forKey: Self.merchantProductKey(merchant: currentMerchantKey, product: baselineProductKey))
        }

        if !currentMerchantKey.isEmpty {
            storage.merchantCategories.removeValue(forKey: currentMerchantKey)
        }

        if !currentMerchantKey.isEmpty, !currentProductKey.isEmpty {
            let key = Self.merchantProductKey(merchant: currentMerchantKey, product: currentProductKey)
            storage.merchantProductCategories.removeValue(forKey: key)
            storage.merchantProductWarranties.removeValue(forKey: key)
        }

        save(storage)
    }

    private func load() -> LearnedImportStorage {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode(LearnedImportStorage.self, from: data) else {
            return LearnedImportStorage()
        }

        return decoded
    }

    private func save(_ storage: LearnedImportStorage) {
        guard let data = try? JSONEncoder().encode(storage) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func normalizedKey(_ value: String) -> String {
        value
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "&", with: "and")
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func merchantProductKey(merchant: String, product: String) -> String {
        "\(merchant)|\(product)"
    }
}

private struct LearnedImportStorage: Codable {
    var merchantAliases: [String: String] = [:]
    var productAliases: [String: String] = [:]
    var merchantCategories: [String: String] = [:]
    var merchantProductCategories: [String: String] = [:]
    var merchantProductWarranties: [String: StoredWarrantyPreference] = [:]
}

private struct StoredWarrantyPreference: Codable {
    let statusRaw: String
    let months: Int

    init(status: WarrantyStatus, months: Int) {
        self.statusRaw = status.rawValue
        self.months = months
    }

    var status: WarrantyStatus {
        WarrantyStatus(rawValue: statusRaw) ?? .none
    }
}
