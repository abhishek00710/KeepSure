import CoreData
import Foundation
import UIKit

@objc(PurchaseRecord)
final class PurchaseRecord: NSManagedObject {
    @NSManaged var id: UUID?
    @NSManaged var productName: String?
    @NSManaged var merchantName: String?
    @NSManaged var categoryName: String?
    @NSManaged var familyOwner: String?
    @NSManaged var sourceType: String?
    @NSManaged var notes: String?
    @NSManaged var currencyCode: String?
    @NSManaged var purchaseDate: Date?
    @NSManaged var returnDeadline: Date?
    @NSManaged var warrantyExpiration: Date?
    @NSManaged var warrantyStatusRaw: String?
    @NSManaged var returnExplanation: String?
    @NSManaged var warrantyExplanation: String?
    @NSManaged var createdAt: Date?
    @NSManaged var price: Double
    @NSManaged var isArchived: Bool
    @NSManaged var returnCompleted: Bool
    @NSManaged var externalProvider: String?
    @NSManaged var externalRecordID: String?
    @NSManaged var lastSyncedAt: Date?
    @NSManaged var gmailOrderNumber: String?
    @NSManaged var gmailLifecycleStageRaw: String?
    @NSManaged var proofPreviewData: Data?
    @NSManaged var proofDocumentData: Data?
    @NSManaged var proofDocumentType: String?
    @NSManaged var proofDocumentName: String?
    @NSManaged var proofHTMLData: Data?
}

extension PurchaseRecord {
    @nonobjc class func fetchRequest() -> NSFetchRequest<PurchaseRecord> {
        NSFetchRequest<PurchaseRecord>(entityName: "PurchaseRecord")
    }

    static var recentFetchRequest: NSFetchRequest<PurchaseRecord> {
        let request = fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        return request
    }

    var wrappedProductName: String { productName ?? "Untitled purchase" }
    var wrappedMerchantName: String { merchantName ?? "Unknown merchant" }
    var wrappedCategoryName: String { categoryName ?? "General" }
    var wrappedFamilyOwner: String { ReceiptDraft.normalizedFamilyOwner(familyOwner) }
    var wrappedSourceType: String { sourceType ?? "Scan" }
    var wrappedNotes: String { notes ?? "" }
    var wrappedCurrencyCode: String { currencyCode ?? "USD" }
    var wrappedPurchaseDate: Date { purchaseDate ?? .now }
    var wrappedCreatedAt: Date { createdAt ?? wrappedPurchaseDate }
    var wrappedExternalProvider: String { externalProvider ?? "" }
    var wrappedGmailOrderNumber: String { gmailOrderNumber ?? "" }
    var wrappedProofDocumentType: String { proofDocumentType ?? "" }
    var wrappedProofDocumentName: String { proofDocumentName ?? "" }
    var trackedReturnDays: Int {
        guard let purchaseDate, let returnDeadline else { return 0 }
        return max(Calendar.current.dateComponents([.day], from: purchaseDate, to: returnDeadline).day ?? 0, 0)
    }
    var trackedWarrantyMonths: Int {
        guard let purchaseDate, let warrantyExpiration else { return 0 }
        return max(Calendar.current.dateComponents([.month], from: purchaseDate, to: warrantyExpiration).month ?? 0, 0)
    }
    var wrappedReturnExplanation: String {
        let stored = returnExplanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty {
            return stored
        }
        return ProtectionExplanationBuilder.returnExplanation(
            merchant: wrappedMerchantName,
            sourceType: wrappedSourceType,
            returnDays: trackedReturnDays
        )
    }
    var wrappedWarrantyExplanation: String {
        let stored = warrantyExplanation?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !stored.isEmpty {
            return stored
        }
        return ProtectionExplanationBuilder.warrantyExplanation(
            status: warrantyStatus,
            months: warrantyStatus == .none ? 0 : trackedWarrantyMonths,
            evidenceNote: warrantyStatus.reviewGuidance
        )
    }
    var hasRichHTMLProof: Bool { proofHTMLData != nil }
    var isReturnHandled: Bool { returnCompleted }
    var hasReceiptProof: Bool { proofPreviewData != nil || proofDocumentData != nil }
    var receiptPreviewImage: UIImage? {
        guard let proofPreviewData else { return nil }
        return UIImage(data: proofPreviewData)
    }
    var warrantyStatus: WarrantyStatus { WarrantyStatus(rawValue: warrantyStatusRaw ?? "") ?? .none }
    var gmailLifecycleStage: GmailOrderStage {
        GmailOrderStage(rawValue: gmailLifecycleStageRaw ?? "") ?? .unknown
    }
    var estimatedWarrantyExpiration: Date? { warrantyStatus == .estimated ? warrantyExpiration : nil }
    var confirmedWarrantyExpiration: Date? { warrantyStatus == .confirmed ? warrantyExpiration : nil }
    var hasVisibleWarranty: Bool { confirmedWarrantyExpiration != nil }
    var hasUncertainMerchant: Bool { wrappedMerchantName == "Unknown merchant" }
    var hasUncertainProduct: Bool { wrappedProductName == "Untitled purchase" || wrappedProductName == "Scanned purchase" }
    var needsWarrantyConfirmation: Bool { warrantyStatus == .estimated }
    var needsReview: Bool { !reviewReasons.isEmpty }
    var primaryReviewReason: String { reviewReasons.first ?? "Review details" }

    var reviewReasons: [String] {
        var reasons: [String] = []

        if needsWarrantyConfirmation {
            reasons.append("Warranty estimate needs confirmation")
        }

        if hasUncertainMerchant {
            reasons.append("Merchant needs review")
        }

        if hasUncertainProduct {
            reasons.append("Product name needs review")
        }

        if wrappedNotes.localizedCaseInsensitiveContains("review") {
            reasons.append("Imported details should be checked")
        }

        return Array(NSOrderedSet(array: reasons)) as? [String] ?? reasons
    }

    var timelineItems: [(label: String, date: Date)] {
        [
            (!isReturnHandled ? returnDeadline.map { ("Return", $0) } : nil),
            confirmedWarrantyExpiration.map { ("Warranty", $0) }
        ]
        .compactMap { $0 }
        .sorted { $0.date < $1.date }
    }

    var nextDeadline: (label: String, date: Date)? {
        let futureItems = timelineItems.filter { $0.date >= Calendar.current.startOfDay(for: .now) }
        return futureItems.first ?? timelineItems.last
    }

    var urgency: PurchaseUrgency {
        PurchaseUrgency(deadline: nextDeadline?.date)
    }

    var statusLine: String {
        if wrappedSourceType == "Email", gmailLifecycleStage != .unknown {
            let stageLabel = gmailLifecycleStage.statusLineTitle
            if let syncedAt = lastSyncedAt {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .full
                let relativeText = formatter.localizedString(for: syncedAt, relativeTo: .now)
                return "\(stageLabel) \(relativeText)"
            }

            return stageLabel
        }

        guard let nextDeadline else {
            return "Receipt saved"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeText = formatter.localizedString(for: nextDeadline.date, relativeTo: .now)
        return "\(nextDeadline.label) \(relativeText)"
    }
}
