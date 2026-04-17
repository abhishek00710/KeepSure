import Combine
import CoreData
import Foundation
import UserNotifications

struct NotificationDeepLink: Identifiable, Equatable {
    enum Destination: String {
        case returnWindow = "return"
        case warrantyCoverage = "warranty"
        case review
    }

    let id = UUID()
    let destination: Destination
    let purchaseURI: String

    nonisolated init?(userInfo: [AnyHashable: Any]) {
        guard
            let rawType = userInfo["type"] as? String,
            let destination = Destination(rawValue: rawType),
            let purchaseURI = userInfo["purchaseURI"] as? String,
            !purchaseURI.isEmpty
        else {
            return nil
        }

        self.destination = destination
        self.purchaseURI = purchaseURI
    }
}

@MainActor
final class SmartNotificationManager: NSObject, ObservableObject {
    static let shared = SmartNotificationManager()

    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var pendingReminderCount = 0
    @Published var pendingDeepLink: NotificationDeepLink?

    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private let reminderPrefix = "keepsure.reminder."

    private override init() {
        super.init()
        center.delegate = self
    }

    func consumePendingDeepLink() -> NotificationDeepLink? {
        let route = pendingDeepLink
        pendingDeepLink = nil
        return route
    }

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
        "Returns: \(formattedDays(returnReminderDays)) before. Warranty: \(formattedDays(warrantyReminderDays)) before. Review nudges: \(reviewNudgeLine)."
    }

    var returnReminderDays: [Int] {
        normalizedUniqueDescending([
            defaults.object(forKey: DefaultsKeys.returnReminderPrimary) as? Int ?? 7,
            defaults.object(forKey: DefaultsKeys.returnReminderSecondary) as? Int ?? 3,
            defaults.object(forKey: DefaultsKeys.returnReminderFinal) as? Int ?? 1
        ])
    }

    var warrantyReminderDays: [Int] {
        normalizedUniqueDescending([
            defaults.object(forKey: DefaultsKeys.warrantyReminderPrimary) as? Int ?? 30,
            defaults.object(forKey: DefaultsKeys.warrantyReminderFinal) as? Int ?? 7
        ])
    }

    var reviewNudgeHours: Int {
        max(defaults.object(forKey: DefaultsKeys.reviewNudgeHours) as? Int ?? 24, 1)
    }

    var reviewNudgeLine: String {
        if reviewNudgeHours < 24 {
            return "\(reviewNudgeHours) hours later"
        }

        let days = max(reviewNudgeHours / 24, 1)
        return days == 1 ? "next day" : "\(days) days later"
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

        return returnReminderDays.compactMap { days in
            makeDayBasedRequest(
                id: "\(reminderPrefix)return.\(purchase.objectID.uriRepresentation().absoluteString).\(days)",
                fireDate: scheduledDate(before: deadline, daysBefore: days),
                title: returnTitle(daysBefore: days, deadline: deadline),
                body: "\(purchase.wrappedProductName) from \(purchase.wrappedMerchantName) can still be returned until \(deadline.formatted(date: .abbreviated, time: .omitted)). \(notificationExplanationSnippet(for: purchase.wrappedReturnExplanation)) If you have already started it, open Keep Sure and mark it done.",
                userInfo: ["type": "return", "purchaseURI": purchase.objectID.uriRepresentation().absoluteString]
            )
        }
    }

    private func buildWarrantyRequests(for purchase: PurchaseRecord) -> [UNNotificationRequest] {
        guard purchase.warrantyStatus == .confirmed, let expiration = purchase.confirmedWarrantyExpiration else { return [] }

        return warrantyReminderDays.compactMap { days in
            makeDayBasedRequest(
                id: "\(reminderPrefix)warranty.\(purchase.objectID.uriRepresentation().absoluteString).\(days)",
                fireDate: scheduledDate(before: expiration, daysBefore: days),
                title: warrantyTitle(daysBefore: days, expiration: expiration),
                body: "Coverage for \(purchase.wrappedProductName) from \(purchase.wrappedMerchantName) ends on \(expiration.formatted(date: .abbreviated, time: .omitted)). \(notificationExplanationSnippet(for: purchase.wrappedWarrantyExplanation)) Keep any claim details or proof close by.",
                userInfo: ["type": "warranty", "purchaseURI": purchase.objectID.uriRepresentation().absoluteString]
            )
        }
    }

    private func buildReviewRequests(for purchase: PurchaseRecord) -> [UNNotificationRequest] {
        guard purchase.needsReview else { return [] }
        let baseDate = purchase.lastSyncedAt ?? purchase.wrappedCreatedAt
        guard let reminderDate = Calendar.current.date(byAdding: .hour, value: reviewNudgeHours, to: baseDate) else { return [] }

        return [
            makeTimedRequest(
                id: "\(reminderPrefix)review.\(purchase.objectID.uriRepresentation().absoluteString)",
                fireDate: reminderDate,
                title: "Finish one quick review",
                body: "Keep Sure still has a few uncertain details for \(purchase.wrappedProductName). \(notificationExplanationSnippet(for: purchase.primaryReviewReason)) A quick pass now will make the reminders more trustworthy.",
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

    private func notificationExplanationSnippet(for explanation: String) -> String {
        let trimmed = explanation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let firstSentence = trimmed
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? trimmed

        let softened = firstSentence
            .replacingOccurrences(of: "Keep Sure is tracking ", with: "")
            .replacingOccurrences(of: "Keep Sure has enough direct warranty proof to track ", with: "")
            .replacingOccurrences(of: "Keep Sure found partial warranty clues and is holding ", with: "")
            .replacingOccurrences(of: "Keep Sure found partial warranty clues, but ", with: "")
            .replacingOccurrences(of: "Keep Sure has not found dependable warranty proof yet, so ", with: "")

        let compact = softened.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !compact.isEmpty else { return "" }

        return "Why: \(compact.prefix(110))\(compact.count > 110 ? "…" : "")."
    }

    private func normalizedUniqueDescending(_ values: [Int]) -> [Int] {
        Array(Set(values.map { max($0, 1) })).sorted(by: >)
    }

    private func formattedDays(_ values: [Int]) -> String {
        values
            .sorted(by: >)
            .map { $0 == 1 ? "1 day" : "\($0) days" }
            .formatted(.list(type: .and))
    }
}

extension SmartNotificationManager: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .badge]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        guard let route = NotificationDeepLink(userInfo: userInfo) else { return }

        await MainActor.run {
            self.pendingDeepLink = route
        }
    }
}

private enum DefaultsKeys {
    static let smartAlertsEnabled = "smart_alerts_enabled"
    static let returnReminderPrimary = "return_reminder_primary_days"
    static let returnReminderSecondary = "return_reminder_secondary_days"
    static let returnReminderFinal = "return_reminder_final_days"
    static let warrantyReminderPrimary = "warranty_reminder_primary_days"
    static let warrantyReminderFinal = "warranty_reminder_final_days"
    static let reviewNudgeHours = "review_nudge_hours"
}

private extension Calendar {
    func isDateInNextWeek(_ date: Date) -> Bool {
        guard let weekFromNow = self.date(byAdding: .day, value: 7, to: .now) else { return false }
        return isDate(date, inSameDayAs: weekFromNow)
    }
}
