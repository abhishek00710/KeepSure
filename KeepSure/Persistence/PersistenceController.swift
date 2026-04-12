import CoreData
import Foundation

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()
    static let preview = PersistenceController(inMemory: true)

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        let model = Self.makeModel()
        container = NSPersistentContainer(name: "KeepSureModel", managedObjectModel: model)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.persistentStoreDescriptions.forEach { description in
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }

        container.loadPersistentStores { _, error in
            if let error {
                fatalError("Failed to load Core Data store: \(error.localizedDescription)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump

        seedIfNeeded()
    }

    private func seedIfNeeded() {
        let context = container.viewContext
        let request = PurchaseRecord.fetchRequest()
        request.fetchLimit = 1

        do {
            let existing = try context.count(for: request)
            guard existing == 0 else { return }

            let now = Date()
            let examples: [(String, String, String, String, Double, Int, Int, Int)] = [
                ("Dyson Airwrap", "Sephora", "Beauty", "You", 599, -12, 30, 24),
                ("Nintendo Switch OLED", "Target", "Electronics", "Aarav", 349, -6, 15, 12),
                ("Patio String Lights", "Costco", "Home", "Maya", 119, -20, 90, 24),
                ("Carry-on Suitcase", "Away", "Travel", "You", 275, -40, 100, 60)
            ]

            for item in examples {
                let purchase = PurchaseRecord(context: context)
                let purchaseDate = Calendar.current.date(byAdding: .day, value: item.5, to: now) ?? now
                let windows = PurchaseWindows.makeDeadlines(
                    purchaseDate: purchaseDate,
                    returnDays: item.6,
                    warrantyMonths: item.7
                )

                purchase.id = UUID()
                purchase.productName = item.0
                purchase.merchantName = item.1
                purchase.categoryName = item.2
                purchase.familyOwner = item.3
                purchase.price = item.4
                purchase.purchaseDate = purchaseDate
                purchase.returnDeadline = windows.returnDeadline
                purchase.warrantyExpiration = windows.warrantyExpiration
                purchase.sourceType = item.1 == "Target" ? "Email" : "Scan"
                purchase.currencyCode = "USD"
                purchase.notes = "Seeded sample purchase for the first dashboard experience."
                purchase.createdAt = purchaseDate
                purchase.isArchived = false
                purchase.externalProvider = item.1 == "Target" ? "demo" : nil
                purchase.externalRecordID = item.1 == "Target" ? UUID().uuidString : nil
                purchase.lastSyncedAt = item.1 == "Target" ? .now : nil
            }

            try context.save()
        } catch {
            assertionFailure("Failed to seed starter purchases: \(error.localizedDescription)")
        }
    }

    private static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()
        entity.name = "PurchaseRecord"
        entity.managedObjectClassName = NSStringFromClass(PurchaseRecord.self)

        entity.properties = [
            attribute(name: "id", type: .UUIDAttributeType),
            attribute(name: "productName", type: .stringAttributeType),
            attribute(name: "merchantName", type: .stringAttributeType),
            attribute(name: "categoryName", type: .stringAttributeType),
            attribute(name: "familyOwner", type: .stringAttributeType),
            attribute(name: "sourceType", type: .stringAttributeType),
            attribute(name: "notes", type: .stringAttributeType, optional: true),
            attribute(name: "currencyCode", type: .stringAttributeType),
            attribute(name: "purchaseDate", type: .dateAttributeType),
            attribute(name: "returnDeadline", type: .dateAttributeType, optional: true),
            attribute(name: "warrantyExpiration", type: .dateAttributeType, optional: true),
            attribute(name: "createdAt", type: .dateAttributeType),
            attribute(name: "price", type: .doubleAttributeType, optional: false),
            attribute(name: "isArchived", type: .booleanAttributeType, optional: false),
            attribute(name: "externalProvider", type: .stringAttributeType, optional: true),
            attribute(name: "externalRecordID", type: .stringAttributeType, optional: true),
            attribute(name: "lastSyncedAt", type: .dateAttributeType, optional: true)
        ]

        model.entities = [entity]
        return model
    }

    private static func attribute(
        name: String,
        type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        return attribute
    }
}
