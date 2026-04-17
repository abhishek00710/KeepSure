import SwiftUI
import CoreData

@main
struct KeepSureApp: App {
    private let persistenceController: PersistenceController
    @StateObject private var emailSyncManager: EmailSyncManager
    @StateObject private var appModeManager: AppModeManager
    @StateObject private var notificationManager: SmartNotificationManager

    init() {
        let controller = PersistenceController.shared
        persistenceController = controller
        _emailSyncManager = StateObject(wrappedValue: EmailSyncManager(container: controller.container))
        _appModeManager = StateObject(wrappedValue: AppModeManager(persistenceController: controller))
        _notificationManager = StateObject(wrappedValue: SmartNotificationManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(emailSyncManager)
                .environmentObject(appModeManager)
                .environmentObject(notificationManager)
                .preferredColorScheme(.light)
                .task {
                    emailSyncManager.restoreSession()
                    appModeManager.prepareDataForCurrentMode()
                    await notificationManager.refreshAuthorizationStatus()
                    if appModeManager.selectedMode == .live {
                        await emailSyncManager.syncOnLaunchIfNeeded()
                    }
                    await notificationManager.rescheduleAll(in: persistenceController.container)
                }
        }
    }
}
