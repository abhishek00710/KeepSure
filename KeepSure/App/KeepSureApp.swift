import SwiftUI
import CoreData

@main
struct KeepSureApp: App {
    private let persistenceController: PersistenceController
    @StateObject private var emailSyncManager: EmailSyncManager
    @StateObject private var appModeManager: AppModeManager

    init() {
        let controller = PersistenceController.shared
        persistenceController = controller
        _emailSyncManager = StateObject(wrappedValue: EmailSyncManager(container: controller.container))
        _appModeManager = StateObject(wrappedValue: AppModeManager(persistenceController: controller))
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(emailSyncManager)
                .environmentObject(appModeManager)
                .preferredColorScheme(.light)
                .task {
                    emailSyncManager.restoreSession()
                    appModeManager.prepareDataForCurrentMode()
                    if appModeManager.selectedMode == .live {
                        await emailSyncManager.syncOnLaunchIfNeeded()
                    }
                }
        }
    }
}
