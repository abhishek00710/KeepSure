import Combine
import Foundation

enum AppMode: String, CaseIterable, Identifiable {
    case demo
    case live

    var id: String { rawValue }

    var title: String {
        switch self {
        case .demo: return "Demo mode"
        case .live: return "Live mode"
        }
    }

    var shortTitle: String {
        switch self {
        case .demo: return "Demo"
        case .live: return "Live"
        }
    }

    var summary: String {
        switch self {
        case .demo:
            return "Loads curated sample purchases so the app feels complete right away."
        case .live:
            return "Starts clean, then syncs real purchases from Gmail into Core Data."
        }
    }

    var resetSummary: String {
        switch self {
        case .demo:
            return "This replaces current purchases with prefilled sample data."
        case .live:
            return "This clears existing purchases so Gmail can become the source of truth."
        }
    }
}

@MainActor
final class AppModeManager: ObservableObject {
    @Published private(set) var selectedMode: AppMode?
    @Published private(set) var isApplying = false
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let persistenceController: PersistenceController

    init(persistenceController: PersistenceController) {
        self.persistenceController = persistenceController
        self.selectedMode = AppMode(rawValue: defaults.string(forKey: DefaultsKeys.appMode) ?? "")
    }

    var requiresSelection: Bool {
        selectedMode == nil
    }

    func prepareDataForCurrentMode() {
        guard let selectedMode else { return }

        do {
            switch selectedMode {
            case .demo:
                try persistenceController.ensureDemoDataIfNeeded()
            case .live:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func select(_ mode: AppMode) async {
        guard !isApplying else { return }

        isApplying = true
        errorMessage = nil
        defer { isApplying = false }

        do {
            switch mode {
            case .demo:
                try persistenceController.resetToDemoMode()
            case .live:
                try persistenceController.resetToLiveMode()
            }

            defaults.set(mode.rawValue, forKey: DefaultsKeys.appMode)
            selectedMode = mode
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private enum DefaultsKeys {
    static let appMode = "app_mode"
}
