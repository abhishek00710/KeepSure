import Combine
import CoreData
import Foundation
import UserNotifications

@MainActor
final class SmartNotificationManager: ObservableObject {
    static let shared = SmartNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingReminderCount = 0

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let reminderPrefix = "keepsure.reminder."

    private init() {}

    var isEnabled: Bool {
        defaults.object(forKey: DefaultsKeys.smartAlertsEnabled) as? Bool ?? true
    }

    var permissionStatusLine: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return pendingReminderCount == 0 ? "Watching quietly for the next date that matters" : "Watching \(pendingReminderCount) upcoming reminders"
        case .denied:
            return "Notifications are off in system settings"
        case .notDetermined:
            return "Permission will be requested the first time reminders are needed"
        @unknown default:
            return "Notification access is still being checked"
        }
    }

    var cadenceLine: String {
        "Returns: 7, 3, and 1 day. Warranty: 30 and 7 days. Review nudges: next day."
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        await refreshPendingCount()
    }

    func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            await refreshPendingCount()
            return true
        case .denied:
            await refreshPendingCount()
            return false
        case .notDetermined:
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                let updated = await center.notificationSettings()
                authorizationStatus = updated.authorizationStatus
                await refreshPendingCount()
                return granted
            } catch {
                let updated = await center.notificationSettings()
                authorizationStatus = updated.authorizationStatus
                await refreshPendingCount()
                return false
            }
        @unknown default:
            await refreshPendingCount()
            return false
        }
    }

    func applyPreference(enabled: Bool, container: NSPersistentContainer) async {
        defaults.set(enabled, forKey: DefaultsKeys.smartAlertsEnabled)
        if enabled {
            _ = await requestAuthorizationIfNeeded()
            await rescheduleAll(in: container)
        } else {
            await clearAllKeepSureNotifications()
        }
    }

    func rescheduleAll(in container: NSPersistentContainer) async {
        guard isEnabled else {
            await clearAllKeepSureNotifications()
            return
        }

        let allowed = await requestAuthorizationIfNeeded()
        guard allowed else {
            await clearAllKeepSureNotifications()
            return
        }

        let purchases = await fetchPurchases(in: container.viewContext)
        let requests = buildRequests(for: purchases)
        await replaceKeepSureNotifications(with: requests)
    }

    private func fetchPurchases(in context: NSManagedObjectContext) async -> [PurchaseRecord] {
        await context.perform {
            let request = PurchaseRecord.fetchRequest()
            request.sortDescriptors = [NSSortDescriptor(key: "purchaseDate", ascending: false)]
            do {
                return try context.fetch(request)
            } catch {
                return []
            }
        }
    }

    private func buildRequests(for purchases: [PurchaseRecord]) -> [UNNotificationRequest] {
        purchases
            .filter { !$0.isArchived }
            .flatMap { purchase in
                return buildReturnRequests(for: purchase)
                    + buildWarrantyRequests(for: purchase)
                    + buildReviewRequests(for: purchase)
            }
    }

    private func buildReturnRequests(for purchase: PurchaseRecord) -> [UNNotificationRequest] {
        guard !purchase.isReturnHandled, let deadline = purchase.returnDeadline else { return [] }

        let cadences = [7, 3, 1]
        return cadences.compactMap { days in
            makeDayBasedRequest(
                id: "\(reminderPrefix)return.\(purchase.objectID.uriRepresentation().absoluteString).\(days)",
                fireDate: scheduledDate(before: deadline, daysBefore: days),
                title: returnTitle(daysBefore: days, deadline: deadline),
                body: "\(purchase.wrappedProductName) from \(purchase.wrappedMerchantName) can still be returned until \(deadline.formatted(date: .abbreviated, time: .omitted)). If you have already started it, open Keep Sure and mark it done.",
                userInfo: ["type": "return", "purchaseURI": purchase.objectID.uriRepresentation().absoluteString]
            )
        }
    }

    private func buildWarrantyRequests(for purchase: PurchaseRecord) -> [UNNotificationRequest] {
        guard purchase.warrantyStatus == .confirmed, let expiration = purchase.confirmedWarrantyExpiration else { return [] }

        let cadences = [30, 7]
        return cadences.compactMap { days in
            makeDayBasedRequest(
                id: "\(reminderPrefix)warranty.\(purchase.objectID.uriRepresentation().absoluteString).\(days)",
                fireDate: scheduledDate(before: expiration, daysBefore: days),
                title: warrantyTitle(daysBefore: days, expiration: expiration),
                body: "Coverage for \(purchase.wrappedProductName) from \(purchase.wrappedMerchantName) ends on \(expiration.formatted(date: .abbreviated, time: .omitted)). Keep any claim details or proof close by.",
                userInfo: ["type": "warranty", "purchaseURI": purchase.objectID.uriRepresentation().absoluteString]
            )
        }
    }

    private func buildReviewRequests(for purchase: PurchaseRecord) -> [UNNotificationRequest] {
        guard purchase.needsReview else { return [] }
        let baseDate = purchase.lastSyncedAt ?? purchase.wrappedCreatedAt
        guard let reminderDate = Calendar.current.date(byAdding: .day, value: 1, to: baseDate) else { return [] }

        return [
            makeTimedRequest(
                id: "\(reminderPrefix)review.\(purchase.objectID.uriRepresentation().absoluteString)",
                fireDate: reminderDate,
                title: "Finish one quick review",
                body: "Keep Sure still has a few uncertain details for \(purchase.wrappedProductName). A quick pass now will make the reminders more trustworthy.",
                userInfo: ["type": "review", "purchaseURI": purchase.objectID.uriRepresentation().absoluteString]
            )
        ].compactMap { $0 }
    }

    private func makeDayBasedRequest(id: String, fireDate: Date?, title: String, body: String, userInfo: [AnyHashable: Any]) -> UNNotificationRequest? {
        guard let fireDate else { return nil }
        return makeTimedRequest(id: id, fireDate: fireDate, title: title, body: body, userInfo: userInfo)
    }

    private func makeTimedRequest(id: String, fireDate: Date, title: String, body: String, userInfo: [AnyHashable: Any]) -> UNNotificationRequest? {
        guard fireDate > Date().addingTimeInterval(300) else { return nil }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    private func replaceKeepSureNotifications(with requests: [UNNotificationRequest]) async {
        let identifiers = await keepSureIdentifiers()
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }

        for request in requests {
            do {
                try await center.add(request)
            } catch {
                continue
            }
        }

        await refreshPendingCount()
    }

    private func clearAllKeepSureNotifications() async {
        let identifiers = await keepSureIdentifiers()
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
            center.removeDeliveredNotifications(withIdentifiers: identifiers)
        }
        await refreshPendingCount()
    }

    private func keepSureIdentifiers() async -> [String] {
        let requests = await center.pendingNotificationRequests()
        return requests.map(\.identifier).filter { $0.hasPrefix(reminderPrefix) }
    }

    private func refreshPendingCount() async {
        let requests = await center.pendingNotificationRequests()
        pendingReminderCount = requests.filter { $0.identifier.hasPrefix(reminderPrefix) }.count
    }

    private func scheduledDate(before deadline: Date, daysBefore: Int) -> Date? {
        let calendar = Calendar.current
        guard let reminderDay = calendar.date(byAdding: .day, value: -daysBefore, to: deadline) else { return nil }
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: reminderDay)
    }

    private func returnTitle(daysBefore: Int, deadline: Date) -> String {
        if Calendar.current.isDateInTomorrow(deadline), daysBefore == 1 {
            return "Return window closes tomorrow"
        }

        if daysBefore == 1 {
            return "Return window closes in 1 day"
        }

        return "Return window closes in \(daysBefore) days"
    }

    private func warrantyTitle(daysBefore: Int, expiration: Date) -> String {
        if Calendar.current.isDateInNextWeek(expiration), daysBefore == 7 {
            return "Warranty ends next week"
        }

        return "Warranty check in \(daysBefore) days"
    }
}

private enum DefaultsKeys {
    static let smartAlertsEnabled = "smart_alerts_enabled"
}

private extension Calendar {
    func isDateInNextWeek(_ date: Date) -> Bool {
        guard let weekFromNow = self.date(byAdding: .day, value: 7, to: .now) else { return false }
        return isDate(date, inSameDayAs: weekFromNow)
    }
}
