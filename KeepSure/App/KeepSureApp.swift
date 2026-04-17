import SwiftUI
import CoreData

@main
struct KeepSureApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private let persistenceController: PersistenceController
    @StateObject private var emailSyncManager: EmailSyncManager
    @StateObject private var notificationManager: SmartNotificationManager
    @StateObject private var securityManager: AppSecurityManager

    init() {
        let controller = PersistenceController.shared
        persistenceController = controller
        _emailSyncManager = StateObject(wrappedValue: EmailSyncManager(container: controller.container))
        _notificationManager = StateObject(wrappedValue: SmartNotificationManager.shared)
        _securityManager = StateObject(wrappedValue: AppSecurityManager.shared)
    }

    var body: some Scene {
        WindowGroup {
            AppBootstrapView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
                .environmentObject(emailSyncManager)
                .environmentObject(notificationManager)
                .environmentObject(securityManager)
                .preferredColorScheme(.light)
                .task {
                    emailSyncManager.restoreSession()
                    await notificationManager.refreshAuthorizationStatus()
                    await emailSyncManager.syncOnLaunchIfNeeded()
                    securityManager.refreshAvailability()
                    await notificationManager.rescheduleAll(in: persistenceController.container)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    Task {
                        await securityManager.handleScenePhaseChange(newPhase)
                    }
                }
        }
    }
}
