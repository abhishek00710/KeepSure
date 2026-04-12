import CoreData
import Foundation

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
    @NSManaged var createdAt: Date?
    @NSManaged var price: Double
    @NSManaged var isArchived: Bool
    @NSManaged var externalProvider: String?
    @NSManaged var externalRecordID: String?
    @NSManaged var lastSyncedAt: Date?
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
    var wrappedFamilyOwner: String { familyOwner ?? "You" }
    var wrappedSourceType: String { sourceType ?? "Scan" }
    var wrappedNotes: String { notes ?? "" }
    var wrappedCurrencyCode: String { currencyCode ?? "USD" }
    var wrappedPurchaseDate: Date { purchaseDate ?? .now }
    var wrappedCreatedAt: Date { createdAt ?? wrappedPurchaseDate }
    var wrappedExternalProvider: String { externalProvider ?? "" }

    var timelineItems: [(label: String, date: Date)] {
        [
            returnDeadline.map { ("Return", $0) },
            warrantyExpiration.map { ("Warranty", $0) }
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
        guard let nextDeadline else {
            return "Receipt saved"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let relativeText = formatter.localizedString(for: nextDeadline.date, relativeTo: .now)
        return "\(nextDeadline.label) \(relativeText)"
    }
}
