import Foundation

struct PurchaseWindows: Equatable {
    let returnDeadline: Date?
    let warrantyExpiration: Date?

    static func makeDeadlines(
        purchaseDate: Date,
        returnDays: Int,
        warrantyMonths: Int,
        calendar: Calendar = .current
    ) -> PurchaseWindows {
        let returnDeadline = returnDays > 0
            ? calendar.date(byAdding: .day, value: returnDays, to: purchaseDate)
            : nil
        let warrantyExpiration = warrantyMonths > 0
            ? calendar.date(byAdding: .month, value: warrantyMonths, to: purchaseDate)
            : nil

        return PurchaseWindows(
            returnDeadline: returnDeadline,
            warrantyExpiration: warrantyExpiration
        )
    }
}

enum PurchaseUrgency {
    case critical
    case soon
    case calm
    case expired

    init(referenceDate: Date = .now, deadline: Date?) {
        guard let deadline else {
            self = .calm
            return
        }

        let daysRemaining = Calendar.current.dateComponents([.day], from: referenceDate, to: deadline).day ?? 0

        switch daysRemaining {
        case ..<0:
            self = .expired
        case 0...3:
            self = .critical
        case 4...14:
            self = .soon
        default:
            self = .calm
        }
    }

    var label: String {
        switch self {
        case .critical:
            "Act now"
        case .soon:
            "Coming up"
        case .calm:
            "On track"
        case .expired:
            "Expired"
        }
    }
}
