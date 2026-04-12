import SwiftUI
import CoreData

@main
struct KeepSureApp: App {
    private let persistenceController: PersistenceController
    @StateObject private var emailSyncManager: EmailSyncManager

    init() {
        let controller = PersistenceController.shared
        persistenceController = controller
        _emailSyncManager = StateObject(wrappedValue: EmailSyncManager(container: controller.container))
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(emailSyncManager)
                .preferredColorScheme(.light)
                .task {
                    emailSyncManager.restoreSession()
                    await emailSyncManager.syncOnLaunchIfNeeded()
                }
        }
    }
}
