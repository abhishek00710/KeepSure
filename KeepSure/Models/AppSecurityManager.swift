import Combine
import Foundation
import LocalAuthentication
import SwiftUI

@MainActor
final class AppSecurityManager: ObservableObject {
    static let shared = AppSecurityManager()

    @Published private(set) var isLocked = false
    @Published private(set) var isAvailable = false
    @Published private(set) var biometryType: LABiometryType = .none
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard

    var isProtectionEnabled: Bool {
        defaults.object(forKey: DefaultsKeys.faceIDLockEnabled) as? Bool ?? false
    }

    var biometryLabel: String {
        switch biometryType {
        case .faceID:
            return "Face ID"
        case .touchID:
            return "Touch ID"
        default:
            return "device authentication"
        }
    }

    var protectionStatusLine: String {
        if isProtectionEnabled {
            return "\(biometryLabel) is protecting Keep Sure when you reopen it."
        }

        if isAvailable {
            return "Turn on \(biometryLabel) to keep receipts private when the app returns."
        }

        return "Biometric protection is unavailable on this device right now."
    }

    func refreshAvailability() {
        let context = LAContext()
        var error: NSError?
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        isAvailable = canEvaluate
        biometryType = context.biometryType
    }

    func setProtectionEnabled(_ enabled: Bool) async {
        refreshAvailability()

        guard enabled else {
            defaults.set(false, forKey: DefaultsKeys.faceIDLockEnabled)
            isLocked = false
            errorMessage = nil
            return
        }

        guard isAvailable else {
            defaults.set(false, forKey: DefaultsKeys.faceIDLockEnabled)
            errorMessage = "This device does not have biometric protection available right now."
            return
        }

        let authenticated = await authenticate(reason: "Turn on \(biometryLabel) to protect your Keep Sure receipts.")
        if authenticated {
            defaults.set(true, forKey: DefaultsKeys.faceIDLockEnabled)
            isLocked = false
            errorMessage = nil
        } else {
            defaults.set(false, forKey: DefaultsKeys.faceIDLockEnabled)
        }
    }

    func handleScenePhaseChange(_ phase: ScenePhase) async {
        refreshAvailability()

        switch phase {
        case .active:
            guard isProtectionEnabled, isLocked else { return }
            _ = await unlock()
        case .inactive, .background:
            guard isProtectionEnabled else { return }
            isLocked = true
        @unknown default:
            break
        }
    }

    func unlock() async -> Bool {
        guard isProtectionEnabled else {
            isLocked = false
            return true
        }

        refreshAvailability()
        guard isAvailable else {
            errorMessage = "Biometric protection is no longer available on this device."
            return false
        }

        let authenticated = await authenticate(reason: "Unlock Keep Sure to view your protected purchases.")
        if authenticated {
            isLocked = false
            errorMessage = nil
            return true
        }

        return false
    }

    private func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Not now"

        do {
            return try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )
        } catch {
            let nsError = error as NSError
            switch nsError.code {
            case LAError.userCancel.rawValue, LAError.systemCancel.rawValue, LAError.appCancel.rawValue:
                errorMessage = nil
            default:
                errorMessage = nsError.localizedDescription
            }
            return false
        }
    }
}

private enum DefaultsKeys {
    static let faceIDLockEnabled = "face_id_lock_enabled"
}
