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
            attribute(name: "warrantyStatusRaw", type: .stringAttributeType, optional: true),
            attribute(name: "returnExplanation", type: .stringAttributeType, optional: true),
            attribute(name: "warrantyExplanation", type: .stringAttributeType, optional: true),
            attribute(name: "createdAt", type: .dateAttributeType),
            attribute(name: "price", type: .doubleAttributeType, optional: false),
            attribute(name: "isArchived", type: .booleanAttributeType, optional: false),
            attribute(name: "returnCompleted", type: .booleanAttributeType, optional: false, defaultValue: false),
            attribute(name: "externalProvider", type: .stringAttributeType, optional: true),
            attribute(name: "externalRecordID", type: .stringAttributeType, optional: true),
            attribute(name: "lastSyncedAt", type: .dateAttributeType, optional: true),
            attribute(name: "gmailOrderNumber", type: .stringAttributeType, optional: true),
            attribute(name: "gmailLifecycleStageRaw", type: .stringAttributeType, optional: true),
            attribute(name: "proofPreviewData", type: .binaryDataAttributeType, optional: true),
            attribute(name: "proofDocumentData", type: .binaryDataAttributeType, optional: true),
            attribute(name: "proofDocumentType", type: .stringAttributeType, optional: true),
            attribute(name: "proofDocumentName", type: .stringAttributeType, optional: true),
            attribute(name: "proofHTMLData", type: .binaryDataAttributeType, optional: true)
        ]

        model.entities = [entity]
        return model
    }

    private static func attribute(
        name: String,
        type: NSAttributeType,
        optional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }
}
